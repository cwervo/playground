import Foundation
import CoreGraphics
import simd

/// Everything the overlay needs to draw one frame. Produced on the vision queue,
/// consumed on the render thread, so it is a value type behind a lock rather
/// than a set of shared references.
struct HUDState {
    var enabled = false
    var phase: TouchPhase = .away
    var contact: GlassContact?
    var screenPoint: CGPoint?
    var maskSize = SIMD2<Int>(1280, 720)
    var screenQuadInCamera: [SIMD2<Double>] = []

    var fps: Double = 0
    var frameMilliseconds: Double = 0

    var calibrationTarget: CGPoint?
    var calibrationProgress: (done: Int, total: Int)?
    var banner: String?
}

/// Small lock-guarded box. The vision queue writes at 60 Hz, the display link
/// reads at 60 Hz, and they are not the same clock.
final class HUDStateBox {
    private var storage = HUDState()
    private let lock = NSLock()

    func update(_ mutate: (inout HUDState) -> Void) {
        lock.lock()
        mutate(&storage)
        lock.unlock()
    }

    var value: HUDState {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
