import AVFoundation
import CoreImage
import UIKit

/// Owns the capture session and the per-frame pipeline. Every frame goes
/// under the red bar; the full-frame rectangle pass runs every few frames.
/// Nothing here (or anywhere in the app) touches the network.
final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    @Published var scanline = ScanlineResult(signal: [], binary: [], decode: nil)
    @Published var quads: [PaperQuad] = []
    @Published var confirmedDecode: BarcodeDecode?
    @Published var authorized = true
    /// Vertical center of the red bar (fraction of view height); draggable.
    @Published var barCenterY: CGFloat = 0.5

    private let queue = DispatchQueue(label: "labscan.camera", qos: .userInitiated)
    private var scanner = RedBarScanner()
    private let paperDetector = PaperDetector()
    private var frameCount = 0

    // Wand-scanner debounce: same value on N consecutive decoding frames.
    private var candidate: BarcodeDecode?
    private var candidateHits = 0
    private var lastFrame: CVPixelBuffer?

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async { self?.authorized = granted }
            guard granted else { return }
            self?.queue.async { self?.configure() }
        }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    private func configure() {
        guard session.inputs.isEmpty else { session.startRunning(); return }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        if let conn = output.connection(with: .video) {
            conn.videoRotationAngle = 90  // portrait
        }
        session.commitConfiguration()
        session.startRunning()

        // Continuous focus helps the 1-D read; nothing exotic.
        try? device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = pb
        frameCount += 1

        scanner.centerY = barCenterY
        let result = scanner.scan(pixelBuffer: pb)

        // Debounce decodes across frames before reporting.
        if let d = result.decode {
            if d == candidate { candidateHits += 1 } else { candidate = d; candidateHits = 1 }
        } else if candidateHits > 0 {
            candidateHits -= 1
        }
        let confirmed = candidateHits >= 3 ? candidate : nil

        let newQuads = frameCount % 4 == 0 ? paperDetector.detect(pixelBuffer: pb) : nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scanline = result
            if let confirmed, confirmed != self.confirmedDecode {
                self.confirmedDecode = confirmed
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            if let newQuads { self.quads = newQuads }
        }
    }

    /// Snapshot the most recent frame as a UIImage (local use only).
    func snapshot() -> UIImage? {
        var frame: CVPixelBuffer?
        queue.sync { frame = lastFrame }
        guard let frame else { return nil }
        let ci = CIImage(cvPixelBuffer: frame)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
