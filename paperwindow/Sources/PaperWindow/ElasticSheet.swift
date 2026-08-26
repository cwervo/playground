import Foundation
import simd

/// A rectangular lattice of particles held together by distance constraints and
/// pulled back towards its rest shape — a sheet of paper that can be grabbed,
/// stretched and flicked, and that wobbles its way back to flat.
///
/// Solved with position based dynamics: integrate, then relax the constraints a
/// few times per step. Positions are in the overlay view's coordinate space
/// (points, y up).
final class ElasticSheet {

    struct Constraint {
        var a: Int32
        var b: Int32
        var rest: Float
        var stiffness: Float
    }

    let cols: Int
    let rows: Int
    let cellW: Float
    let cellH: Float

    private(set) var pos: [SIMD2<Float>]
    private var prev: [SIMD2<Float>]
    private(set) var rest: [SIMD2<Float>]
    private var constraints: [Constraint] = []

    /// How strongly every particle is dragged back to its rest position each
    /// relaxation pass. 0 leaves the sheet crumpled wherever you put it.
    var springBack: Float = 0.010
    /// Velocity retained per substep. Lower damps the jiggle out faster.
    var damping: Float = 0.988
    var gravity: Float = 0

    private var grabbed: Int?
    private var grabFrom: SIMD2<Float> = .zero
    private var grabTo: SIMD2<Float> = .zero

    private let iterations = 4
    private var seed: UInt64 = 0x9E3779B97F4A7C15

    private let stiffness: Float

    /// - Parameters:
    ///   - frame: rest rectangle of the sheet, in view points.
    ///   - spacing: desired distance between lattice vertices, in points.
    ///   - stiffness: multiplier on every spring; 1 is paper, less is cloth.
    init(frame: CGRect, spacing: CGFloat, stiffness: Float = 1) {
        // Position based dynamics needs relaxation factors in (0, 1].
        self.stiffness = max(0.02, min(1, stiffness))
        cols = max(4, min(48, Int((frame.width / spacing).rounded()) + 1))
        rows = max(4, min(48, Int((frame.height / spacing).rounded()) + 1))
        cellW = Float(frame.width) / Float(cols - 1)
        cellH = Float(frame.height) / Float(rows - 1)

        var points: [SIMD2<Float>] = []
        points.reserveCapacity(cols * rows)
        let top = Float(frame.maxY)
        let left = Float(frame.minX)
        for j in 0..<rows {
            for i in 0..<cols {
                // Row 0 is the top of the window, and y grows upwards in view space.
                points.append(SIMD2(left + Float(i) * cellW, top - Float(j) * cellH))
            }
        }
        pos = points
        prev = points
        rest = points

        buildConstraints()
    }

    private func buildConstraints() {
        func index(_ i: Int, _ j: Int) -> Int32 { Int32(j * cols + i) }
        func link(_ a: Int32, _ b: Int32, _ weight: Float) {
            let d = simd_length(pos[Int(a)] - pos[Int(b)])
            constraints.append(Constraint(a: a, b: b, rest: d, stiffness: weight * stiffness))
        }
        for j in 0..<rows {
            for i in 0..<cols {
                let me = index(i, j)
                // structural: the weave of the paper
                if i + 1 < cols { link(me, index(i + 1, j), 1.0) }
                if j + 1 < rows { link(me, index(i, j + 1), 1.0) }
                // shear: resists the lattice collapsing into a diamond
                if i + 1 < cols && j + 1 < rows {
                    link(me, index(i + 1, j + 1), 0.55)
                    link(index(i + 1, j), index(i, j + 1), 0.55)
                }
                // bend: keeps long runs from folding back on themselves
                if i + 2 < cols { link(me, index(i + 2, j), 0.22) }
                if j + 2 < rows { link(me, index(i, j + 2), 0.22) }
            }
        }
    }

    // MARK: - Handles

    var cornerIndices: [Int] {
        [0, cols - 1, (rows - 1) * cols, rows * cols - 1]
    }

    /// The corner nearest `point`, if it is within `radius` points.
    func corner(near point: CGPoint, radius: CGFloat) -> Int? {
        let p = SIMD2<Float>(Float(point.x), Float(point.y))
        var best: (Int, Float)?
        for index in cornerIndices {
            let d = simd_length(pos[index] - p)
            if d <= Float(radius), best == nil || d < best!.1 { best = (index, d) }
        }
        return best?.0
    }

    /// The lattice vertex nearest `point`, if the sheet is within `radius`.
    func nearest(to point: CGPoint, within radius: CGFloat) -> Int? {
        let index = nearest(to: point)
        let p = SIMD2<Float>(Float(point.x), Float(point.y))
        return simd_length(pos[index] - p) <= Float(radius) ? index : nil
    }

    /// The lattice vertex nearest `point`, whatever the distance.
    func nearest(to point: CGPoint) -> Int {
        let p = SIMD2<Float>(Float(point.x), Float(point.y))
        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for index in pos.indices {
            let d = simd_length_squared(pos[index] - p)
            if d < bestDistance { bestDistance = d; bestIndex = index }
        }
        return bestIndex
    }

    var isGrabbing: Bool { grabbed != nil }

    func beginGrab(index: Int, at point: CGPoint) {
        grabbed = index
        let p = SIMD2<Float>(Float(point.x), Float(point.y))
        grabFrom = p
        grabTo = p
        pos[index] = p
        prev[index] = p
    }

    func moveGrab(to point: CGPoint) {
        grabTo = SIMD2<Float>(Float(point.x), Float(point.y))
    }

    /// Let go. Whatever speed the hand had is already stored as the particle's
    /// velocity, so the sheet keeps going and then springs back.
    func endGrab() {
        grabbed = nil
    }

    // MARK: - Impulses

    /// A random flap, as if you shook the sheet.
    func flap(strength: Float = 16) {
        let angle = Float(random01()) * 2 * .pi
        let dir = SIMD2<Float>(cos(angle), sin(angle))
        for i in pos.indices {
            // A long wavelength across the sheet: tighter ripples just fight
            // the distance constraints and die within a frame.
            let u = Float(i % cols) / Float(cols - 1) - 0.5
            let v = Float(i / cols) / Float(rows - 1) - 0.5
            let wave = sin((u * 1.5 + v * 1.1) * .pi + angle)
            prev[i] -= dir * strength * wave * (0.4 + Float(random01()) * 0.6)
        }
    }

    /// Snap flat again, killing all motion.
    func reset() {
        pos = rest
        prev = rest
        grabbed = nil
    }

    private func random01() -> Double {
        // xorshift; we only need wiggle, not statistics.
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return Double(seed % 100_000) / 100_000.0
    }

    // MARK: - Simulation

    /// Advance one fixed substep. `progress` walks the grabbed point from where
    /// it was at the start of the frame to where the cursor is now, so fast
    /// drags transfer real momentum instead of teleporting.
    func step(progress: Float) {
        let g = SIMD2<Float>(0, -gravity)
        for i in pos.indices {
            let velocity = (pos[i] - prev[i]) * damping
            prev[i] = pos[i]
            pos[i] += velocity + g
        }

        let handPosition = grabFrom + (grabTo - grabFrom) * progress
        if let index = grabbed {
            pos[index] = handPosition
        }

        for _ in 0..<iterations {
            solveDistances()
            solveSpringBack()
            // The hand wins: re-pin after every relaxation pass.
            if let index = grabbed {
                pos[index] = handPosition
            }
        }
    }

    /// Called once per frame after all substeps have consumed the drag.
    func commitGrabTarget() {
        grabFrom = grabTo
    }

    private func solveDistances() {
        for c in constraints {
            let a = Int(c.a), b = Int(c.b)
            let delta = pos[b] - pos[a]
            let length = simd_length(delta)
            guard length > 1e-5 else { continue }
            let correction = delta * ((length - c.rest) / length) * 0.5 * c.stiffness
            pos[a] += correction
            pos[b] -= correction
        }
    }

    private func solveSpringBack() {
        guard springBack > 0 else { return }
        for i in pos.indices {
            pos[i] += (rest[i] - pos[i]) * springBack
        }
    }
}
