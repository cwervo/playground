import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Turns a payload string into a crisp, nearest-neighbour scaled QR bitmap.
public enum QRRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// - Parameters:
    ///   - payload: UTF-8 text to encode.
    ///   - correction: L, M, Q or H.
    ///   - pixelSize: Width and height of the returned image.
    public static func image(for payload: String,
                             correction: StampSettings.ErrorCorrection,
                             pixelSize: Int) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = correction.rawValue
        guard let raw = filter.outputImage, raw.extent.width > 0 else { return nil }
        let scale = CGFloat(pixelSize) / raw.extent.width
        let scaled = raw
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: CGRect(x: 0, y: 0,
                                                         width: pixelSize,
                                                         height: pixelSize))
    }

    /// Modules per side, quiet zone included. Handy for showing density.
    public static func moduleCount(for payload: String,
                                   correction: StampSettings.ErrorCorrection) -> Int? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = correction.rawValue
        guard let raw = filter.outputImage else { return nil }
        return Int(raw.extent.width)
    }
}
