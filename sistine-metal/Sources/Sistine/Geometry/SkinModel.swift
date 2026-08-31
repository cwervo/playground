import Foundation
import CoreVideo
import simd

/// A 2D Gaussian over CbCr, fitted to the user's own hand under the user's own
/// lighting during calibration.
///
/// The reason this beats a fixed HSV box: the mirror is not colour-neutral, the
/// display backlight tints everything above the glass, and "skin" spans a range
/// that a box either clips (missing dark skin tones) or over-covers (swallowing
/// wood desks and warm wallpaper). One Mahalanobis ellipse per user, fitted in
/// five seconds, sidesteps the whole argument.
struct SkinModel: Codable {
    var meanCb: Float
    var meanCr: Float
    var invCovA: Float   // [[a, b], [b, c]]
    var invCovB: Float
    var invCovC: Float

    /// Broad prior used before calibration: centred on the usual CbCr skin locus
    /// (Cb ~108, Cr ~153 of 255) with enough spread to find any hand at all.
    static let prior = SkinModel(meanCb: 0.424, meanCr: 0.600,
                                 invCovA: 900, invCovB: 250, invCovC: 900)

    func params(config: Config, flipX: Bool, flipY: Bool) -> SkinParams {
        SkinParams(mean: SIMD2(meanCb, meanCr),
                   invCov: SIMD3(invCovA, invCovB, invCovC),
                   threshold: config.skinThreshold,
                   lumaMin: config.lumaMin,
                   lumaMax: config.lumaMax,
                   flipX: flipX ? 1 : 0,
                   flipY: flipY ? 1 : 0)
    }

    /// Fit from raw CbCr samples, with a variance floor so a perfectly uniform
    /// patch cannot produce a degenerate, infinitely narrow ellipse.
    static func fit(samples: [SIMD2<Float>], sigmaScale: Float = 2.5) -> SkinModel? {
        guard samples.count >= 64 else { return nil }
        let n = Float(samples.count)
        let mean = samples.reduce(SIMD2<Float>(0, 0), +) / n

        var vxx: Float = 0, vxy: Float = 0, vyy: Float = 0
        for s in samples {
            let d = s - mean
            vxx += d.x * d.x
            vxy += d.x * d.y
            vyy += d.y * d.y
        }
        let floor: Float = 1e-5
        vxx = max(vxx / n, floor) * sigmaScale
        vyy = max(vyy / n, floor) * sigmaScale
        vxy = (vxy / n) * sigmaScale

        let det = vxx * vyy - vxy * vxy
        guard abs(det) > 1e-12 else { return nil }
        return SkinModel(meanCb: mean.x, meanCr: mean.y,
                         invCovA: vyy / det, invCovB: -vxy / det, invCovC: vxx / det)
    }
}

/// Reads CbCr values out of the interleaved half-resolution chroma plane.
///
/// This is the one place the CPU touches pixel data, and it only happens during
/// calibration, for a few hundred pixels per frame. Everything on the hot path
/// stays on the GPU.
enum ChromaSampler {
    static func sample(pixelBuffer: CVPixelBuffer,
                       aroundMaskPoint p: SIMD2<Float>,
                       maskSize: SIMD2<Int>,
                       radius: Int = 6,
                       flipX: Bool,
                       flipY: Bool) -> [SIMD2<Float>]
    {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else { return [] }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else { return [] }
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let cw = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let ch = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let bytes = base.assumingMemoryBound(to: UInt8.self)

        // Undo the canonical-orientation flip the shader applied, so we index
        // the raw plane the camera actually delivered.
        var mx = Int(p.x.rounded())
        var my = Int(p.y.rounded())
        if flipX { mx = maskSize.x - 1 - mx }
        if flipY { my = maskSize.y - 1 - my }

        let sx = Double(cw) / Double(maskSize.x)
        let sy = Double(ch) / Double(maskSize.y)
        let cx = Int(Double(mx) * sx)
        let cy = Int(Double(my) * sy)

        var out: [SIMD2<Float>] = []
        for dy in -radius...radius {
            let y = cy + dy
            guard y >= 0, y < ch else { continue }
            for dx in -radius...radius {
                let x = cx + dx
                guard x >= 0, x < cw else { continue }
                let o = y * bytesPerRow + x * 2
                out.append(SIMD2(Float(bytes[o]) / 255.0, Float(bytes[o + 1]) / 255.0))
            }
        }
        return out
    }
}
