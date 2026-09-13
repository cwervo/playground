import AVFoundation
import AVKit
import Combine
import UIKit

/// Owns the `AVSampleBufferDisplayLayer` that feeds Picture in Picture.
/// The "video" is a sequence of still frames, one per stamp refresh.
final class PiPController: NSObject, ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isPossible = false
    @Published private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var lastError: String?
    /// Pixel size iOS is currently drawing the PiP window at.
    @Published private(set) var renderSize = CGSize(width: 0, height: 0)

    let displayLayer = AVSampleBufferDisplayLayer()

    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var lastImage: CGImage?

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.white.cgColor
        guard isSupported else { return }
        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        possibleObservation = pip.observe(\.isPictureInPicturePossible,
                                          options: [.initial, .new]) { [weak self] pip, _ in
            DispatchQueue.main.async { self?.isPossible = pip.isPictureInPicturePossible }
        }
        controller = pip
    }

    // MARK: Frames

    /// Shows `image` in the layer (and therefore in the PiP window).
    func show(_ image: CGImage) {
        lastImage = image
        if displayLayer.status == .failed || displayLayer.requiresFlushToResumeDecoding {
            displayLayer.flush()
        }
        guard let buffer = SampleBufferFactory.makeSampleBuffer(from: image) else {
            lastError = "Could not build a sample buffer."
            return
        }
        displayLayer.enqueue(buffer)
    }

    /// Re-enqueues the last frame; needed after a flush or a render-size change.
    func repaint() {
        if let lastImage { show(lastImage) }
    }

    // MARK: Control

    var canStartAutomatically: Bool {
        get { controller?.canStartPictureInPictureAutomaticallyFromInline ?? false }
        set { controller?.canStartPictureInPictureAutomaticallyFromInline = newValue }
    }

    func start() {
        guard let controller, !controller.isPictureInPictureActive else { return }
        AudioSession.activate()
        controller.startPictureInPicture()
    }

    func stop() {
        controller?.stopPictureInPicture()
    }

    func toggle() {
        isActive ? stop() : start()
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    setPlaying playing: Bool) {
        // Stills only: there is nothing to pause. Repaint so the window never blanks.
        repaint()
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        // Report a live, unbounded stream so PiP shows no scrubber.
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        renderSize = CGSize(width: Int(newRenderSize.width), height: Int(newRenderSize.height))
        repaint()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        lastError = nil
        repaint()
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        lastError = error.localizedDescription
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

// MARK: - Audio session

/// PiP from a sample buffer layer needs the `audio` background mode and an
/// active playback session, otherwise iOS refuses to start it.
enum AudioSession {
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("AudioSession: \(error)")
        }
    }
}
