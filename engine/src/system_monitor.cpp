#include <iostream>
#include <unistd.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/mount.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/IOKitLib.h>
#include <sstream>
#include <iomanip>
#include <libproc.h>
#include <mach/mach.h>
#include <IOKit/IOKitLib.h>
#include <chrono>
#include <unordered_map>

using namespace std;

// ---------- CPU ----------
double getCPUUsage() {
    host_cpu_load_info_data_t cpuinfo;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
                    (host_info_t)&cpuinfo, &count);

    static uint64_t prevTotal = 0, prevIdle = 0;

    uint64_t idle = cpuinfo.cpu_ticks[CPU_STATE_IDLE];
    uint64_t total = 0;
    for (int i = 0; i < CPU_STATE_MAX; i++)
        total += cpuinfo.cpu_ticks[i];

    uint64_t totalDiff = total - prevTotal;
    uint64_t idleDiff = idle - prevIdle;

    prevTotal = total;
    prevIdle = idle;

    if (totalDiff == 0) return 0;
    return (1.0 - (double)idleDiff / totalDiff) * 100.0;
}

// ---------- MEMORY ----------
void getMemoryPressure(double &usedGB,double &totalGB,double &pressure,double &swapUsedGB)
{
    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;

    host_statistics64(
        mach_host_self(),
        HOST_VM_INFO64,
        (host_info64_t)&vm,
        &count
    );

    uint64_t pageSize;
    size_t size = sizeof(pageSize);
    sysctlbyname("hw.pagesize", &pageSize, &size, nullptr, 0);

    uint64_t totalMem;
    sysctlbyname("hw.memsize", &totalMem, &size, nullptr, 0);

    uint64_t freeMem =
        vm.free_count * pageSize;

    uint64_t inactiveMem =
        vm.inactive_count * pageSize;

    uint64_t compressedMem =
        vm.compressor_page_count * pageSize;

    // 🔑 Apple-like reclaimability model
    const double inactiveReclaimableRatio = 0.74;

    uint64_t reclaimable =
        freeMem +
        (uint64_t)(inactiveMem * inactiveReclaimableRatio);

    uint64_t usedMem =
        totalMem - reclaimable;

    // --- Current swap usage ---
    struct xsw_usage swap;
    size = sizeof(swap);
    sysctlbyname("vm.swapusage", &swap, &size, nullptr, 0);

    uint64_t swapUsed = swap.xsu_used;

    // --- Outputs ---
    usedGB  = usedMem  / 1024.0 / 1024.0 / 1024.0;
    totalGB = totalMem / 1024.0 / 1024.0 / 1024.0;
    swapUsedGB = swapUsed / 1024.0 / 1024.0 / 1024.0;

    // --- Pressure estimation ---
    double freeRatio =
        (double)(freeMem + inactiveMem) / totalMem;

    double compressedRatio =
        (double)compressedMem / totalMem;

    double swapRatio =
        (double)swapUsed / totalMem;

    pressure = 0.0;

    if (freeRatio < 0.15) {
        pressure += (0.15 - freeRatio) * 4.0;
    }

    pressure += compressedRatio;
    pressure += swapRatio * 2.0;

    if (pressure < 0.0) pressure = 0.0;
    if (pressure > 1.0) pressure = 1.0;
}

// ---------- NETWORK ----------
void getNetwork(double &down, double &up) {
    static uint64_t prevIn = 0, prevOut = 0;
    uint64_t in = 0, out = 0;
    static bool initialized = false;
    
    struct ifaddrs *ifap;
    getifaddrs(&ifap);

    for (auto p = ifap; p; p = p->ifa_next) {
        if (!p->ifa_data) continue;
        if (!(p->ifa_flags & IFF_UP)) continue;

        struct if_data *data = (struct if_data *)p->ifa_data;
        in += data->ifi_ibytes;
        out += data->ifi_obytes;
    }

    freeifaddrs(ifap);

    if (!initialized) {
        prevIn = in;
        prevOut = out;
        down = 0;
        up = 0;
        initialized = true;
        return;
    }


    down = (in - prevIn) / 1024.0 / 1024.0;
    up   = (out - prevOut) / 1024.0 / 1024.0;

    prevIn = in;
    prevOut = out;
}

// ---------- DISK ----------
void getDiskInfo(double &freeGB, double &totalGB) {
    struct statfs stats;
    statfs("/", &stats);
    uint64_t freeBytes = (uint64_t)stats.f_bsize * stats.f_bavail;
    uint64_t totalBytes = (uint64_t)stats.f_bsize * stats.f_blocks;

    freeGB = freeBytes / 1024.0 / 1024.0 / 1024.0;
    totalGB = totalBytes / 1024.0 / 1024.0 / 1024.0;
}

// ----------Helper function - CPU CORE COUNT ----------
int getCPUCoreCount() {
    static int cores = 0;
    if (cores == 0) {
        size_t size = sizeof(cores);
        sysctlbyname("hw.ncpu", &cores, &size, NULL, 0);
    }
    return cores;
}

// ---------- top cpu process ----------
static std::unordered_map<pid_t, uint64_t> lastCpuTimes;
static auto lastSampleTime = std::chrono::steady_clock::now();
std::vector<pid_t> getTopCPUProcesses(
    int maxCount,
    double &selfCPUPercent
) {
    selfCPUPercent = 0.0;

    pid_t pids[2048];
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    int count = bytes / sizeof(pid_t);

    auto now = std::chrono::steady_clock::now();
    double elapsedSeconds =
        std::chrono::duration<double>(now - lastSampleTime).count();
    lastSampleTime = now;

    if (elapsedSeconds <= 0.0)
        elapsedSeconds = 1.0;

    int cores = getCPUCoreCount();
    pid_t selfPID = getpid();

    std::vector<std::pair<double, pid_t>> cpuList;

    for (int i = 0; i < count; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        struct proc_taskinfo pti;
        if (proc_pidinfo(pid,
                         PROC_PIDTASKINFO,
                         0,
                         &pti,
                         sizeof(pti)) != sizeof(pti))
            continue;

        uint64_t currentCpu =
            pti.pti_total_user + pti.pti_total_system;

        uint64_t lastCpu = lastCpuTimes[pid];
        uint64_t deltaCpu =
            (currentCpu > lastCpu) ? (currentCpu - lastCpu) : 0;

        lastCpuTimes[pid] = currentCpu;
        if (deltaCpu == 0) continue;

        double normalizedCPU =
            (double)deltaCpu /
            (elapsedSeconds * NSEC_PER_SEC * cores) * 100.0;

        if (pid == selfPID)
            selfCPUPercent = normalizedCPU;

        cpuList.emplace_back(normalizedCPU, pid);
    }

    std::sort(cpuList.begin(), cpuList.end(),
              [](auto &a, auto &b) {
                  return a.first > b.first;
              });

    std::vector<pid_t> topPids;
    for (int i = 0;
         i < std::min(maxCount, (int)cpuList.size());
         i++) {
        topPids.push_back(cpuList[i].second);
    }

    return topPids;
}

// ---------- top memory process ----------
struct MemProcess {
    pid_t pid;
    uint64_t bytes;
};
std::vector<MemProcess> getTopMemoryProcesses(int maxCount = 5)
{
    pid_t pids[2048];
    int bytesRead = proc_listpids(PROC_ALL_PIDS, 0, pids, sizeof(pids));
    int count = bytesRead / sizeof(pid_t);

    std::vector<MemProcess> list;
    list.reserve(count);

    for (int i = 0; i < count; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        struct proc_taskinfo pti;
        if (proc_pidinfo(pid,
                         PROC_PIDTASKINFO,
                         0,
                         &pti,
                         sizeof(pti)) != sizeof(pti)) {
            continue;
        }

        uint64_t mem = pti.pti_resident_size;
        if (mem == 0) continue;

        list.push_back({ pid, mem });
    }

    std::sort(list.begin(), list.end(),
              [](const MemProcess &a, const MemProcess &b) {
                  return a.bytes > b.bytes;
              });

    if ((int)list.size() > maxCount)
        list.resize(maxCount);

    return list;
}

// ---------- top memory process ----------
uint64_t getSelfMemoryBytes()
{
    struct proc_taskinfo pti;
    if (proc_pidinfo(
            getpid(),
            PROC_PIDTASKINFO,
            0,
            &pti,
            sizeof(pti)
        ) != sizeof(pti)) {
        return 0;
    }

    // Resident memory (what Activity Monitor shows)
    return pti.pti_resident_size;
}


// ---------- uptime ----------
double getUptimeSeconds()
{
    struct timeval boottime;
    size_t size = sizeof(boottime);

    sysctlbyname("kern.boottime", &boottime, &size, nullptr, 0);

    time_t now = time(nullptr);
    return difftime(now, boottime.tv_sec);
}

// ---------- MAIN ----------
int main() {
    cout.setf(ios::fixed);
    cout.precision(2);

    while (true) {
        double cpu = getCPUUsage();
        double memUsed, memTotal, memPressure, swapUsedGB;
        getMemoryPressure(memUsed, memTotal, memPressure, swapUsedGB);
        double down, up;
        getNetwork(down, up);
        double diskFree, diskTotal;
        getDiskInfo(diskFree, diskTotal);
        double selfCPUPercent = 0.0;
        std::vector<pid_t> topCPU = getTopCPUProcesses(5, selfCPUPercent);
        auto topMem = getTopMemoryProcesses(5);
        double uptimeSeconds = getUptimeSeconds();
        uint64_t selfMemBytes = getSelfMemoryBytes();

        cout << "{"
             << "\"cpu\":" << cpu << ","
             << "\"mem_used\":" << memUsed << ","
             << "\"mem_total\":" << memTotal << ","
             << "\"mem_pressure\":" << memPressure << ","
             << "\"swap_used\":" << swapUsedGB << ","
             << "\"net_down\":" << down << ","
             << "\"net_up\":" << up << ","
             << "\"disk_free\":" << diskFree << ","
             << "\"disk_total\":" << diskTotal << ","
             << "\"uptime_seconds\":" << uptimeSeconds << ","
            << "\"self_cpu\":" << selfCPUPercent << ","
            << "\"self_mem\":" << selfMemBytes << ",";

        cout << "\"top_mem\":[";
        for (size_t i = 0; i < topMem.size(); i++) {
            cout << "{"
                << "\"pid\":" << topMem[i].pid << ","
                << "\"bytes\":" << topMem[i].bytes
                << "}";
            if (i + 1 < topMem.size()) cout << ",";
        }
        cout << "],";

        cout << "\"top_cpu_pids\":[";
        for (size_t i = 0; i < topCPU.size(); i++) {
            cout << topCPU[i];
            if (i + 1 < topCPU.size()) cout << ",";
        }
        cout << "]";

        // close JSON
        cout << "}" << endl;

        cout.flush();
        sleep(1);
    }
}

//* ---------- TESTING ----------
// int main() {
//     cout.setf(ios::fixed);
//     cout.precision(1);

//     while (true) {
//         double cpu = getCPUUsage();

//         double ramUsed = 0.0, ramTotal = 0.0;
//         getMemory(ramUsed, ramTotal);

//         double down = 0.0, up = 0.0;
//         getNetwork(down, up);

//         double diskFree = getDiskFree();

//         cout << "\rCPU " << cpu << "% | "
//              << "RAM " << ramUsed << "/" << ramTotal << " GB | "
//              << "↓ " << down << " MB/s ↑ " << up << " MB/s | "
//              << "Disk Free " << diskFree << " GB   "
//              << flush;

//         sleep(1);
//     }

//     return 0;
// }
