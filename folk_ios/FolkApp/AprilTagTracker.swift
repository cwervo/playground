import Foundation
import CoreGraphics
import AVFoundation

public struct TagDetection {
    public let id: Int
    public let corners: [CGPoint] // 4 corners normalized or in image pixels
}

public final class AprilTagTracker {
    
    private var td: UnsafeMutablePointer<apriltag_detector_t>?
    private var tf: UnsafeMutablePointer<apriltag_family_t>?
    
    public init() {
        td = apriltag_detector_create()
        tf = tagStandard52h13_create()
        
        if let td = td, let tf = tf {
            apriltag_detector_add_family_bits(td, tf, 2)
            td.pointee.quad_decimate = 2.0
            td.pointee.nthreads = 2
        }
    }
    
    deinit {
        if let tf = tf {
            tagStandard52h13_destroy(tf)
        }
        if let td = td {
            apriltag_detector_destroy(td)
        }
    }
    
    /// Processes a grayscale CVPixelBuffer and returns any detected tags.
    public func detect(pixelBuffer: CVPixelBuffer) -> [TagDetection] {
        guard let td = td else { return [] }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Plane 0 of bi-planar YCbCr is the grayscale Y channel luma buffer.
        // If it's a single plane grayscale format, Plane 0 is also correct.
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return []
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        
        // Wrap pixel buffer in AprilTag's u8 image struct (no copy)
        var img = image_u8_t(
            width: Int32(width),
            height: Int32(height),
            stride: Int32(bytesPerRow),
            buf: baseAddress.assumingMemoryBound(to: UInt8.self)
        )
        
        guard let detections = apriltag_detector_detect(td, &img) else {
            return []
        }
        
        var results: [TagDetection] = []
        let count = zarray_size(detections)
        
        for i in 0..<count {
            var detPtr: UnsafeMutableRawPointer? = nil
            zarray_get(detections, i, &detPtr)
            
            guard let det = detPtr?.assumingMemoryBound(to: apriltag_detection_t.self) else {
                continue
            }
            
            let tagId = Int(det.pointee.id)
            
            // Fixed-size array det.pointee.p imports into Swift as a tuple of 4 tuples:
            // ((Double, Double), (Double, Double), (Double, Double), (Double, Double))
            let p0 = CGPoint(x: det.pointee.p.0.0 / Double(width), y: det.pointee.p.0.1 / Double(height))
            let p1 = CGPoint(x: det.pointee.p.1.0 / Double(width), y: det.pointee.p.1.1 / Double(height))
            let p2 = CGPoint(x: det.pointee.p.2.0 / Double(width), y: det.pointee.p.2.1 / Double(height))
            let p3 = CGPoint(x: det.pointee.p.3.0 / Double(width), y: det.pointee.p.3.1 / Double(height))
            
            results.append(TagDetection(id: tagId, corners: [p0, p1, p2, p3]))
        }
        
        // Free detections array
        apriltag_detections_destroy(detections)
        
        return results
    }
}
