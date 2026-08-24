import AppKit
import ApplicationServices

/// Slides the real window off screen while its paper double is on stage, so the
/// original does not peek out from under a stretched sheet. Needs the
/// Accessibility permission; without it we simply leave the window where it is.
final class AXWindowMover {
    private let element: AXUIElement
    private let originalPosition: CGPoint
    private var moved = false

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts for Accessibility access if this process has never asked.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Finds the accessibility element for a window by matching its screen rect.
    init?(pid: pid_t, bounds: CGRect) {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return nil }

        var match: (AXUIElement, CGPoint)?
        for window in windows {
            guard let position = AXWindowMover.point(of: window, attribute: kAXPositionAttribute),
                  let size = AXWindowMover.size(of: window, attribute: kAXSizeAttribute)
            else { continue }
            // AX positions are in the same top-left origin space as CGWindowList bounds.
            let matchesOrigin = abs(position.x - bounds.origin.x) < 4 && abs(position.y - bounds.origin.y) < 4
            let matchesSize = abs(size.width - bounds.width) < 6 && abs(size.height - bounds.height) < 6
            if matchesOrigin && matchesSize {
                match = (window, position)
                break
            }
        }
        guard let (window, position) = match else { return nil }
        self.element = window
        self.originalPosition = position
    }

    func hide() {
        guard !moved else { return }
        // Far enough down that no display can show it, close enough that apps
        // that clamp coordinates still move.
        moved = setPosition(CGPoint(x: originalPosition.x, y: 200_000))
    }

    func restore() {
        guard moved else { return }
        _ = setPosition(originalPosition)
        moved = false
    }

    // MARK: - AX plumbing

    private func setPosition(_ p: CGPoint) -> Bool {
        var point = p
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    private static func point(of element: AXUIElement, attribute: String) -> CGPoint? {
        guard let value = axValue(of: element, attribute: attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private static func size(of element: AXUIElement, attribute: String) -> CGSize? {
        guard let value = axValue(of: element, attribute: attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private static func axValue(of element: AXUIElement, attribute: String) -> AXValue? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)
    }
}
