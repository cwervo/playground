import Foundation
import simd

/// One Euro filter (Casiewicz/Roussel/Vogel). Chosen over a Kalman filter
/// because the trade-off we actually face is jitter-at-rest versus lag-in-motion,
/// and this exposes exactly that as one knob: the cutoff rises with speed, so a
/// resting fingertip is heavily smoothed and a flicking one is barely touched.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var derivativeCutoff: Double

    private var previous: SIMD2<Double>?
    private var derivative = SIMD2<Double>(0, 0)
    private var lastTime: Double?

    init(minCutoff: Double, beta: Double, derivativeCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    mutating func reset() {
        previous = nil
        derivative = .zero
        lastTime = nil
    }

    mutating func filter(_ value: SIMD2<Double>, timestamp: Double) -> SIMD2<Double> {
        guard let prev = previous, let last = lastTime, timestamp > last else {
            previous = value
            lastTime = timestamp
            return value
        }
        let dt = timestamp - last
        lastTime = timestamp

        let rawDerivative = (value - prev) / dt
        derivative = mix(derivative, rawDerivative, alpha(cutoff: derivativeCutoff, dt: dt))

        let speed = length(derivative)
        let cutoff = minCutoff + beta * speed
        let filtered = mix(prev, value, alpha(cutoff: cutoff, dt: dt))
        previous = filtered
        return filtered
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private func mix(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ t: Double) -> SIMD2<Double> {
        a + (b - a) * t
    }
}
