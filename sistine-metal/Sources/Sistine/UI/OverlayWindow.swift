import AppKit
import MetalKit
import CoreGraphics

/// A click-through, full-screen, transparent Metal window.
///
/// `ignoresMouseEvents` is not a nicety: this app synthesises the very events
/// that would otherwise land on this window, and a window that could receive
/// them would swallow every touch before it reached the app underneath.
final class OverlayWindow: NSWindow {
    let metalView: MTKView

    init(display: CGDirectDisplayID, device: MTLDevice) {
        let bounds = CGDisplayBounds(display)
        // CGDisplayBounds is top-left origin; NSWindow wants bottom-left, and
        // the flip is about the *union* of all screens, not this one.
        let globalHeight = NSScreen.screens.map { $0.frame.maxY }.max() ?? bounds.maxY
        let frame = NSRect(x: bounds.minX,
                           y: globalHeight - bounds.maxY,
                           width: bounds.width,
                           height: bounds.height)

        metalView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false
        metalView.preferredFramesPerSecond = 60
        metalView.layer?.isOpaque = false
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        super.init(contentRect: frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        contentView = metalView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Above the menu bar and full-screen apps, and present on every Space so
        // the cursor annotation does not vanish when the user switches desktop.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
