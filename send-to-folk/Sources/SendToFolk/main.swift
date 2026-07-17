// SendToFolk — a macOS Services-menu app that captures anything selectable
// in the OS (text, images, files of any type) and writes it out as
// timestamped .folk files on ~/Desktop.
//
// Layout on disk (per the spec):
//   ~/Desktop/DDMMYY/HHMMSSmmmAM.folk          <- the lead .folk file
//   ~/Desktop/DDMMYY/HHMMSSmmmAM/UUID.png      <- assets referenced by it
//
// Lines written into the .folk file:
//   images      -> Wish $this displays image ~/Desktop/$DATE/$TIME/UUID.png
//   text        -> Wish $this is labelled "$TEXT"
//   other files -> Claim $this has unknown data $PATHTOFILE

import Cocoa
import UniformTypeIdentifiers

// MARK: - Folk file writing

struct Capture {
    let dateStamp: String   // DDMMYY
    let timeStamp: String   // HHMMSSmmm + AM/PM, e.g. 013045123PM
    let folkFile: URL       // ~/Desktop/DDMMYY/HHMMSSmmmPM.folk
    let assetsDir: URL      // ~/Desktop/DDMMYY/HHMMSSmmmPM/
    var lines: [String] = []

    // Paths written into the .folk file use ~ so the file stays portable
    // across machines/users, matching the spec.
    var tildeAssetsDir: String { "~/Desktop/\(dateStamp)/\(timeStamp)" }
}

enum FolkWriter {
    static var desktop: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }

    static func newCapture(now: Date = Date()) throws -> Capture {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "ddMMyy"
        let dateStamp = fmt.string(from: now)
        fmt.dateFormat = "hhmmssSSSa"
        let timeStamp = fmt.string(from: now)

        let dateDir = desktop.appendingPathComponent(dateStamp, isDirectory: true)
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        return Capture(
            dateStamp: dateStamp,
            timeStamp: timeStamp,
            folkFile: dateDir.appendingPathComponent("\(timeStamp).folk"),
            assetsDir: dateDir.appendingPathComponent(timeStamp, isDirectory: true)
        )
    }

    /// Ensure the per-capture assets folder exists (only created when needed).
    static func ensureAssetsDir(_ capture: Capture) throws {
        try FileManager.default.createDirectory(at: capture.assetsDir, withIntermediateDirectories: true)
    }

    static func finish(_ capture: Capture) throws {
        guard !capture.lines.isEmpty else { return }
        let body = capture.lines.joined(separator: "\n") + "\n"
        try body.write(to: capture.folkFile, atomically: true, encoding: .utf8)
    }

    /// Quote a string for use inside Tcl double quotes (Folk is Tcl-based).
    static func tclQuoted(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "$":  out += "\\$"
            case "[":  out += "\\["
            case "]":  out += "\\]"
            default:   out.append(ch)
            }
        }
        return "\"\(out)\""
    }

    static func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" { return true }
        if let type = UTType(filenameExtension: ext) {
            return type.conforms(to: .image)
        }
        return false
    }
}

// MARK: - Pasteboard handling

enum CaptureError: Error, CustomStringConvertible {
    case nothingUsable
    var description: String { "SendToFolk: nothing usable on the pasteboard" }
}

func capturePasteboard(_ pboard: NSPasteboard) throws {
    var capture = try FolkWriter.newCapture()

    let fileURLs = (pboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]
    ) as? [URL]) ?? []

    if !fileURLs.isEmpty {
        for url in fileURLs {
            try captureFile(url, into: &capture)
        }
    } else if let pngData = pboard.data(forType: .png) {
        try captureImageData(pngData, ext: "png", into: &capture)
    } else if let tiffData = pboard.data(forType: .tiff),
              let png = NSBitmapImageRep(data: tiffData)?
                  .representation(using: .png, properties: [:]) {
        try captureImageData(png, ext: "png", into: &capture)
    } else if let text = pboard.string(forType: .string), !text.isEmpty {
        capture.lines.append("Wish $this is labelled \(FolkWriter.tclQuoted(text))")
    } else {
        throw CaptureError.nothingUsable
    }

    try FolkWriter.finish(capture)
}

/// A file of any type or extension, without filters.
func captureFile(_ url: URL, into capture: inout Capture) throws {
    let fm = FileManager.default
    try FolkWriter.ensureAssetsDir(capture)

    if FolkWriter.isImageFile(url) {
        // Images are copied as UUID.<ext> and displayed by the .folk file.
        let ext = url.pathExtension.lowercased()
        let name = "\(UUID().uuidString).\(ext)"
        try fm.copyItem(at: url, to: capture.assetsDir.appendingPathComponent(name))
        capture.lines.append("Wish $this displays image \(capture.tildeAssetsDir)/\(name)")
    } else {
        // Any other filetype: save a copy and claim it as unknown data.
        var name = url.lastPathComponent
        if fm.fileExists(atPath: capture.assetsDir.appendingPathComponent(name).path) {
            name = "\(UUID().uuidString)-\(name)"
        }
        try fm.copyItem(at: url, to: capture.assetsDir.appendingPathComponent(name))
        capture.lines.append("Claim $this has unknown data \(capture.tildeAssetsDir)/\(name)")
    }
}

/// Raw image bytes from the pasteboard (e.g. Copy Image in a browser).
func captureImageData(_ data: Data, ext: String, into capture: inout Capture) throws {
    try FolkWriter.ensureAssetsDir(capture)
    let name = "\(UUID().uuidString).\(ext)"
    try data.write(to: capture.assetsDir.appendingPathComponent(name))
    capture.lines.append("Wish $this displays image \(capture.tildeAssetsDir)/\(name)")
}

// MARK: - App / Services provider

final class ServiceProvider: NSObject {
    @objc func sendToFolk(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        do {
            try capturePasteboard(pboard)
            NSSound(named: "Pop")?.play()
        } catch let err {
            error.pointee = "\(err)" as NSString
            NSSound.beep()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let serviceProvider = ServiceProvider()
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "paperplane.circle",
            accessibilityDescription: "Send To Folk"
        )

        let menu = NSMenu()
        menu.addItem(withTitle: "Send To Folk is running", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Open Today's Folder",
            action: #selector(openTodaysFolder),
            keyEquivalent: "o"
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Send To Folk",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }

    @objc func openTodaysFolder() {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "ddMMyy"
        let dir = FolkWriter.desktop.appendingPathComponent(fmt.string(from: Date()))
        let target = FileManager.default.fileExists(atPath: dir.path) ? dir : FolkWriter.desktop
        NSWorkspace.shared.open(target)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
