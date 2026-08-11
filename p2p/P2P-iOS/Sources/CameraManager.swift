import AVFoundation
import CoreImage
import SwiftUI

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var currentFrame: CGImage?
    @Published var isAuthorized: Bool = false

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var activeInput: AVCaptureDeviceInput?
    private let context = CIContext()
    private let sessionQueue = DispatchQueue(label: "cameraSessionQueue")
    private var currentPosition: AVCaptureDevice.Position = .back

    override init() {
        super.init()
        requestAccessAndStart()
    }

    private func requestAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            sessionQueue.async { self.setupSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.isAuthorized = granted }
                if granted {
                    self.sessionQueue.async { self.setupSession() }
                }
            }
        default:
            isAuthorized = false
        }
    }

    private func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    private func setupSession() {
        captureSession.beginConfiguration()

        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }

        guard let device = device(for: currentPosition) else {
            captureSession.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                activeInput = input
            }
        } catch {
            print("Error setting up camera input: \(error)")
        }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        videoOutput.connection(with: .video)?.videoRotationAngle = 90

        captureSession.commitConfiguration()
        captureSession.startRunning()
    }

    func switchCamera(next: Bool) {
        currentPosition = currentPosition == .back ? .front : .back

        sessionQueue.async {
            self.captureSession.beginConfiguration()
            if let currentInput = self.activeInput {
                self.captureSession.removeInput(currentInput)
            }

            if let device = self.device(for: self.currentPosition) {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.captureSession.canAddInput(input) {
                        self.captureSession.addInput(input)
                        self.activeInput = input
                    }
                } catch {
                    print("Error switching camera: \(error)")
                }
            }

            self.captureSession.commitConfiguration()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            DispatchQueue.main.async {
                self.currentFrame = cgImage
            }
        }
    }
}
