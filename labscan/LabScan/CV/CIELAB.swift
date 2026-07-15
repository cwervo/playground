import Foundation

/// sRGB (D65) → CIELAB, with the lookup tables precomputed so per-frame work
/// is a few table hits and one cube-root path per pixel.
enum CIELAB {
    /// 256-entry sRGB gamma → linear table.
    static let srgbToLinear: [Float] = (0..<256).map { i in
        let c = Float(i) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    @inline(__always)
    static func fLab(_ t: Float) -> Float {
        // CIE f(t): cube root above (6/29)^3, linear toe below.
        t > 0.008856 ? cbrt(t) : (7.787 * t + 16.0 / 116.0)
    }

    /// Full Lab from 8-bit sRGB. D65 white.
    @inline(__always)
    static func lab(r: UInt8, g: UInt8, b: UInt8) -> (L: Float, a: Float, b: Float) {
        let rl = srgbToLinear[Int(r)], gl = srgbToLinear[Int(g)], bl = srgbToLinear[Int(b)]
        // linear sRGB → XYZ (D65), already divided by white point (Xn, Yn, Zn)
        let x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
        let y =  0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
        let z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883
        let fx = fLab(x), fy = fLab(y), fz = fLab(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// The "red laser" signal: reflectance at ~650 nm is essentially the
    /// linear red channel; map it through the L* curve so thresholds behave
    /// perceptually. This is what a handheld laser wand sees — red ink
    /// vanishes, black/blue ink goes dark.
    @inline(__always)
    static func redLaserL(r: UInt8) -> Float {
        116 * fLab(srgbToLinear[Int(r)]) - 16
    }

    /// Chroma C*ab.
    @inline(__always)
    static func chroma(a: Float, b: Float) -> Float { (a * a + b * b).squareRoot() }

    /// Rough hue bucket name for sticky-note colors, from Lab hue angle.
    static func hueName(a: Float, b: Float) -> String {
        var deg = atan2(b, a) * 180 / .pi
        if deg < 0 { deg += 360 }
        switch deg {
        case 0..<35, 330..<360: return "pink/red"
        case 35..<75: return "orange"
        case 75..<115: return "yellow"
        case 115..<180: return "green"
        case 180..<260: return "cyan/blue"
        default: return "violet"
        }
    }
}
