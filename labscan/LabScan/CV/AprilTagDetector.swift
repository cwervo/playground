import Foundation
import CoreGraphics
import Vision

/// tag36h11 detection in the LabScan idiom: Apple's classic rectangle
/// detector (no ML, on-device) proposes square-ish quads, then we sample the
/// tag's 8×8 cell grid through a square→quad homography and match the 36
/// data bits against the family codebook — tables and bit twiddling, like
/// the wand-scanner decoders next door.
enum AprilTagDetector {

    static func detect(cgImage: CGImage) -> [Detection] {
        guard let gray = Gray(cgImage, maxDim: 1280) else { return [] }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 16
        request.minimumConfidence = 0.3
        request.minimumAspectRatio = 0.6
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.02
        request.quadratureTolerance = 30
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil, let quads = request.results else { return [] }

        // The rectangle detector often fires on both edges of the black
        // border; keep one detection per tag id.
        var best: [Int: Detection] = [:]
        for obs in quads {
            guard let (tagID, det) = decode(obs, in: gray) else { continue }
            if let old = best[tagID], old.confidence >= det.confidence { continue }
            best[tagID] = det
        }
        return Array(best.values)
    }

    // MARK: quad → bits → id

    private static func decode(_ obs: VNRectangleObservation, in gray: Gray) -> (Int, Detection)? {
        // Vision corners are normalized, origin bottom-left; flip to pixels.
        func px(_ p: CGPoint) -> (Double, Double) {
            (Double(p.x) * Double(gray.width - 1), (1 - Double(p.y)) * Double(gray.height - 1))
        }
        guard let hom = Homography(px(obs.topLeft), px(obs.topRight),
                                   px(obs.bottomRight), px(obs.bottomLeft)) else { return nil }

        // Mean gray of each of the 8×8 cells (border ring + 6×6 data).
        var cells = [Double](repeating: 0, count: 64)
        var lo = 255.0, hi = 0.0
        let offsets: [(Double, Double)] = [(0, 0), (-0.15, -0.15), (0.15, -0.15), (-0.15, 0.15), (0.15, 0.15)]
        for cy in 0..<8 {
            for cx in 0..<8 {
                var acc = 0.0
                for (ou, ov) in offsets {
                    let (x, y) = hom.map((Double(cx) + 0.5 + ou) / 8, (Double(cy) + 0.5 + ov) / 8)
                    acc += gray.sample(x, y)
                }
                let m = acc / Double(offsets.count)
                cells[cy * 8 + cx] = m
                lo = min(lo, m); hi = max(hi, m)
            }
        }
        guard hi - lo > 30 else { return nil }  // flat patch, not a tag
        let threshold = (lo + hi) / 2

        // The border ring must be solid (black normally); a couple of cells
        // of slack for glare.
        var borderWhite = 0
        for i in 0..<8 {
            for j in [0, 7] {
                if cells[j * 8 + i] > threshold { borderWhite += 1 }
                if i != 0 && i != 7, cells[i * 8 + j] > threshold { borderWhite += 1 }
            }
        }

        var grid = [[Bool]](repeating: [Bool](repeating: false, count: 6), count: 6)
        for y in 0..<6 {
            for x in 0..<6 {
                grid[y][x] = cells[(y + 1) * 8 + (x + 1)] > threshold  // white = 1
            }
        }
        // Normal tags have a black border; if the border reads white, try the
        // inverted interpretation instead of rejecting outright.
        if borderWhite > 3 {
            guard borderWhite >= 25 else { return nil }
            for y in 0..<6 { for x in 0..<6 { grid[y][x].toggle() } }
        }

        // Try all four rotations against the codebook.
        var bestID = -1, bestHamming = Int.max
        for _ in 0..<4 {
            let code = pack(grid)
            for (id, known) in Tag36h11.codes.enumerated() {
                let d = (code ^ known).nonzeroBitCount
                if d < bestHamming { bestHamming = d; bestID = id }
            }
            grid = rotated(grid)
        }
        guard bestHamming <= 2 else { return nil }

        let det = Detection(
            kind: .aprilTag,
            payload: "tag36h11 #\(bestID)",
            detail: bestHamming == 0 ? "AprilTag" : "AprilTag · \(bestHamming) bit fix",
            confidence: 1 - Float(bestHamming) / 3,
            visionBox: obs.boundingBox)
        return (bestID, det)
    }

    /// Codeword from the 6×6 data grid, MSB first in the family's bit order.
    private static func pack(_ grid: [[Bool]]) -> UInt64 {
        var code: UInt64 = 0
        for i in 0..<36 {
            code = (code << 1) | (grid[Tag36h11.bitY[i] - 1][Tag36h11.bitX[i] - 1] ? 1 : 0)
        }
        return code
    }

    private static func rotated(_ g: [[Bool]]) -> [[Bool]] {
        let n = g.count
        var out = g
        for y in 0..<n { for x in 0..<n { out[y][x] = g[n - 1 - x][y] } }
        return out
    }

    // MARK: supporting cast

    /// 8-bit grayscale copy of the image, downsampled for cheap sampling.
    private struct Gray {
        let pixels: [UInt8]
        let width: Int, height: Int

        init?(_ cg: CGImage, maxDim: Int) {
            let scale = min(1, Double(maxDim) / Double(max(cg.width, cg.height)))
            width = max(8, Int(Double(cg.width) * scale))
            height = max(8, Int(Double(cg.height) * scale))
            let w = width, h = height
            var buf = [UInt8](repeating: 0, count: w * h)
            let ok = buf.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(
                    data: raw.baseAddress, width: w, height: h,
                    bitsPerComponent: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            pixels = buf
        }

        /// Bilinear sample at pixel coordinates, clamped to the image.
        func sample(_ x: Double, _ y: Double) -> Double {
            let cx = min(max(x, 0), Double(width - 1))
            let cy = min(max(y, 0), Double(height - 1))
            let x0 = Int(cx), y0 = Int(cy)
            let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
            let fx = cx - Double(x0), fy = cy - Double(y0)
            let p00 = Double(pixels[y0 * width + x0]), p10 = Double(pixels[y0 * width + x1])
            let p01 = Double(pixels[y1 * width + x0]), p11 = Double(pixels[y1 * width + x1])
            return (p00 * (1 - fx) + p10 * fx) * (1 - fy) + (p01 * (1 - fx) + p11 * fx) * fy
        }
    }

    /// Projective map from the unit square (u right, v down) onto a quad —
    /// Heckbert's classic square-to-quad derivation.
    private struct Homography {
        let a, b, c, d, e, f, g, h: Double

        init?(_ p0: (Double, Double), _ p1: (Double, Double),
              _ p2: (Double, Double), _ p3: (Double, Double)) {
            let sx = p0.0 - p1.0 + p2.0 - p3.0
            let sy = p0.1 - p1.1 + p2.1 - p3.1
            if abs(sx) < 1e-9 && abs(sy) < 1e-9 {
                a = p1.0 - p0.0; b = p3.0 - p0.0; c = p0.0
                d = p1.1 - p0.1; e = p3.1 - p0.1; f = p0.1
                g = 0; h = 0
                return
            }
            let dx1 = p1.0 - p2.0, dx2 = p3.0 - p2.0
            let dy1 = p1.1 - p2.1, dy2 = p3.1 - p2.1
            let den = dx1 * dy2 - dx2 * dy1
            guard abs(den) > 1e-9 else { return nil }
            g = (sx * dy2 - dx2 * sy) / den
            h = (dx1 * sy - sx * dy1) / den
            a = p1.0 - p0.0 + g * p1.0
            b = p3.0 - p0.0 + h * p3.0
            c = p0.0
            d = p1.1 - p0.1 + g * p1.1
            e = p3.1 - p0.1 + h * p3.1
            f = p0.1
        }

        func map(_ u: Double, _ v: Double) -> (Double, Double) {
            let w = g * u + h * v + 1
            return ((a * u + b * v + c) / w, (d * u + e * v + f) / w)
        }
    }
}
