import Foundation

/// Cross-process pings between the keyboard extension and the app.
/// Darwin notifications carry no payload; the receiver re-reads `SharedStore`.
public enum DarwinNotification: String {
    case contextChanged = "com.cwervo.pipstamp.contextChanged"
    case settingsChanged = "com.cwervo.pipstamp.settingsChanged"
    case stampRefreshed = "com.cwervo.pipstamp.stampRefreshed"
}

public enum DarwinNotifier {
    /// Keep the returned token alive for as long as you want callbacks.
    public final class Observation {
        fileprivate let name: CFString
        fileprivate let handler: () -> Void

        fileprivate init(name: CFString, handler: @escaping () -> Void) {
            self.name = name
            self.handler = handler
        }

        deinit {
            let center = CFNotificationCenterGetDarwinNotifyCenter()
            let observer = Unmanaged.passUnretained(self).toOpaque()
            CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(name), nil)
        }
    }

    public static func post(_ notification: DarwinNotification) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center,
                                             CFNotificationName(notification.rawValue as CFString),
                                             nil, nil, true)
    }

    public static func observe(_ notification: DarwinNotification,
                               handler: @escaping () -> Void) -> Observation {
        let token = Observation(name: notification.rawValue as CFString, handler: handler)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(token).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let token = Unmanaged<Observation>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { token.handler() }
        }, token.name, nil, .deliverImmediately)
        return token
    }
}
