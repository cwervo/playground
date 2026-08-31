import Foundation
import AVFoundation
import CoreVideo

protocol CameraSourceDelegate: AnyObject {
    func cameraSource(_ source: CameraSource, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime)
}

/// AVFoundation capture, configured for the two things that matter here:
/// the lowest-latency native format, and *locked* exposure / white balance.
///
/// Auto-exposure is the quiet killer of colour segmentation. When a bright
/// window opens on screen the AE loop shifts gain, every CbCr value slides, and
/// a skin model fitted a minute ago stops matching. We lock exposure, gain and
/// white balance after the calibration pass and never let them move again.
final class CameraSource: NSObject {
    weak var delegate: CameraSourceDelegate?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "sistine.capture", qos: .userInteractive)
    private var device: AVCaptureDevice?

    private(set) var dimensions = (width: 0, height: 0)

    func start(config: Config) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CaptureError.noCamera
        }
        self.device = device

        session.beginConfiguration()
        session.sessionPreset = .inputPriority   // we pick the format by hand below

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        // Full-range 4:2:0 biplanar: plane 0 is luma, plane 1 is CbCr. Choosing
        // this over BGRA is what lets the skin kernel skip colour conversion.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        output.alwaysDiscardsLateVideoFrames = true   // drop, never queue: latency > completeness
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.cannotAddOutput }
        session.addOutput(output)

        session.commitConfiguration()

        try configureFormat(device: device, config: config)
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
    }

    /// Pick the format closest to the requested resolution that can sustain the
    /// requested frame rate, then pin the frame duration so AVFoundation cannot
    /// quietly drop to 30 fps in dim light (which it will, if you let it).
    private func configureFormat(device: AVCaptureDevice, config: Config) throws {
        var best: AVCaptureDevice.Format?
        var bestScore = Int.max
        for format in device.formats {
            let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let fits = format.videoSupportedFrameRateRanges.contains {
                $0.maxFrameRate >= Double(config.targetFPS) - 0.5
            }
            guard fits else { continue }
            let score = abs(Int(d.width) - config.captureWidth)
                      + abs(Int(d.height) - config.captureHeight)
            if score < bestScore { bestScore = score; best = format }
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if let best {
            device.activeFormat = best
            let duration = CMTime(value: 1, timescale: CMTimeScale(config.targetFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
        let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        dimensions = (Int(d.width), Int(d.height))

        if device.isFocusModeSupported(.locked) {
            // The glass is a fixed distance away; hunting autofocus only blurs
            // the reflection at exactly the wrong moment.
            device.focusMode = .locked
        }
    }

    /// Called once the skin model has been fitted, so the lighting the model was
    /// trained under is the lighting it will run under.
    func lockExposureAndWhiteBalance() {
        guard let device else { return }
        try? device.lockForConfiguration()
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
        device.unlockForConfiguration()
    }

    func unlockExposureAndWhiteBalance() {
        guard let device else { return }
        try? device.lockForConfiguration()
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()
    }

    enum CaptureError: Error, CustomStringConvertible {
        case noCamera, cannotAddInput, cannotAddOutput

        var description: String {
            switch self {
            case .noCamera: return "No video capture device found."
            case .cannotAddInput: return "Could not attach the camera to the capture session."
            case .cannotAddOutput: return "Could not attach the video output to the capture session."
            }
        }
    }
}

extension CameraSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection)
    {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        delegate?.cameraSource(self, didOutput: pb,
                               at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
