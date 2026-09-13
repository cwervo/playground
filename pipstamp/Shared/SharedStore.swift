import Foundation

/// Identifiers shared by the app and the keyboard. Change the group ID to one
/// registered under your own team; it must match both entitlements files.
public enum AppGroup {
    public static let identifier = "group.com.cwervo.pipstamp"
}

/// Tiny key/value store on top of the App Group `UserDefaults`.
/// The keyboard can only reach it when "Allow Full Access" is on, so every
/// read falls back to defaults and every write is best effort.
public final class SharedStore {
    public static let shared = SharedStore()

    private enum Key {
        static let settings = "settings.v1"
        static let context = "context.v1"
        static let seq = "seq.v1"
        static let lastMarkdown = "lastMarkdown.v1"
        static let lastRefresh = "lastRefresh.v1"
    }

    private let defaults: UserDefaults?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(suiteName: String = AppGroup.identifier) {
        defaults = UserDefaults(suiteName: suiteName)
    }

    /// False when the App Group container is unreachable, which in the
    /// keyboard means Full Access is off.
    public var isAvailable: Bool { defaults != nil }

    public var settings: StampSettings {
        get { load(Key.settings) ?? StampSettings() }
        set { save(newValue.clamped(), for: Key.settings) }
    }

    public var context: StampContext? {
        get { load(Key.context) }
        set { save(newValue, for: Key.context) }
    }

    public var seq: Int {
        get { defaults?.integer(forKey: Key.seq) ?? 0 }
        set { defaults?.set(newValue, forKey: Key.seq) }
    }

    public var lastMarkdown: String? {
        get { defaults?.string(forKey: Key.lastMarkdown) }
        set { defaults?.set(newValue, forKey: Key.lastMarkdown) }
    }

    public var lastRefresh: Date? {
        get { defaults?.object(forKey: Key.lastRefresh) as? Date }
        set { defaults?.set(newValue, forKey: Key.lastRefresh) }
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T?, for key: String) {
        guard let value else {
            defaults?.removeObject(forKey: key)
            return
        }
        if let data = try? encoder.encode(value) {
            defaults?.set(data, forKey: key)
        }
    }
}
