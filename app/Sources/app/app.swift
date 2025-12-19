import AppKit
import Foundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var process: Process?
    var pipe: Pipe?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Starting..."

        startSysmon()
        readStream()
    }

    func startSysmon() {
        process = Process()
        process?.executableURL = URL(
            fileURLWithPath: "/Users/nurulhasan/Developer/machwatch/engine/bin/system_monitor"
        )

        pipe = Pipe()
        process?.standardOutput = pipe

        try? process?.run()
    }

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


    func handleJSON(_ json: String) {
        guard
            let data = json.data(using: .utf8),
            let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double]
        else { return }

        let cpu  = dict["cpu"]  ?? 0
        let down = dict["net_down"] ?? 0
        let up   = dict["net_up"]   ?? 0
        let ramUsed  = dict["ram_used"]  ?? 0
        let ramTotal = dict["ram_total"] ?? 0
        let ramUsed_pct = (ramTotal > 0) ? (ramUsed / ramTotal) * 100 : 0
        let disk     = dict["disk_free"]  ?? 0

        statusItem.button?.title =
            String(format: "CPU %.0f%% | ↓ %.1f ↑ %.1f | RAM %.0f%% | DISK-FREE %.0fGB", cpu, down, up, ramUsed_pct, disk)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()