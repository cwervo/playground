import Foundation
import simd

/// Every tunable in one place. Values are in mask-space pixels unless noted.
struct Config: Codable {
    // Capture
    var captureWidth = 1280
    var captureHeight = 720
    var targetFPS = 60

    // Segmentation
    var morphRadius: UInt32 = 2          // open then close, separable, this radius
    var minRunLength: UInt32 = 3         // vertical runs shorter than this are noise
    var skinThreshold: Float = 0.28      // exp(-0.5 * mahalanobis) cut
    var lumaMin: Float = 0.10
    var lumaMax: Float = 0.98

    // Pairing a finger with its reflection
    var maxPairGap = 90                  // px between finger bottom and reflection top
    var minFingerRun = 6                 // px, the real finger's vertical extent
    var minReflectionRatio: Float = 0.25 // reflection must be >= this fraction of the finger
    var maxColumnJump = 5                // px of contact-y drift allowed between columns
    var minClusterWidth = 4              // columns

    // Touch decision, on gap normalised by apparent finger width.
    // Under a pinhole model of this geometry the ratio is ~0.142 per mm of hover
    // and varies only 3-4% across the display, so these are physical distances:
    // press below ~1.3 mm, release above ~3.0 mm.
    var touchDownRatio: Float = 0.18
    var touchUpRatio: Float = 0.42
    var downFrames = 2                   // consecutive frames below the down ratio
    var upFrames = 3
    var dropoutFrames = 4                // frames a tracked finger may vanish before release

    // Pointer
    var moveCursorWhileHovering = true
    var clickDeadBandPoints: Double = 2.5
    var clickDeadBandSeconds: Double = 0.12
    var doubleClickSeconds: Double = 0.4
    var doubleClickPoints: Double = 14

    // Smoothing (One Euro)
    var filterMinCutoff: Double = 1.2
    var filterBeta: Double = 0.05
    var filterDerivativeCutoff: Double = 1.0

    // Calibration grid
    var calibrationColumns = 5
    var calibrationRows = 4
    var calibrationDwellSeconds: Double = 0.35

    static let shared = Config()
}

/// A point on the glass, in mask-space pixels, plus the evidence behind it.
struct GlassContact {
    var point: SIMD2<Float>       // midpoint of finger tip and reflection top
    var gap: Float                // px between them; 0 when the runs have merged
    var widthPx: Float            // apparent finger width, the perspective scale proxy
    var columns: ClosedRange<Int>
    var confidence: Float

    /// Perspective-invariant hover height. A 5 mm hover is ~30 px near the bezel
    /// and ~6 px at the far edge of the display, but the finger's apparent width
    /// shrinks by the same factor, so the ratio is flat across the screen.
    var normalizedGap: Float { gap / max(widthPx, 6) }
}
