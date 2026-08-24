import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())

let options: Options
do {
    options = try Options.parse(arguments)
} catch {
    FileHandle.standardError.write(Data("paperwindow: \(error)\n\n\(Options.usage)\n".utf8))
    exit(2)
}

if options.listOnly {
    func column(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    if !CGPreflightScreenCaptureAccess() {
        print("(no Screen Recording permission yet, so window titles are hidden)")
    }
    let windows = WindowList.onScreen()
    if windows.isEmpty {
        print("No capturable windows found.")
    }
    for window in windows {
        let b = window.bounds
        let size = "\(Int(b.width))x\(Int(b.height))"
        print("\(column(String(window.id), 8))  \(column(size, 11))  \(window.label)")
    }
    exit(0)
}

guard Capture.ensurePermission() else {
    FileHandle.standardError.write(Data("""
    paperwindow: Screen Recording permission is required to photograph a window.
    Grant it in System Settings › Privacy & Security › Screen Recording, then run this again.

    """.utf8))
    exit(1)
}

let app = NSApplication.shared
// Accessory: no Dock icon, but we can still take key focus for esc.
app.setActivationPolicy(.accessory)
let controller = AppController(options: options)
app.delegate = controller
app.run()
