import AppKit
import Foundation

// HISTORY HELPER
func pushHistory<T>(_ array: inout [T], value: T, maxSize: Int) {
    array.append(value)
    if array.count > maxSize {
        array.removeFirst()
    }
}
func formatBytes(_ bytes: Double) -> String {
    let gb = bytes / 1024 / 1024 / 1024
    if gb >= 1 {
        return String(format: "%.1f GB", gb)
    }

    let mb = bytes / 1024 / 1024
    return String(format: "%.0f MB", mb)
}
// APP INFO FROM PID
func appInfoFromPID(_ pid: Int) -> NSRunningApplication? {
    // First try direct match
    if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
        return app
    }

    // Fallback: find any GUI app using same executable path
    let runningApps = NSWorkspace.shared.runningApplications

    for app in runningApps {
        // guard let url = app.executableURL else { continue }
        guard app.executableURL != nil else { continue }

        let appPid = app.processIdentifier
        if appPid == pid {
            return app
        }
    }

    return nil
}


@MainActor
func firstGUIApp(from pidValues: [Double]) -> (name: String, icon: NSImage)? {

    let selfPID = getpid()

    for value in pidValues {
        let pid = Int(value)
        if pid <= 0 { continue }

        if pid == selfPID {
            return ("machwatch", NSApp.applicationIconImage)
        }

        guard
            let app = NSRunningApplication(processIdentifier: pid_t(pid)),
            app.activationPolicy == .regular
        else {
            continue
        }

        return (
            app.localizedName ?? "Unknown",
            app.icon ?? NSImage()
        )
    }
    return nil
}

@MainActor
func firstGUIAppWithMemory(
    from items: [[String: Any]]
) -> (name: String, icon: NSImage, bytes: Double)? {

    for item in items {
        guard
            let pidValue = item["pid"] as? Double,
            let bytes = item["bytes"] as? Double
        else { continue }

        let pid = Int(pidValue)

        if pid == getpid() {
            return (
                name: "machwatch",
                icon: NSApp.applicationIconImage,
                bytes: bytes
            )
        }

        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            return (
                name: app.localizedName ?? "Unknown",
                icon: app.icon ?? NSImage(),
                bytes: bytes
            )
        }
    }
    return nil
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Self App Info
    let selfPID = getpid()
    let selfBundleID = Bundle.main.bundleIdentifier

    // MARK: - Status Bar
    var statusItem: NSStatusItem!

    // MARK: - Menu Items
    var menu: NSMenu!
    var cpuRow: MenuStatRowView!
    var ramRow: MenuStatRowView!
    var netRow: MenuStatRowView!
    var diskRow: MenuStatRowView!
    var swapRow: MenuStatRowView!
    var ramPressureView: RamPressureView!
    var topAppRow: MenuStatRowView!
    var selfRow: MenuStatRowView!
    var topMemRow: MenuStatRowView!

    var cpuGraphView: CPUHistoryView!
    var networkGraphView: NetworkHistoryView!


    // MARK: - Process / Pipe
    var process: Process?
    var pipe: Pipe?

    // MARK: - HISTORY STORAGE
    let historySize = 60
    var cpuHistory: [Double] = []
    var ramHistory: [Double] = []

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Starting…"

        setupMenu()
        startSysmon()
        readStream()

        printBanner()

    }

    // MARK: - Menu Setup
    func setupMenu() {
        menu = NSMenu()

        cpuRow = MenuStatRowView(labelText: "CPU", valueText: "--")
        topAppRow = MenuStatRowView(labelText: "Top Proc", valueText: "--")
        ramRow = MenuStatRowView(labelText: "RAM", valueText: "--")
        topMemRow = MenuStatRowView(labelText: "Top Proc", valueText: "--")
        selfRow = MenuStatRowView(labelText: "machwatch", valueText: "--", isBold: true)
        netRow = MenuStatRowView(labelText: "Network", valueText: "--")
        diskRow = MenuStatRowView(labelText: "Disk", valueText: "--")
        swapRow = MenuStatRowView(labelText: "Swap", valueText: "--")
        let memoryGraphLabel = NSMenuItem(title: "Memory Pressure", action: nil, keyEquivalent: "")
        let cpuGraphLabel = NSMenuItem(title: "CPU History", action: nil, keyEquivalent: "")

        menu.addItem(makeItem(cpuRow))
        menu.addItem(makeItem(topAppRow))
        menu.addItem(makeItem(ramRow))
        menu.addItem(makeItem(topMemRow))

        menu.addItem(makeItem(selfRow))

        menu.addItem(makeItem(netRow))
        menu.addItem(makeItem(diskRow))
        menu.addItem(makeItem(swapRow))

        // menu.addItem(.separator())
        // ram pressure graph
        menu.addItem(memoryGraphLabel)
        ramPressureView = RamPressureView(
            frame: NSRect(x: 0, y: 0, width: 310, height: 80)
        )

        let ramGraphItem = NSMenuItem()
        ramGraphItem.view = ramPressureView
        menu.addItem(ramGraphItem)

        // menu.addItem(.separator())
        menu.addItem(cpuGraphLabel)
        //cpu graph
        cpuGraphView = CPUHistoryView(frame: NSRect(x: 0, y: 0, width: 310, height: 80))

        let graphItem = NSMenuItem()
        graphItem.view = cpuGraphView

        menu.addItem(graphItem)

        menu.addItem(.separator())

        //quit item
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func makeItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    // MARK: - Launch C++ Sysmon
    func startSysmon() {
        process = Process()
        process?.executableURL = URL(
            fileURLWithPath: "../engine/bin/system_monitor"
        )

        pipe = Pipe()
        process?.standardOutput = pipe

        try? process?.run()
    }

    // MARK: - Read JSON Stream
    func readStream() {
        pipe?.fileHandleForReading.readabilityHandler = { (handle: FileHandle) in
            let data = handle.availableData
            if data.isEmpty { return }

            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.handleJSON(text)
                }
            }
        }
    }

    // MARK: - Update Menu Live
    func handleJSON(_ json: String) {
        guard
            let data = json.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let cpu        = dict["cpu"] as? Double ?? 0
        let ramUsed    = dict["mem_used"] as? Double ?? 0
        let ramTotal   = dict["mem_total"] as? Double ?? 0
        let ramPressure = (dict["mem_pressure"] as? Double ?? 0) * 100
        let swapUsed   = dict["swap_used"] as? Double ?? 0
        let down       = dict["net_down"] as? Double ?? 0
        let up         = dict["net_up"] as? Double ?? 0

        let diskFree   = dict["disk_free"] as? Double ?? 0
        let diskTotal  = dict["disk_total"] as? Double ?? 0
        let selfCPU = dict["self_cpu"] as? Double ?? 0
        let selfMemBytes = dict["self_mem"] as? Double ?? 0
        let selfMemText = formatBytes(selfMemBytes)

        let topCpuPids = dict["top_cpu_pids"] as? [Double] ?? []
        if let info = firstGUIApp(from: topCpuPids) {
            topAppRow.update(
                valueText: "\(info.name)"
            )
            topAppRow.setIcon(info.icon)
        } else {
            topAppRow.update(valueText: "Background Process")
            topAppRow.setIcon(nil)
        }

        let topMem = dict["top_mem"] as? [[String: Any]] ?? []
        if let memInfo = firstGUIAppWithMemory(from: topMem) {
            let memText = formatBytes(memInfo.bytes)

            topMemRow.update(
                valueText: "\(memInfo.name) (\(memText))"
            )
            topMemRow.setIcon(memInfo.icon)
        } else {
            topMemRow.update(valueText: "Background Process")
            topMemRow.setIcon(nil)
        }

        let ramUsedPct = (ramTotal > 0) ? (ramUsed / ramTotal * 100) : 0
        let diskPct = (diskTotal > 0) ? (diskFree / diskTotal * 100) : 0


        let cpuCol = cpuColor(cpu)
        cpuRow.setValueColor(cpuCol)
        // cpuRow.setLabelColor(cpuCol)

        cpuRow.update(
            valueText: String(format: "%.0f %%", cpu)
        )

        let ramCol = ramPressureColor(ramPressure)
        ramRow.setValueColor(ramCol)
        // ramRow.setLabelColor(ramCol)

        ramRow.update(
            valueText: String(
                format: "%.1f / %.1f GB (%.0f%%)",
                ramUsed, ramTotal, ramUsedPct
            )
        )


        netRow.update(
            valueText: String(format: "↓ %.1f ↑ %.1f MB/s", down, up)
        )

        let diskCol = diskFreeColor(freePercent: diskPct)
        diskRow.setValueColor(diskCol)
        // diskRow.setLabelColor(diskCol)

        diskRow.update(
            valueText: String(format: "Disk Free: %.0f / %.0f GB (%.0f%%)", diskFree, diskTotal, diskPct)
        )

        swapRow.update(valueText: String(format: "%.1f GB", swapUsed))

        let selfCol = cpuColor(selfCPU)
        selfRow.setValueColor(selfCol)
        selfRow.setLabelColor(selfCol)
        selfRow.update(
            valueText: String(
                format: "%.2f%% CPU , %@ MEM",
                selfCPU,
                selfMemText
            )
        )

        // Update Histories
        pushHistory(&cpuHistory, value: cpu, maxSize: historySize)
        pushHistory(&ramHistory, value: ramPressure, maxSize: historySize)

        statusItem.button?.title =
            String(format: "MEM %.0f%% | CPU %.0f%% | ↓ %.1f ↑ %.1f", ramUsedPct, cpu, down, up)

        cpuGraphView.values = cpuHistory
        ramPressureView.values = ramHistory
        ramPressureView.needsDisplay = true
        cpuGraphView.needsDisplay = true
    }

    @objc func quitApp() {
        process?.terminate()
        NSApplication.shared.terminate(nil)
    }
}