import AppKit

/// One capturable on-screen window, as reported by CGWindowListCopyWindowInfo.
struct WindowInfo {
    var id: CGWindowID
    var pid: pid_t
    var owner: String
    var title: String
    var bounds: CGRect        // CoreGraphics (top-left origin) global coordinates
    var layer: Int

    var label: String {
        title.isEmpty ? owner : "\(owner) — \(title)"
    }
}

enum WindowList {
    /// On-screen windows, front to back, with our own and the desktop furniture removed.
    static func onScreen() -> [WindowInfo] {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap { entry -> WindowInfo? in
            guard
                let id = entry[kCGWindowNumber as String] as? CGWindowID,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

            guard pid != ourPID else { return nil }          // never paper ourselves
            guard layer == 0 else { return nil }             // normal windows only
            guard bounds.width >= 80, bounds.height >= 60 else { return nil }

            let owner = entry[kCGWindowOwnerName as String] as? String ?? "?"
            let title = entry[kCGWindowName as String] as? String ?? ""
            guard owner != "Window Server", owner != "Dock" else { return nil }

            return WindowInfo(id: id, pid: pid, owner: owner, title: title, bounds: bounds, layer: layer)
        }
    }

    /// Frontmost window belonging to an application, matched case-insensitively.
    static func firstWindow(ofApp name: String) -> WindowInfo? {
        let needle = name.lowercased()
        return onScreen().first { $0.owner.lowercased().contains(needle) }
    }

    static func window(withID id: CGWindowID) -> WindowInfo? {
        onScreen().first { $0.id == id }
    }

    /// Topmost window under a point given in AppKit screen coordinates.
    static func window(underNSPoint p: CGPoint) -> WindowInfo? {
        let cg = Coords.cgPoint(fromNS: p)
        // onScreen() is ordered front to back, so the first hit is the topmost.
        return onScreen().first { $0.bounds.contains(cg) }
    }
}
