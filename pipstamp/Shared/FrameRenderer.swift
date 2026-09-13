import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

/// Composes the QR code and a one-line caption into the bitmap that is shown
/// both in the PiP window and in the keyboard panel.
public enum FrameRenderer {
    public struct Layout {
        public var width: CGFloat = 768
        public var margin: CGFloat = 40
        public var captionHeight: CGFloat = 72
        public var gap: CGFloat = 12
        public init() {}

        public var qrSide: CGFloat { width - margin * 2 }
        public var height: CGFloat { margin + qrSide + gap + captionHeight + margin }
        public var size: CGSize { CGSize(width: width, height: height) }
    }

    /// Renders `markdown` as a QR code with `caption` under it.
    public static func render(markdown: String,
                              caption: String,
                              correction: StampSettings.ErrorCorrection,
                              layout: Layout = Layout()) -> CGImage? {
        guard let qr = QRRenderer.image(for: markdown,
                                        correction: correction,
                                        pixelSize: Int(layout.qrSide)) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: layout.size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: layout.size))

            cg.saveGState()
            cg.interpolationQuality = .none
            // CGContext draws images upside down unless we flip.
            let qrRect = CGRect(x: layout.margin, y: layout.margin,
                                width: layout.qrSide, height: layout.qrSide)
            cg.translateBy(x: 0, y: qrRect.maxY + qrRect.minY)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(qr, in: qrRect)
            cg.restoreGState()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingMiddle
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: layout.captionHeight * 0.42,
                                                   weight: .medium),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]
            let captionRect = CGRect(x: layout.margin,
                                     y: layout.margin + layout.qrSide + layout.gap,
                                     width: layout.qrSide,
                                     height: layout.captionHeight)
            (caption as NSString).draw(in: captionRect, withAttributes: attributes)
        }
        return image.cgImage
    }
}

/// Wraps a bitmap in a `CMSampleBuffer` that `AVSampleBufferDisplayLayer`
/// will show immediately. PiP is driven by exactly these buffers.
public enum SampleBufferFactory {
    public static func makeSampleBuffer(from image: CGImage) -> CMSampleBuffer? {
        let width = image.width
        let height = image.height
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary, &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        if let cg = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                              width: width, height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: bitmapInfo) {
            cg.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatOut: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatOut)
        guard let format = formatOut else { return nil }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sampleBufferOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: pixelBuffer,
                                                 formatDescription: format,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBufferOut)
        guard let sampleBuffer = sampleBufferOut else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                     createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0),
                                           to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sampleBuffer
    }
}
