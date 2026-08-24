import AppKit

/// CoreGraphics window coordinates are top-left origin and grow downwards;
/// AppKit screen coordinates are bottom-left origin and grow upwards.
/// Everything below converts between the two using the primary display,
/// which is the screen whose AppKit frame origin is (0, 0).
enum Coords {
    static var primaryHeight: CGFloat {
        // NSScreen.screens[0] is the screen with the menu bar, i.e. the origin of
        // the AppKit coordinate space.
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func nsRect(fromCG r: CGRect) -> CGRect {
        CGRect(x: r.origin.x,
               y: primaryHeight - r.origin.y - r.height,
               width: r.width,
               height: r.height)
    }

    static func cgPoint(fromNS p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    /// A rect covering every attached display, in AppKit coordinates.
    static var screensUnion: CGRect {
        var union = CGRect.null
        for screen in NSScreen.screens { union = union.union(screen.frame) }
        return union.isNull ? (NSScreen.main?.frame ?? .zero) : union
    }
}
