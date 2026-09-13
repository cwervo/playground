import Foundation

/// User-tunable behaviour. Stored as JSON in the App Group so the keyboard
/// extension reads the same values the app wrote.
public struct StampSettings: Codable, Equatable {
    /// The app never refreshes faster than this. Sixty seconds is the floor
    /// the product spec asks for; it also keeps the PiP frame rate trivial.
    public static let minimumRefreshSeconds = 60
    public static let maximumRefreshSeconds = 3600
    public static let refreshPresets = [60, 120, 300, 600, 900, 1800, 3600]

    public enum ErrorCorrection: String, Codable, CaseIterable {
        case low = "L", medium = "M", quartile = "Q", high = "H"
    }

    public var refreshSeconds: Int = 60
    public var includeApp = true
    public var includeScreenText = true
    public var includeFieldInfo = true
    public var includeDevice = true
    /// Characters of host text kept around the cursor. Bigger payloads mean
    /// denser QR codes, which scan worse from a small PiP window.
    public var maxScreenTextChars = 80
    public var errorCorrection: ErrorCorrection = .medium
    /// Keyboard: write a new context every time the host text changes.
    public var autoCaptureWhileTyping = true
    /// Keyboard: show the QR panel above the keys.
    public var showQRInKeyboard = true
    /// App: start PiP automatically when the app leaves the foreground.
    public var startPiPAutomatically = true
    /// App: loop a silent audio file while PiP is active so iOS keeps the
    /// process (and therefore the refresh timer) alive.
    public var keepAliveWithSilentAudio = true
    /// Labels shown as chips in the keyboard so the user can tag the current
    /// app by hand. iOS gives keyboards no public way to learn the host app.
    public var hostLabels: [String] = ["Messages", "Mail", "Safari", "Notes", "Slack"]

    public init() {}

    /// Returns a copy with every value pulled back inside its legal range.
    public func clamped() -> StampSettings {
        var copy = self
        copy.refreshSeconds = min(max(refreshSeconds, Self.minimumRefreshSeconds), Self.maximumRefreshSeconds)
        copy.maxScreenTextChars = min(max(maxScreenTextChars, 0), 400)
        copy.hostLabels = hostLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return copy
    }
}
