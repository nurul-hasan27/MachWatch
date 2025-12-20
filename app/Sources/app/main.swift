import AppKit

@MainActor
func startApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()

    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}

startApp()
