import AppKit
import Foundation
//start at login module
import ServiceManagement

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

enum MenuBarMetric: String, CaseIterable {
    case cpu
    case mem
    case netDown
    case netUp
    case disk

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .mem: return "MEM"
        case .netDown: return "↓"
        case .netUp: return "↑"
        case .disk: return "Disk"
        }
    }
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

    // MARK: - User Defaults Keys
    let launchPromptShownKey = "launchPromptShown"
    let launchUserAllowedKey = "launchUserAllowed"


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

    var enabledMenuBarMetrics: Set<MenuBarMetric> = {
        if let raw = UserDefaults.standard.array(forKey: "menuBarMetrics") as? [String] {
            return Set(raw.compactMap { MenuBarMetric(rawValue: $0) })
        }
        return [.cpu, .mem] // default
    }()


    // MARK: - Process / Pipe
    var process: Process?
    var pipe: Pipe?

    // MARK: - HISTORY STORAGE
    let historySize = 60
    var cpuHistory: [Double] = []
    var ramHistory: [Double] = []

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        //! ONLY FOR TESTING
        // #if DEBUG
        // UserDefaults.standard.removeObject(forKey: launchPromptShownKey)
        // UserDefaults.standard.removeObject(forKey: launchUserAllowedKey)
        // #endif

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Starting…"

        setupMenu()
        startSysmon()
        readStream()

        promptLaunchAtLoginIfNeeded()

        printBanner()

    }

    // MARK: - Launch at Login
    func promptLaunchAtLoginIfNeeded() {
        // Already asked once
        guard !UserDefaults.standard.bool(forKey: launchPromptShownKey) else {
            return
        }

        UserDefaults.standard.set(true, forKey: launchPromptShownKey)

        // Only supported on macOS 13+
        guard #available(macOS 13.0, *) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Start MachWatch at login?"
        alert.informativeText = "You can change this later in System Settings → Login Items."

        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: launchUserAllowedKey)
                print("Launch at login enabled by user")
            } catch {
                print("Failed to enable launch at login:", error)
            }
        } else {
            UserDefaults.standard.set(false, forKey: launchUserAllowedKey)
        }
        setupMenu()
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
        let cpuGraphLabel = NSMenuItem(title: "CPU Load", action: nil, keyEquivalent: "")

        let editMenuItem = NSMenuItem(title: "Edit Menu Bar", action: nil, keyEquivalent: "")

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

        //launch at login item
        if UserDefaults.standard.bool(forKey: launchPromptShownKey),
        UserDefaults.standard.bool(forKey: launchUserAllowedKey) == false {

            let launchItem = NSMenuItem(
                title: "Enable Launch at Login",
                action: #selector(enableLaunchFromMenu),
                keyEquivalent: ""
            )
            launchItem.target = self
            menu.addItem(launchItem)
        }


        let editMenu = NSMenu()

        for metric in MenuBarMetric.allCases {
            let item = NSMenuItem(
                title: metric.title,
                action: #selector(toggleMenuBarMetric(_:)),
                keyEquivalent: ""
            )
            item.state = enabledMenuBarMetrics.contains(metric) ? .on : .off
            item.representedObject = metric
            item.target = self
            editMenu.addItem(item)
        }

        editMenuItem.submenu = editMenu
        menu.addItem(editMenuItem)
        

        menu.addItem(.separator())
        //about me item
        let aboutItem = NSMenuItem(
            title: "",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self

        aboutItem.attributedTitle = NSAttributedString(
            string: "About MachWatch",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        menu.addItem(aboutItem)


        //quit item
        // menu.addItem(.separator())
        // let quitItem = NSMenuItem(
        //     title: "Quit",
        //     action: #selector(quitApp),
        //     keyEquivalent: "q"
        // )
        // quitItem.target = self
        // menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func makeItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    func startSysmon() {
        let engineURL: URL

        // Production: inside .app bundle
        if let bundled = Bundle.main.url(
            forResource: "system_monitor",
            withExtension: nil
        ) {
            engineURL = bundled
        } else {
            // Development fallback
            engineURL = URL(fileURLWithPath: "engine/bin/system_monitor")
        }

        guard FileManager.default.isExecutableFile(atPath: engineURL.path) else {
            fatalError("system_monitor not executable at \(engineURL.path)")
        }

        process = Process()
        process?.executableURL = engineURL

        pipe = Pipe()
        process?.standardOutput = pipe

        do {
            try process?.run()
            print("system_monitor started:", engineURL.path)
        } catch {
            fatalError("Failed to start system_monitor: \(error)")
        }
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

    @objc func toggleMenuBarMetric(_ sender: NSMenuItem) {
        guard let metric = sender.representedObject as? MenuBarMetric else { return }

        if enabledMenuBarMetrics.contains(metric) {
            enabledMenuBarMetrics.remove(metric)
            sender.state = .off
        } else {
            enabledMenuBarMetrics.insert(metric)
            sender.state = .on
        }

        UserDefaults.standard.set(
            enabledMenuBarMetrics.map { $0.rawValue },
            forKey: "menuBarMetrics"
        )
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

        var titleParts: [String] = []

        if enabledMenuBarMetrics.contains(.cpu) {
            titleParts.append(String(format: "CPU %.0f%%", cpu))
        }

        if enabledMenuBarMetrics.contains(.mem) {
            titleParts.append(String(format: "MEM %.0f%%", ramUsedPct))
        }

        if enabledMenuBarMetrics.contains(.disk) {
            titleParts.append(String(format: "Disk %.0f%%", diskPct))
        }

        if enabledMenuBarMetrics.contains(.netDown) {
            titleParts.append(String(format: "↓ %.1f", down))
        }

        if enabledMenuBarMetrics.contains(.netUp) {
            titleParts.append(String(format: "↑ %.1f", up))
        }

        statusItem.button?.title = titleParts.joined(separator: " | ")



        cpuGraphView.values = cpuHistory
        ramPressureView.values = ramHistory
        ramPressureView.needsDisplay = true
        cpuGraphView.needsDisplay = true
    }

    @objc func enableLaunchFromMenu(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else { return }

        do {
            try SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: launchUserAllowedKey)
            menu.removeItem(sender)   // 👈 disappears forever
            print("Launch at login enabled from menu")
        } catch {
            print("Failed to enable launch at login:", error)
        }
    }
@objc func showAbout() {
    let text = "Lightweight Real-time macOS\nsystem monitor\n\nCreated by Nurul Hasan\n\nGitHub"

    let attributed = NSMutableAttributedString(string: text)

    // Center alignment
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    attributed.addAttributes(
        [
            .paragraphStyle: paragraph,
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ],
        range: NSRange(location: 0, length: attributed.length)
    )

    // Make "GitHub" a clickable link
    let linkRange = (text as NSString).range(of: "GitHub")
    attributed.addAttribute(
        .link,
        value: "https://github.com/nurul-hasan27",
        range: linkRange
    )

    NSApp.orderFrontStandardAboutPanel(
        options: [
            .applicationName: "MachWatch",
            .credits: attributed
        ]
    )
}


    @objc func quitApp() {
        process?.terminate()
        NSApplication.shared.terminate(nil)
    }
}