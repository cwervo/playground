import Foundation

/// What the keyboard extension observed inside the host app's text field.
/// This is the only window a third-party iOS app gets onto "what's on screen"
/// in another app, so it is deliberately small and explicit.
public struct StampContext: Codable, Equatable {
    public enum Source: String, Codable {
        case keyboard   // captured by the custom keyboard
        case app        // PiPStamp itself was in the foreground
        case manual     // user tapped a host label chip
    }

    public var source: Source
    public var capturedAt: Date
    /// Only populated when the keyboard is built with PIPSTAMP_PRIVATE_HOST_ID.
    public var hostBundleID: String?
    /// Label the user picked from the keyboard's chip row.
    public var hostLabel: String?
    /// UITextDocumentProxy.documentIdentifier, shortened.
    public var documentID: String?
    public var keyboardType: String?
    public var returnKeyType: String?
    public var textBefore: String?
    public var textAfter: String?
    public var selectedText: String?

    public init(source: Source,
                capturedAt: Date = Date(),
                hostBundleID: String? = nil,
                hostLabel: String? = nil,
                documentID: String? = nil,
                keyboardType: String? = nil,
                returnKeyType: String? = nil,
                textBefore: String? = nil,
                textAfter: String? = nil,
                selectedText: String? = nil) {
        self.source = source
        self.capturedAt = capturedAt
        self.hostBundleID = hostBundleID
        self.hostLabel = hostLabel
        self.documentID = documentID
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.textBefore = textBefore
        self.textAfter = textAfter
        self.selectedText = selectedText
    }

    /// Best available name for the app the user was in.
    public var appName: String? { hostBundleID ?? hostLabel }

    public func age(at now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(capturedAt))
    }
}

/// One fully resolved stamp: everything that ends up inside the QR code.
public struct Stamp: Equatable {
    public var seq: Int
    public var date: Date
    /// Resolved app name, e.g. "com.apple.MobileSMS", "Messages" or "PiPStamp".
    public var app: String
    /// Provenance shown next to the app, e.g. "keyboard, 4s ago".
    public var appNote: String?
    public var context: StampContext?
    public var deviceName: String?
    public var refreshSeconds: Int

    public init(seq: Int, date: Date, app: String, appNote: String? = nil,
                context: StampContext? = nil, deviceName: String? = nil,
                refreshSeconds: Int) {
        self.seq = seq
        self.date = date
        self.app = app
        self.appNote = appNote
        self.context = context
        self.deviceName = deviceName
        self.refreshSeconds = refreshSeconds
    }
}

/// Renders a `Stamp` as a small Markdown document. The format is a level-1
/// heading followed by one `- key: value` bullet per line, so any scanner can
/// parse it with a single regular expression and it stays readable as text.
public enum StampFormatter {
    public static let heading = "PiPStamp"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ssxxx"
        return f
    }()

    public static func markdown(for stamp: Stamp, settings: StampSettings) -> String {
        var lines: [String] = []
        lines.append("# \(heading) #\(stamp.seq)")
        lines.append("- date: \(dateFormatter.string(from: stamp.date))")
        lines.append("- time: \(timeFormatter.string(from: stamp.date))")

        if settings.includeApp {
            if let note = stamp.appNote, !note.isEmpty {
                lines.append("- app: \(stamp.app) (\(note))")
            } else {
                lines.append("- app: \(stamp.app)")
            }
        }

        if let context = stamp.context {
            if settings.includeFieldInfo {
                var parts: [String] = []
                if let k = context.keyboardType { parts.append("keyboard=\(k)") }
                if let r = context.returnKeyType { parts.append("return=\(r)") }
                if let d = context.documentID { parts.append("doc=\(d)") }
                if !parts.isEmpty { lines.append("- field: \(parts.joined(separator: " "))") }
            }
            if settings.includeScreenText, settings.maxScreenTextChars > 0 {
                let text = screenText(from: context, limit: settings.maxScreenTextChars)
                if !text.isEmpty { lines.append("- text: \"\(escape(text))\"") }
            }
        }

        if settings.includeDevice, let device = stamp.deviceName, !device.isEmpty {
            lines.append("- device: \(device)")
        }
        lines.append("- refresh: \(stamp.refreshSeconds)s")
        return lines.joined(separator: "\n")
    }

    /// Text around the cursor, `|` marking the insertion point and `[...]`
    /// wrapping a selection, trimmed to `limit` characters total.
    static func screenText(from context: StampContext, limit: Int) -> String {
        let before = context.textBefore ?? ""
        let after = context.textAfter ?? ""
        let selected = context.selectedText.map { "[\($0)]" } ?? "|"
        let budget = max(0, limit - selected.count)
        let beforeBudget = min(before.count, max(budget / 2, budget - after.count))
        let afterBudget = min(after.count, budget - beforeBudget)
        var head = String(before.suffix(beforeBudget))
        if head.count < before.count { head = "…" + head }
        var tail = String(after.prefix(afterBudget))
        if tail.count < after.count { tail += "…" }
        return head + selected + tail
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Human readable age like "4s ago" or "2m ago".
    public static func ageDescription(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }
}
