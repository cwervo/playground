import Foundation
import AVFoundation
import CoreGraphics

public protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didUpdateDetections detections: [TagDetection])
}

public final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public static let shared = CameraManager()
    
    public weak var delegate: CameraManagerDelegate?
    
    public private(set) var captureSession: AVCaptureSession?
    private let tracker = AprilTagTracker()
    private let folkEngine: FolkEngine
    
    private let sessionQueue = DispatchQueue(label: "org.folk.camera.session")
    private let videoQueue = DispatchQueue(label: "org.folk.camera.video", qos: .userInteractive)
    
    private var activeTagIds = Set<Int>()
    private var isCalibrating = false
    
    public init(engine: FolkEngine = FolkEngine()) {
        self.folkEngine = engine
        super.init()
    }
    
    public func start(completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            let success = self.setupSession()
            if success {
                self.captureSession?.startRunning()
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    public func stop() {
        sessionQueue.async {
            self.captureSession?.stopRunning()
            self.captureSession = nil
        }
    }
    
    private func setupSession() -> Bool {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720 // 720p is perfect balance of speed and resolution
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("CameraManager: Failed to get default camera.")
            return false
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                return false
            }
        } catch {
            print("CameraManager: Error setting video input: \(error)")
            return false
        }
        
        // Attempt to configure 120fps high frame rate if supported
        configureHighFrameRate(for: videoDevice)
        
        let videoOutput = AVCaptureVideoDataOutput()
        // Capture in bi-planar YpCbCr 420 (video range). Plane 0 is grayscale Y.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            return false
        }
        
        // Ensure orientation is locked to portrait or correct format
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
        
        session.commitConfiguration()
        self.captureSession = session
        return true
    }
    
    private func configureHighFrameRate(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            
            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?
            
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    // Look for formats that support high frame rates (ideal is 120fps)
                    if range.maxFrameRate >= 120.0 {
                        if bestFormat == nil || range.maxFrameRate > (bestFrameRateRange?.maxFrameRate ?? 0) {
                            bestFormat = format
                            bestFrameRateRange = range
                        }
                    }
                }
            }
            
            if let format = bestFormat, let range = bestFrameRateRange {
                device.activeFormat = format
                device.activeVideoMinFrameDuration = range.minFrameDuration
                device.activeVideoMaxFrameDuration = range.minFrameDuration // lock it
                print("CameraManager: Configured camera at \(range.maxFrameRate) fps")
            } else {
                print("CameraManager: 120fps not supported, defaulting to standard.")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("CameraManager: Failed to lock device configuration: \(error)")
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Detect tags using our C wrapper
        let detections = tracker.detect(pixelBuffer: pixelBuffer)
        
        // Extract the detected tag IDs
        let detectedIds = Set(detections.map { $0.id })
        
        // 1. Update Geometry Store for all detected tags (real-time coordinates)
        for det in detections {
            GeometryStore.shared.setQuad(for: det.id, corners: det.corners)
        }
        
        // 2. Topology changes: handle additions/retractions in the Folk Engine
        let newTags = detectedIds.subtracting(activeTagIds)
        let removedTags = activeTagIds.subtracting(detectedIds)
        
        for id in newTags {
            folkEngine.claim(["tag", "\(id)", "is", "active"])
        }
        
        for id in removedTags {
            folkEngine.retract(["tag", "\(id)", "is", "active"])
            GeometryStore.shared.removeQuad(for: id)
        }
        
        activeTagIds = detectedIds
        
        // Delegate callback for phone UI updates
        DispatchQueue.main.async {
            self.delegate?.cameraManager(self, didUpdateDetections: detections)
        }
    }
}
