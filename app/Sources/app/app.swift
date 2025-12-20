import AppKit
import Foundation

// HISTORY HELPER
func pushHistory<T>(_ array: inout [T], value: T, maxSize: Int) {
    array.append(value)
    if array.count > maxSize {
        array.removeFirst()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Status Bar
    var statusItem: NSStatusItem!

    // MARK: - Menu Items
    var menu: NSMenu!
    var cpuRow: MenuStatRowView!
    var ramRow: MenuStatRowView!
    var netRow: MenuStatRowView!
    var diskRow: MenuStatRowView!
    var ramPressureView: RamPressureView!

    var cpuGraphView: CPUHistoryView!
    var networkGraphView: NetworkHistoryView!


    // MARK: - Process / Pipe
    var process: Process?
    var pipe: Pipe?

    // MARK: - HISTORY STORAGE
    let historySize = 60
    var cpuHistory: [Double] = []
    var downHistory: [Double] = []
    var upHistory: [Double] = []
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
        ramRow = MenuStatRowView(labelText: "RAM", valueText: "--")
        netRow = MenuStatRowView(labelText: "Network", valueText: "--")
        diskRow = MenuStatRowView(labelText: "Disk", valueText: "--")

        menu.addItem(makeItem(cpuRow))
        menu.addItem(makeItem(ramRow))
        menu.addItem(makeItem(netRow))
        menu.addItem(makeItem(diskRow))

        // ram pressure graph
        ramPressureView = RamPressureView(
            frame: NSRect(x: 0, y: 0, width: 220, height: 40)
        )

        let ramGraphItem = NSMenuItem()
        ramGraphItem.view = ramPressureView
        menu.addItem(ramGraphItem)

        //cpu graph
        cpuGraphView = CPUHistoryView(frame: NSRect(x: 0, y: 0, width: 220, height: 60))

        let graphItem = NSMenuItem()
        graphItem.view = cpuGraphView

        menu.addItem(graphItem)

        menu.addItem(.separator())

        //network graph
        networkGraphView = NetworkHistoryView(
            frame: NSRect(x: 0, y: 0, width: 220, height: 40)
        )

        let netGraphItem = NSMenuItem()
        netGraphItem.view = networkGraphView
        menu.addItem(netGraphItem)

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
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
        else { return }

        let cpu      = dict["cpu"] ?? 0
        let ramUsed  = dict["mem_used"] ?? 0
        let ramTotal = dict["mem_total"] ?? 0
        let ramPressure = dict["mem_pressure"] ?? 0
        // let swapUsed = dict["swap_used"] ?? 0
        let down     = dict["net_down"] ?? 0
        let up       = dict["net_up"] ?? 0
        let diskFree = dict["disk_free"] ?? 0
        let diskTotal = dict["disk_total"] ?? 0
        // let topCpuProcess = dict["top_cpu_pid"] ?? 0
        // let topMemProcess = dict["top_mem_pid"] ?? 0
        

        let ramUsedPct = (ramTotal > 0) ? (ramUsed / ramTotal * 100) : 0
        let diskPct = (diskTotal > 0) ? (diskFree / diskTotal * 100) : 0

        let ramColor: NSColor
        switch ramUsedPct {
        case 0..<50:
            ramColor = .systemGreen
        case 50..<80:
            ramColor = .systemYellow
        default:
            ramColor = .systemRed
        }

        ramRow.setValueColor(ramColor)

        cpuRow.update(valueText: String(format: "%.0f %%", cpu))

        ramRow.update(
            valueText: String(format: "%.1f / %.1f GB (%.0f%%)",
            ramUsed, ramTotal, ramPressure)
        )

        netRow.update(
            valueText: String(format: "↓ %.1f ↑ %.1f MB/s", down, up)
        )

        diskRow.update(
            valueText: String(format: "Disk Free: %.0f / %.0f GB (%.0f%%)", diskFree, diskTotal, diskPct)
        )

        pushHistory(&cpuHistory, value: cpu, maxSize: historySize)
        pushHistory(&downHistory, value: down, maxSize: historySize)
        pushHistory(&upHistory, value: up, maxSize: historySize)
        pushHistory(&ramHistory, value: ramPressure, maxSize: historySize)

        statusItem.button?.title =
            String(format: "MEM %.0f%% | CPU %.0f%% | ↓ %.1f ↑ %.1f", ramUsedPct, cpu, down, up)

        cpuGraphView.values = cpuHistory
        networkGraphView.downValues = downHistory
        networkGraphView.upValues = upHistory
        ramPressureView.values = ramHistory
        ramPressureView.needsDisplay = true
        networkGraphView.needsDisplay = true
        cpuGraphView.needsDisplay = true


    }

    @objc func quitApp() {
        process?.terminate()
        NSApplication.shared.terminate(nil)
    }
}