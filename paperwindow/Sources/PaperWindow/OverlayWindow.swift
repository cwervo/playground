import AppKit

/// A borderless, transparent, click-through-nothing window that floats above
/// everything, spanning every attached display.
final class OverlayWindow: NSWindow {

    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        isMovable = false
        ignoresMouseEvents = false
        setFrame(frame, display: false)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
