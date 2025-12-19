import AppKit
import Foundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Status Bar
    var statusItem: NSStatusItem!

    // MARK: - Menu Items (STEP 1)
    var menu: NSMenu!
    var cpuItem: NSMenuItem!
    var ramItem: NSMenuItem!
    var netItem: NSMenuItem!
    var diskItem: NSMenuItem!

    // MARK: - Process / Pipe
    var process: Process?
    var pipe: Pipe?

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Starting…"

        setupMenu()      // STEP 3
        startSysmon()
        readStream()
    }

    // MARK: - Menu Setup (STEP 2)
    func setupMenu() {
        menu = NSMenu()

        cpuItem = NSMenuItem(title: "CPU: --", action: nil, keyEquivalent: "")
        ramItem = NSMenuItem(title: "RAM: --", action: nil, keyEquivalent: "")
        netItem = NSMenuItem(title: "Network: --", action: nil, keyEquivalent: "")
        diskItem = NSMenuItem(title: "Disk: --", action: nil, keyEquivalent: "")

        menu.addItem(cpuItem)
        menu.addItem(ramItem)
        menu.addItem(netItem)
        menu.addItem(diskItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
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

    // MARK: - Update Menu Live (STEP 4)
    func handleJSON(_ json: String) {
        guard
            let data = json.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
        else { return }

        let cpu      = dict["cpu"]      ?? 0
        let down     = dict["net_down"]     ?? 0
        let up       = dict["net_up"]       ?? 0
        let ramUsed  = dict["ram_used"]  ?? 0
        let ramTotal = dict["ram_total"] ?? 0
        let disk     = dict["disk_free"]     ?? 0
        let ramUsedPct = (ramTotal > 0) ? (ramUsed / ramTotal * 100) : 0

        cpuItem.title =
            String(format: "CPU Usage: %.1f%%", cpu)

        ramItem.title =
            String(format: "RAM: %.1f / %.1f GB (%.0f%%)",
                   ramUsed, ramTotal, ramUsedPct)

        netItem.title =
            String(format: "Network ↓ %.1f MB/s ↑ %.1f MB/s", down, up)

        diskItem.title =
            String(format: "Disk Free: %.0f GB", disk)

        // Short menu bar title
        statusItem.button?.title =
            String(format: "CPU %.0f%% | ↓ %.1f ↑ %.1f", cpu, down, up)
    }

    // MARK: - Quit (STEP 5)
    @objc func quitApp() {
        process?.terminate()
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - App Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()