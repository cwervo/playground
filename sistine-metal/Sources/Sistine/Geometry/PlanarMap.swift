import Foundation
import simd

/// Camera glass-space -> screen points, and back.
///
/// A homography alone leaves a few points of error near the frame edges, where
/// the wide-angle FaceTime lens' barrel distortion is worst and where the
/// grazing angle amplifies it. Rather than fit a full Brown-Conrady distortion
/// model (which needs far more than 20 samples to be well conditioned), we keep
/// the homography as the global model and interpolate the leftover per-target
/// residuals with inverse-distance weighting. It is a lookup table for the part
/// of the error we cannot name, and it converges with exactly the data the
/// calibration pass already collects.
struct PlanarMap: Codable {
    var homography: [Double]
    var controlCameraPoints: [SIMD2<Double>]
    var residuals: [SIMD2<Double>]     // screen-space correction at each control point
    var screenQuadInCamera: [SIMD2<Double>]
    var flipX: Bool
    var flipY: Bool

    var h: Homography { Homography(m: homography) }

    static func build(cameraPoints: [SIMD2<Double>],
                      screenPoints: [SIMD2<Double>],
                      screenSize: SIMD2<Double>,
                      flipX: Bool,
                      flipY: Bool) -> PlanarMap?
    {
        guard let (homography, inliers) =
                HomographySolver.fitRANSAC(source: cameraPoints, destination: screenPoints)
        else { return nil }

        let camIn = inliers.map { cameraPoints[$0] }
        let residuals = inliers.map { screenPoints[$0] - homography.apply(cameraPoints[$0]) }

        // Project the screen's own corners back into camera space; this quad
        // becomes the segmentation ROI.
        var quad: [SIMD2<Double>] = []
        if let inv = homography.inverted() {
            quad = [SIMD2(0, 0),
                    SIMD2(screenSize.x, 0),
                    SIMD2(screenSize.x, screenSize.y),
                    SIMD2(0, screenSize.y)].map { inv.apply($0) }
        }

        return PlanarMap(homography: homography.m,
                         controlCameraPoints: camIn,
                         residuals: residuals,
                         screenQuadInCamera: quad,
                         flipX: flipX,
                         flipY: flipY)
    }

    func screenPoint(forCamera p: SIMD2<Double>) -> SIMD2<Double> {
        var out = h.apply(p)
        out += interpolatedResidual(at: p)
        return out
    }

    /// Shepard interpolation over the four nearest control points. Four is
    /// enough to stay smooth without letting a distant corner's residual leak
    /// into the middle of the screen.
    private func interpolatedResidual(at p: SIMD2<Double>) -> SIMD2<Double> {
        guard !controlCameraPoints.isEmpty else { return .zero }

        var neighbours: [(distanceSquared: Double, index: Int)] = []
        for (i, c) in controlCameraPoints.enumerated() {
            let d = distance_squared(c, p)
            if d < 1e-6 { return residuals[i] }   // sitting on a control point
            neighbours.append((d, i))
        }
        neighbours.sort { $0.distanceSquared < $1.distanceSquared }

        var sum = SIMD2<Double>(0, 0)
        var weight = 0.0
        for (d2, i) in neighbours.prefix(4) {
            let w = 1.0 / d2
            sum += residuals[i] * w
            weight += w
        }
        return weight > 0 ? sum / weight : .zero
    }

    var residualStatistics: (mean: Double, max: Double) {
        guard !residuals.isEmpty else { return (0, 0) }
        let lengths = residuals.map { simd_length($0) }
        return (lengths.reduce(0, +) / Double(lengths.count), lengths.max() ?? 0)
    }
}
