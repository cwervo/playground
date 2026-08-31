import Foundation
import simd

/// A 3x3 projective map, stored row-major.
///
/// The glass is a plane and the camera is a pinhole, so a homography is the
/// *exact* model for camera-plane -> screen-plane, not an approximation. What it
/// does not model is lens distortion, which is why `PlanarMap` layers a residual
/// field on top.
struct Homography {
    var m: [Double]   // 9 entries, row-major

    static let identity = Homography(m: [1, 0, 0, 0, 1, 0, 0, 0, 1])

    func apply(_ p: SIMD2<Double>) -> SIMD2<Double> {
        let x = m[0] * p.x + m[1] * p.y + m[2]
        let y = m[3] * p.x + m[4] * p.y + m[5]
        let w = m[6] * p.x + m[7] * p.y + m[8]
        guard abs(w) > 1e-12 else { return SIMD2(0, 0) }
        return SIMD2(x / w, y / w)
    }

    func inverted() -> Homography? {
        let a = m
        let c0 = a[4] * a[8] - a[5] * a[7]
        let c1 = a[5] * a[6] - a[3] * a[8]
        let c2 = a[3] * a[7] - a[4] * a[6]
        let det = a[0] * c0 + a[1] * c1 + a[2] * c2
        guard abs(det) > 1e-12 else { return nil }
        let inv = [
            c0, a[2] * a[7] - a[1] * a[8], a[1] * a[5] - a[2] * a[4],
            c1, a[0] * a[8] - a[2] * a[6], a[2] * a[3] - a[0] * a[5],
            c2, a[1] * a[6] - a[0] * a[7], a[0] * a[4] - a[1] * a[3],
        ].map { $0 / det }
        return Homography(m: inv)
    }
}

enum HomographySolver {

    /// Normalised DLT. Hartley normalisation (centroid to origin, mean distance
    /// to sqrt(2)) is not optional here: raw pixel coordinates in the hundreds
    /// give the design matrix a condition number in the millions, and the
    /// smallest singular vector comes out as noise.
    static func fit(source: [SIMD2<Double>], destination: [SIMD2<Double>]) -> Homography? {
        guard source.count >= 4, source.count == destination.count else { return nil }

        guard let (ns, ts) = normalize(source),
              let (nd, td) = normalize(destination) else { return nil }

        var a = [Double](repeating: 0, count: 9 * 9)   // A = M^T M, built in place
        for i in 0..<ns.count {
            let (x, y) = (ns[i].x, ns[i].y)
            let (u, v) = (nd[i].x, nd[i].y)
            let r1: [Double] = [-x, -y, -1, 0, 0, 0, u * x, u * y, u]
            let r2: [Double] = [0, 0, 0, -x, -y, -1, v * x, v * y, v]
            for p in 0..<9 {
                for q in 0..<9 {
                    a[p * 9 + q] += r1[p] * r1[q] + r2[p] * r2[q]
                }
            }
        }

        guard let h = smallestEigenvector(symmetric: a, n: 9) else { return nil }

        // Undo the normalisation: H = Td^-1 * Hn * Ts
        let hn = Homography(m: h)
        guard let tdInv = td.inverted() else { return nil }
        return Homography(m: multiply(multiply(tdInv.m, hn.m), ts.m))
    }

    /// RANSAC over the calibration correspondences. With a 20-point grid a
    /// single mis-tap (the user's finger drifting off a target, or a frame where
    /// a knuckle won the cluster vote) would otherwise skew the whole map.
    static func fitRANSAC(source: [SIMD2<Double>],
                          destination: [SIMD2<Double>],
                          threshold: Double = 6.0,
                          iterations: Int = 800) -> (homography: Homography, inliers: [Int])?
    {
        guard source.count >= 4 else { return nil }
        if source.count == 4 {
            return HomographySolver.fit(source: source, destination: destination)
                .map { ($0, Array(0..<4)) }
        }

        var rng = SystemRandomNumberGenerator()
        var best: (Homography, [Int])?

        for _ in 0..<iterations {
            var idx = Set<Int>()
            while idx.count < 4 { idx.insert(Int.random(in: 0..<source.count, using: &rng)) }
            let pick = Array(idx)
            let s = pick.map { source[$0] }
            let d = pick.map { destination[$0] }
            guard !isDegenerate(s), !isDegenerate(d),
                  let candidate = fit(source: s, destination: d) else { continue }

            var inliers: [Int] = []
            for i in 0..<source.count {
                let e = distance(candidate.apply(source[i]), destination[i])
                if e <= threshold { inliers.append(i) }
            }
            if inliers.count > (best?.1.count ?? 0) { best = (candidate, inliers) }
        }

        guard let (_, inliers) = best, inliers.count >= 4 else { return nil }
        // Refit on the full inlier set — the minimal-sample model is only ever a
        // hypothesis generator.
        guard let refined = fit(source: inliers.map { source[$0] },
                                destination: inliers.map { destination[$0] }) else { return nil }
        return (refined, inliers)
    }

    // MARK: - Linear algebra

    /// Cyclic Jacobi eigen-decomposition of a small symmetric matrix, returning
    /// the eigenvector of the smallest eigenvalue.
    ///
    /// Deliberately hand-rolled rather than routed through LAPACK: the matrix is
    /// 9x9 and always symmetric positive semi-definite, Jacobi converges in a
    /// handful of sweeps, and it keeps the app free of Accelerate's
    /// LAPACK integer-width churn across SDK versions.
    static func smallestEigenvector(symmetric a0: [Double], n: Int) -> [Double]? {
        guard a0.count == n * n else { return nil }
        var a = a0
        var v = [Double](repeating: 0, count: n * n)
        for i in 0..<n { v[i * n + i] = 1 }

        for _ in 0..<64 {
            var off = 0.0
            for p in 0..<n { for q in (p + 1)..<n { off += a[p * n + q] * a[p * n + q] } }
            if off < 1e-24 { break }

            for p in 0..<n {
                for q in (p + 1)..<n {
                    let apq = a[p * n + q]
                    if abs(apq) < 1e-18 { continue }
                    let theta = (a[q * n + q] - a[p * n + p]) / (2 * apq)
                    let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
                    let c = 1 / (t * t + 1).squareRoot()
                    let s = t * c

                    for k in 0..<n {
                        let akp = a[k * n + p], akq = a[k * n + q]
                        a[k * n + p] = c * akp - s * akq
                        a[k * n + q] = s * akp + c * akq
                    }
                    for k in 0..<n {
                        let apk = a[p * n + k], aqk = a[q * n + k]
                        a[p * n + k] = c * apk - s * aqk
                        a[q * n + k] = s * apk + c * aqk
                    }
                    for k in 0..<n {
                        let vkp = v[k * n + p], vkq = v[k * n + q]
                        v[k * n + p] = c * vkp - s * vkq
                        v[k * n + q] = s * vkp + c * vkq
                    }
                }
            }
        }

        var smallest = 0
        for i in 1..<n where a[i * n + i] < a[smallest * n + smallest] { smallest = i }
        return (0..<n).map { v[$0 * n + smallest] }
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                var s = 0.0
                for k in 0..<3 { s += a[i * 3 + k] * b[k * 3 + j] }
                r[i * 3 + j] = s
            }
        }
        return r
    }

    private static func normalize(_ pts: [SIMD2<Double>]) -> ([SIMD2<Double>], Homography)? {
        let n = Double(pts.count)
        let centroid = pts.reduce(SIMD2<Double>(0, 0), +) / n
        let meanDist = pts.reduce(0.0) { $0 + distance($1, centroid) } / n
        guard meanDist > 1e-9 else { return nil }
        let scale = 2.0.squareRoot() / meanDist
        let t = Homography(m: [scale, 0, -scale * centroid.x,
                               0, scale, -scale * centroid.y,
                               0, 0, 1])
        return (pts.map { t.apply($0) }, t)
    }

    /// Reject minimal samples with three near-collinear points; they produce a
    /// rank-deficient system and a wild model that RANSAC then has to outvote.
    private static func isDegenerate(_ p: [SIMD2<Double>]) -> Bool {
        for i in 0..<p.count {
            for j in (i + 1)..<p.count {
                for k in (j + 1)..<p.count {
                    let a = p[j] - p[i], b = p[k] - p[i]
                    if abs(a.x * b.y - a.y * b.x) < 1e-3 { return true }
                }
            }
        }
        return false
    }
}
