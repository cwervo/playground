import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import Metal
import MetalKit
import simd

/// Wires capture -> GPU segmentation -> detection -> touch state -> CGEvent,
/// and owns the two modes the app has: calibrating, and running.
final class AppController: NSObject {
    private let config = Config.shared

    private var ctx: MetalContext!
    private let camera = CameraSource()
    private var segmentation: SegmentationPipeline!
    private var detector = TipDetector()
    private var touch = TouchStateMachine()
    private var filter: OneEuroFilter
    private let injector: PointerInjector

    private let hudState = HUDStateBox()
    private var hudRenderer: HUDRenderer?
    private var overlay: OverlayWindow?
    private var statusItem: NSStatusItem?

    private var calibration: CalibrationData?
    private var calibrator: Calibrator?

    /// Bounded in-flight frames. Without this, a GPU hiccup lets the capture
    /// queue enqueue work faster than it drains and latency grows without bound
    /// — the pointer ends up chasing a fingertip that moved 200 ms ago.
    private let inFlight = DispatchSemaphore(value: 2)
    /// Holds the frame the HUD is currently sampling; dropping it would free
    /// the IOSurface out from under the render pass.
    private var latestFrame: CameraTexture?

    private var displayID: CGDirectDisplayID = CGMainDisplayID()
    private var enabled = false

    private var frameTimestamps: [Double] = []
    private var lastFrameStart: Double = 0

    override init() {
        filter = OneEuroFilter(minCutoff: config.filterMinCutoff,
                               beta: config.filterBeta,
                               derivativeCutoff: config.filterDerivativeCutoff)
        injector = PointerInjector(config: config)
        super.init()
    }

    // MARK: - Lifecycle

    func start() async {
        GPUTypes.verifyLayout()

        guard await Permissions.requestCamera() else {
            return fail("Camera access denied. Grant it in System Settings > Privacy & Security > Camera.")
        }
        if !Permissions.requestAccessibility() {
            note("Grant Accessibility to Sistine, then relaunch — pointer events cannot be posted without it.")
        }

        do {
            ctx = try MetalContext()
            try camera.start(config: config)
            camera.delegate = self

            let (w, h) = camera.dimensions
            segmentation = try SegmentationPipeline(ctx: ctx, width: w, height: h)

            displayID = CGMainDisplayID()
            let window = OverlayWindow(display: displayID, device: ctx.device)
            let renderer = try HUDRenderer(ctx: ctx, state: hudState,
                                           pixelFormat: window.metalView.colorPixelFormat)
            window.metalView.delegate = renderer
            window.orderFrontRegardless()
            overlay = window
            hudRenderer = renderer

            calibration = CalibrationStore.load()
            if let calibration {
                applyCalibration(calibration)
                note(String(format: "Loaded calibration (mean residual %.1f pt).",
                            calibration.map.residualStatistics.mean))
            } else {
                note("No calibration found — run Calibrate from the menu bar.")
            }
            installStatusItem()
        } catch {
            fail("\(error)")
        }
    }

    private func applyCalibration(_ data: CalibrationData) {
        let quad = data.map.screenQuadInCamera.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
        segmentation.setROI(quad.count == 4 ? quad : nil)
        hudState.update {
            $0.screenQuadInCamera = data.map.screenQuadInCamera
            $0.maskSize = SIMD2(data.maskWidth, data.maskHeight)
        }
    }

    // MARK: - Menu bar

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◌"
        let menu = NSMenu()
        menu.addItem(withTitle: "Enable Touch", action: #selector(toggleEnabled), keyEquivalent: "e")
            .target = self
        menu.addItem(withTitle: "Calibrate…", action: #selector(beginCalibration), keyEquivalent: "c")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        updateStatusTitle()
    }

    private func updateStatusTitle() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusItem?.button?.title = self.calibrator != nil ? "◎"
                : (self.enabled ? "●" : "◌")
        }
    }

    @objc private func toggleEnabled() {
        guard calibration != nil else { return note("Calibrate first.") }
        enabled = !enabled
        if !enabled {
            injector.releaseIfNeeded()
            touch.reset()
            detector.reset()
            filter.reset()
        }
        hudState.update { $0.enabled = self.enabled }
        updateStatusTitle()
    }

    @objc private func beginCalibration() {
        enabled = false
        injector.releaseIfNeeded()
        detector.reset()
        touch.reset()

        // Widen the ROI: before the map exists we do not know where the screen
        // is in camera space, so nothing can be clipped yet.
        segmentation.setROI(nil)
        camera.unlockExposureAndWhiteBalance()

        let bounds = DisplayGeometry.bounds(for: displayID)
        let (w, h) = camera.dimensions
        calibrator = Calibrator(config: config,
                                screenSize: SIMD2(Double(bounds.width), Double(bounds.height)),
                                displayID: displayID,
                                maskSize: SIMD2(w, h))
        hudState.update {
            $0.enabled = true
            $0.banner = "Hover one fingertip over the middle of the screen."
            $0.calibrationTarget = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            $0.calibrationProgress = (0, self.calibrator!.targets.count)
        }
        updateStatusTitle()
    }

    private func finishCalibration(_ calibrator: Calibrator) {
        self.calibrator = nil
        hudState.update {
            $0.calibrationTarget = nil
            $0.calibrationProgress = nil
            $0.banner = nil
        }

        switch calibrator.state {
        case .solved:
            guard let result = calibrator.result else { return }
            calibration = result
            try? CalibrationStore.save(result)
            applyCalibration(result)
            // Freeze the camera's colour response now that the skin model has
            // been fitted under exactly this lighting.
            camera.lockExposureAndWhiteBalance()
            let stats = result.map.residualStatistics
            note(String(format: "Calibrated. Mean residual %.1f pt, worst %.1f pt.",
                        stats.mean, stats.max))
            enabled = true
            hudState.update { $0.enabled = true }
        case .failed(let reason):
            note(reason)
        default:
            break
        }
        updateStatusTitle()
    }

    // MARK: - Per-frame

    private func handle(runs: ColumnRunTable, frame: CameraTexture, startTime: Double) {
        defer { inFlight.signal() }

        let contact = detector.detect(runs: runs, config: config)
        let event = touch.update(contact: contact, config: config)
        let now = monotonicSeconds()

        if let calibrator {
            let done = calibrator.consume(contact: contact,
                                          phase: touch.phase,
                                          pixelBuffer: frame.pixelBuffer)
            hudState.update {
                $0.contact = contact
                $0.phase = self.touch.phase
                if let target = calibrator.currentTarget {
                    let bounds = DisplayGeometry.bounds(for: self.displayID)
                    $0.calibrationTarget = CGPoint(x: min(target.x, bounds.width),
                                                   y: min(target.y, bounds.height))
                    $0.calibrationProgress = calibrator.progress
                    $0.banner = "Touch the ring with one fingertip and hold."
                }
            }
            if done { DispatchQueue.main.async { self.finishCalibration(calibrator) } }
            publishTiming(now: now, startTime: startTime, contact: contact, screenPoint: nil)
            return
        }

        guard enabled, let calibration, let event else {
            publishTiming(now: now, startTime: startTime, contact: contact, screenPoint: nil)
            return
        }

        let screenPoint = event.point.map { p -> CGPoint in
            let mapped = calibration.map.screenPoint(
                forCamera: SIMD2(Double(p.x), Double(p.y)))
            let smoothed = filter.filter(mapped, timestamp: now)
            return globalPoint(smoothed)
        }

        switch event {
        case .moved:
            if config.moveCursorWhileHovering, let screenPoint { injector.move(to: screenPoint) }
        case .down:
            if let screenPoint {
                // Reset the smoother on contact: the hover trajectory's velocity
                // estimate is stale the instant the finger stops descending, and
                // carrying it into the click drags the cursor off the target.
                filter.reset()
                injector.down(at: screenPoint)
            }
        case .dragged:
            if let screenPoint { injector.drag(to: screenPoint) }
        case .up:
            if let screenPoint { injector.up(at: screenPoint) }
        case .lost:
            injector.releaseIfNeeded()
            filter.reset()
        default:
            break
        }

        publishTiming(now: now, startTime: startTime, contact: contact, screenPoint: screenPoint)
    }

    private func globalPoint(_ local: SIMD2<Double>) -> CGPoint {
        let bounds = DisplayGeometry.bounds(for: displayID)
        return CGPoint(x: bounds.minX + min(max(local.x, 0), bounds.width - 1),
                       y: bounds.minY + min(max(local.y, 0), bounds.height - 1))
    }

    private func publishTiming(now: Double, startTime: Double,
                               contact: GlassContact?, screenPoint: CGPoint?)
    {
        frameTimestamps.append(now)
        if frameTimestamps.count > 60 { frameTimestamps.removeFirst() }
        let fps = frameTimestamps.count > 1
            ? Double(frameTimestamps.count - 1) / (frameTimestamps.last! - frameTimestamps.first!)
            : 0

        hudState.update {
            $0.contact = contact
            $0.phase = self.touch.phase
            $0.screenPoint = screenPoint.map {
                let b = DisplayGeometry.bounds(for: self.displayID)
                return CGPoint(x: $0.x - b.minX, y: $0.y - b.minY)
            }
            $0.fps = fps
            $0.frameMilliseconds = (now - startTime) * 1000
        }
    }

    // MARK: - Messaging

    private func note(_ message: String) {
        hudState.update { $0.banner = message }
        FileHandle.standardError.write(Data(("sistine: " + message + "\n").utf8))
    }

    private func fail(_ message: String) {
        note(message)
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Sistine cannot start"
            alert.informativeText = message
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }
}

extension AppController: CameraSourceDelegate {
    func cameraSource(_ source: CameraSource, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime) {
        guard let segmentation else { return }
        guard inFlight.wait(timeout: .now()) == .success else { return }   // drop, do not queue

        guard let luma = ctx.texture(from: pixelBuffer, plane: 0, format: .r8Unorm),
              let chroma = ctx.texture(from: pixelBuffer, plane: 1, format: .rg8Unorm) else {
            inFlight.signal()
            return
        }

        let skin = (calibration?.skin ?? .prior)
        let flipX = calibration?.map.flipX ?? (calibrator?.flipX ?? false)
        let flipY = calibration?.map.flipY ?? (calibrator?.flipY ?? false)
        let params = skin.params(config: config, flipX: flipX, flipY: flipY)

        latestFrame = luma
        hudRenderer?.publish(camera: luma.texture, mask: segmentation.lastMask)

        let start = monotonicSeconds()
        // Completion handlers on one MTLCommandQueue fire in commit order, so
        // detector and state-machine state stay effectively serialised without a
        // lock — but they do not fire on the capture thread, hence the capture
        // of everything this frame needs.
        segmentation.process(luma: luma.texture,
                             chroma: chroma.texture,
                             skinParams: params,
                             config: config) { [weak self] runs in
            self?.handle(runs: runs, frame: luma, startTime: start)
        }
    }
}

extension TouchEvent {
    var point: SIMD2<Float>? {
        switch self {
        case .moved(let p), .down(let p), .dragged(let p), .up(let p): return p
        case .lost: return nil
        }
    }
}

func monotonicSeconds() -> Double {
    var t = timespec()
    clock_gettime(CLOCK_MONOTONIC_RAW, &t)
    return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
}
