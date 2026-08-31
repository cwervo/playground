import AppKit

/// Menu-bar-only agent: there is no main window, because the app's entire UI is
/// a click-through overlay drawn on top of whatever the user is actually doing.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await controller.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
