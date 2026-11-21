import Foundation
import Vision
import CoreVideo

/// A detected quad, classified in CIELAB.
struct PaperQuad: Identifiable {
    enum Kind { case paper, sticky(hue: String), other }
    let id = UUID()
    /// Corners in Vision's normalized coordinates (origin bottom-left).
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint
    var kind: Kind
    var confidence: Float

    var label: String {
        switch kind {
        case .paper: return "paper"
        case .sticky(let hue): return "sticky · \(hue)"
        case .other: return "quad"
        }
    }
}

/// Traditional Apple CV: VNDetectRectanglesRequest is the classic
/// edge-and-quad detector (no neural net, fully on-device). Each hit is then
/// classified by sampling its interior in CIELAB: bright + low chroma →
/// paper; bright-ish + high chroma → sticky note.
final class PaperDetector {
    private let request: VNDetectRectanglesRequest

    init() {
        let r = VNDetectRectanglesRequest()
        r.maximumObservations = 8
        r.minimumConfidence = 0.5
        r.minimumAspectRatio = 0.2
        r.maximumAspectRatio = 1.0
        r.minimumSize = 0.05
        r.quadratureTolerance = 25
        request = r
    }

    func detect(pixelBuffer: CVPixelBuffer) -> [PaperQuad] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return [] }
        return observations.map { obs in
            PaperQuad(
                topLeft: obs.topLeft, topRight: obs.topRight,
                bottomRight: obs.bottomRight, bottomLeft: obs.bottomLeft,
                kind: classify(obs, in: pixelBuffer),
                confidence: obs.confidence)
        }
    }

    /// Sample a sparse grid inside the quad's bounding box and average Lab.
    private func classify(_ obs: VNRectangleObservation, in pixelBuffer: CVPixelBuffer) -> PaperQuad.Kind {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return .other }
        let buf = base.assumingMemoryBound(to: UInt8.self)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Inner 60% of the bounding box, to stay off the edges.
        let bb = obs.boundingBox
        let x0 = Int((bb.minX + 0.2 * bb.width) * CGFloat(width))
        let x1 = Int((bb.maxX - 0.2 * bb.width) * CGFloat(width))
        // Vision's origin is bottom-left; the buffer's is top-left.
        let y0 = Int((1 - bb.maxY + 0.2 * bb.height) * CGFloat(height))
        let y1 = Int((1 - bb.minY - 0.2 * bb.height) * CGFloat(height))
        guard x1 > x0, y1 > y0 else { return .other }

        var sumL: Float = 0, sumA: Float = 0, sumB: Float = 0
        var n: Float = 0
        let stepX = max(1, (x1 - x0) / 12), stepY = max(1, (y1 - y0) / 12)
        var y = max(0, y0)
        while y < min(height, y1) {
            let row = buf + y * rowBytes
            var x = max(0, x0)
            while x < min(width, x1) {
                let p = row + x * 4  // BGRA
                let lab = CIELAB.lab(r: p[2], g: p[1], b: p[0])
                sumL += lab.L; sumA += lab.a; sumB += lab.b; n += 1
                x += stepX
            }
            y += stepY
        }
        guard n > 0 else { return .other }
        let L = sumL / n, a = sumA / n, b = sumB / n
        let c = CIELAB.chroma(a: a, b: b)
        if L > 40, c > 22 { return .sticky(hue: CIELAB.hueName(a: a, b: b)) }
        if L > 55, c < 14 { return .paper }
        return .other
    }
}
