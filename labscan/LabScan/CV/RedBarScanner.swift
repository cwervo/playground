import Foundation
import CoreVideo

/// What one frame's pass under the red bar produced.
struct ScanlineResult {
    /// Normalized (0…1) red-laser L* signal, one value per sampled column.
    var signal: [Float]
    /// Binarized signal after adaptive threshold (true = dark bar).
    var binary: [Bool]
    /// Decoded value, if any decoder fired this frame.
    var decode: BarcodeDecode?
}

struct BarcodeDecode: Equatable {
    var symbology: String  // "EAN-13", "UPC-A", "Code 39"
    var value: String
}

/// Extracts the 1-D scanline under the red bar and runs the old-school
/// decoders. Pure CPU, no ML, no network — just run lengths and tables.
struct RedBarScanner {
    /// Height of the sampled band in *source pixels* (the UI bar is 80 pt;
    /// we sample a proportional band of the capture buffer).
    var bandFraction: CGFloat = 80.0 / 844.0  // 80 pt on a typical phone height
    /// Vertical center of the bar, as a fraction of frame height.
    var centerY: CGFloat = 0.5
    /// Sample every Nth row of the band — 1–10 px tricks don't need them all.
    var rowStride = 4
    /// Sample every Nth column; 1 keeps full horizontal resolution.
    var colStride = 1

    func scan(pixelBuffer: CVPixelBuffer) -> ScanlineResult {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return ScanlineResult(signal: [], binary: [], decode: nil)
        }
        let buf = base.assumingMemoryBound(to: UInt8.self)

        let bandH = max(4, Int(CGFloat(height) * bandFraction))
        let y0 = min(max(0, Int(CGFloat(height) * centerY) - bandH / 2), height - bandH)

        // Collapse band rows into one scanline of red-laser L*.
        let cols = width / colStride
        var signal = [Float](repeating: 0, count: cols)
        var rows = 0
        var y = y0
        while y < y0 + bandH {
            let row = buf + y * rowBytes
            for c in 0..<cols {
                // BGRA: red is byte 2.
                signal[c] += CIELAB.redLaserL(r: row[c * colStride * 4 + 2])
            }
            rows += 1
            y += rowStride
        }
        var lo: Float = .greatestFiniteMagnitude, hi: Float = -.greatestFiniteMagnitude
        for c in 0..<cols {
            signal[c] /= Float(rows)
            lo = min(lo, signal[c]); hi = max(hi, signal[c])
        }
        // Not enough contrast under the bar → nothing to binarize.
        guard hi - lo > 12 else {
            let norm = signal.map { _ in Float(0.5) }
            return ScanlineResult(signal: norm, binary: .init(repeating: false, count: cols), decode: nil)
        }
        let norm = signal.map { ($0 - lo) / (hi - lo) }

        let binary = Self.adaptiveBinarize(norm)
        let runs = Self.runLengths(binary)
        var decode = EANUPCDecoder.decode(runs: runs) ?? Code39Decoder.decode(runs: runs)
        if decode == nil {
            let rev = Self.runLengths(binary.reversed().map { $0 })
            decode = EANUPCDecoder.decode(runs: rev) ?? Code39Decoder.decode(runs: rev)
        }
        return ScanlineResult(signal: norm, binary: binary, decode: decode)
    }

    /// Moving-mean adaptive threshold with hysteresis — the classic wand
    /// scanner front-end. Window ≈ width/16 so it tracks uneven lighting.
    static func adaptiveBinarize(_ s: [Float]) -> [Bool] {
        let n = s.count
        guard n > 32 else { return .init(repeating: false, count: n) }
        let w = max(8, n / 16)
        // Prefix sums for O(1) windowed means.
        var prefix = [Float](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + s[i] }
        var out = [Bool](repeating: false, count: n)
        var dark = false
        let hysteresis: Float = 0.04
        for i in 0..<n {
            let a = max(0, i - w / 2), b = min(n, i + w / 2)
            let mean = (prefix[b] - prefix[a]) / Float(b - a)
            let t = dark ? mean + hysteresis : mean - hysteresis
            dark = s[i] < t
            out[i] = dark
        }
        return out
    }

    /// Alternating run lengths. First element is always a *space* run
    /// (possibly zero-length) so decoders can index parity by position.
    static func runLengths(_ binary: [Bool]) -> [Int] {
        var runs: [Int] = []
        var current = false  // start expecting space
        var len = 0
        for bit in binary {
            if bit == current { len += 1 } else {
                runs.append(len)
                current = bit
                len = 1
            }
        }
        runs.append(len)
        return runs
    }
}
