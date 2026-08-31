import Foundation
import CoreGraphics
import simd

/// Synthesises pointer events with CoreGraphics.
///
/// `CGEvent.post(tap: .cghidEventTap)` injects at the HID layer, above the
/// driver but below every application, so the events are indistinguishable from
/// a real mouse to AppKit, Catalyst apps, Electron, and games alike. This is
/// what PyAutoGUI is a wrapper around; calling it directly removes a process
/// hop and lets us set click state, subtype and modifier flags properly —
/// which is the difference between a synthetic double-click that works and one
/// that mysteriously does not.
final class PointerInjector {
    private let source = CGEventSource(stateID: .hidSystemState)
    private let config: Config

    private var isDown = false
    private var downPoint = CGPoint.zero
    private var downTime: CFTimeInterval = 0
    private var lastClickTime: CFTimeInterval = 0
    private var lastClickPoint = CGPoint.zero
    private var clickCount: Int64 = 1

    init(config: Config) {
        self.config = config
        // A synthetic event stream and the real trackpad fight over the cursor
        // otherwise: local events would be coalesced with ours and the pointer
        // would visibly stutter between the two sources.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
    }

    func move(to point: CGPoint) {
        guard !isDown else { return drag(to: point) }
        post(.mouseMoved, at: point, clickCount: 0)
    }

    func down(at point: CGPoint) {
        guard !isDown else { return }
        let now = CACurrentMediaTimeShim()
        let quickEnough = now - lastClickTime < config.doubleClickSeconds
        let closeEnough = hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y)
            < config.doubleClickPoints
        clickCount = (quickEnough && closeEnough) ? min(clickCount + 1, 3) : 1

        isDown = true
        downPoint = point
        downTime = now
        post(.leftMouseDown, at: point, clickCount: clickCount)
    }

    func drag(to point: CGPoint) {
        guard isDown else { return }
        // Dead band: a fingertip settles for ~100 ms after contact, and letting
        // that settle become a drag turns every click on a scrollbar or a
        // desktop icon into an accidental move.
        let elapsed = CACurrentMediaTimeShim() - downTime
        let travel = hypot(point.x - downPoint.x, point.y - downPoint.y)
        if elapsed < config.clickDeadBandSeconds && travel < config.clickDeadBandPoints { return }
        post(.leftMouseDragged, at: point, clickCount: clickCount)
    }

    func up(at point: CGPoint) {
        guard isDown else { return }
        isDown = false
        lastClickTime = CACurrentMediaTimeShim()
        lastClickPoint = point
        post(.leftMouseUp, at: point, clickCount: clickCount)
    }

    /// Called when tracking is lost mid-drag. Releasing at the last known point
    /// is always better than leaving the system with a stuck mouse button.
    func releaseIfNeeded() {
        if isDown { up(at: downPoint) }
    }

    private func post(_ type: CGEventType, at point: CGPoint, clickCount: Int64) {
        guard let event = CGEvent(mouseEventSource: source,
                                  mouseType: type,
                                  mouseCursorPosition: point,
                                  mouseButton: .left) else { return }
        if clickCount > 0 {
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        }
        event.post(tap: .cghidEventTap)
    }
}

/// CACurrentMediaTime lives in QuartzCore; wrapped so this file does not need
/// the import and stays a pure CoreGraphics translation unit.
private func CACurrentMediaTimeShim() -> CFTimeInterval {
    var t = timespec()
    clock_gettime(CLOCK_MONOTONIC_RAW, &t)
    return CFTimeInterval(t.tv_sec) + CFTimeInterval(t.tv_nsec) / 1e9
}

/// Screen geometry lives in CoreGraphics too, and its coordinate space — origin
/// at the top-left of the main display, y increasing downward, measured in
/// points — is the one CGEvent expects. NSScreen's bottom-left origin is the
/// usual source of "my cursor is mirrored vertically" bugs here.
enum DisplayGeometry {
    static var main: (id: CGDirectDisplayID, bounds: CGRect) {
        let id = CGMainDisplayID()
        return (id, CGDisplayBounds(id))
    }

    static func bounds(for id: CGDirectDisplayID) -> CGRect { CGDisplayBounds(id) }

    static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }
}
