#include <iostream>
#include <unistd.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/mount.h>

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
void getMemory(double &usedGB, double &totalGB) {
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    vm_statistics_data_t vmstat;
    host_statistics(mach_host_self(), HOST_VM_INFO,
                    (host_info_t)&vmstat, &count);

    uint64_t pageSize;
    size_t size = sizeof(pageSize);
    sysctlbyname("hw.pagesize", &pageSize, &size, NULL, 0);

    uint64_t used =
        (vmstat.active_count + vmstat.inactive_count + vmstat.wire_count) * pageSize;
    uint64_t total;
    sysctlbyname("hw.memsize", &total, &size, NULL, 0);

    usedGB = used / 1024.0 / 1024.0 / 1024.0;
    totalGB = total / 1024.0 / 1024.0 / 1024.0;
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
double getDiskFree() {
    struct statfs stats;
    statfs("/", &stats);
    uint64_t freeBytes = (uint64_t)stats.f_bsize * stats.f_bavail;
    return freeBytes / 1024.0 / 1024.0 / 1024.0;
}

// ---------- MAIN ----------
int main() {
    cout.setf(ios::fixed);
    cout.precision(2);

    while (true) {
        double cpu = getCPUUsage();
        double ramUsed, ramTotal;
        getMemory(ramUsed, ramTotal);
        double down, up;
        getNetwork(down, up);
        double disk = getDiskFree();

        cout << "{"
             << "\"cpu\":" << cpu << ","
             << "\"ram_used\":" << ramUsed << ","
             << "\"ram_total\":" << ramTotal << ","
             << "\"net_down\":" << down << ","
             << "\"net_up\":" << up << ","
             << "\"disk_free\":" << disk
             << "}" << endl;

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
