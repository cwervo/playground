// SplitCam.swift — realtime CIELAB channel-threshold camera viewer.
//
// Live camera feed, converted RGB → CIELAB per frame with Core Image's
// native CIConvertRGBtoLab filter. Each L*/a*/b* channel is binned
// (binarized) at a user-set threshold, then converted back to RGB for
// display. Three vertical sliders in a bottom drawer set the thresholds;
// a dropdown in the top-left switches between available cameras.
//
// Cross-platform: macOS 14+ and iOS 17+.
// Build headlessly with ./build.sh (no Xcode GUI needed).

import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import ImageIO
import Vision
import WebKit
import Photos
import MetalKit

// MARK: - Camera capture + Lab processing

let buildTag = "v21"

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                           AVCapturePhotoCaptureDelegate {
    @Published var hasVideo = false
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String?
    @Published var denied = false
    @Published var frameCount = 0
    @Published var debugLines: [String] = []
    @Published var stillNames: [String] = []
    @Published var selectedStill: String?
    @Published var captures: [Capture] = []
    @Published var currentFPS: Double = 0
    @Published var fpsHistory: [Double] = [] // one sample per second, last 60
    @Published var stageStats = "" // per-frame stage timing, updated 1/sec

    struct Capture: Identifiable, Hashable {
        let id: String
        let original: URL
        let lab: URL
        let html: URL?
    }

    // On-screen + syslog debug trace.
    func dbg(_ line: String) {
        NSLog("[SplitCam] %@", line)
        DispatchQueue.main.async {
            self.debugLines.append(line)
            if self.debugLines.count > 8 {
                self.debugLines.removeFirst(self.debugLines.count - 8)
            }
        }
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "splitcam.capture")
    let metalDevice = MTLCreateSystemDefaultDevice()
    private lazy var ciContext: CIContext =
        metalDevice.map { CIContext(mtlDevice: $0) } ?? CIContext()
    var renderContext: CIContext { ciContext }
    // Separate CIContext for the gallery backdrop's Metal view so its GPU
    // work never serializes with the live pipeline's context.
    private lazy var backdropContext: CIContext =
        metalDevice.map { CIContext(mtlDevice: $0) } ?? CIContext()
    var backdropRenderContext: CIContext { backdropContext }

    // Latest frames, handed GPU-side to the Metal views. The lock is the
    // only cross-thread touchpoint between capture and display.
    private let imageLock = NSLock()
    private var _latestProcessed: CIImage?
    private var _latestRaw: CIImage?
    var latestProcessed: CIImage? {
        imageLock.lock()
        defer { imageLock.unlock() }
        return _latestProcessed
    }
    var latestRaw: CIImage? {
        imageLock.lock()
        defer { imageLock.unlock() }
        return _latestRaw
    }
    private func setProcessed(_ image: CIImage, raw: CIImage) {
        imageLock.lock()
        _latestProcessed = image
        _latestRaw = raw
        imageLock.unlock()
    }
    var drawMsEMA = 0.0 // main-thread only (written by the Metal draw loop)
    // Only read/written on `queue` (the capture callback queue).
    private var thresholds: (l: Double, a: Double, b: Double) = (0.5, 0.5, 0.5)
    private var stillImage: CIImage?
    private var activeStill = false
    private var pendingOCR: Bool? // queue-confined; non-nil = capture requested
    private var photoPendingOCR: Bool? // queue-confined
    private let photoOutput = AVCapturePhotoOutput()
    private var fpsWindowStart: TimeInterval = 0 // queue-confined
    private var fpsFrameCount = 0
    private var accGraphMs = 0.0 // queue-confined stage accumulator

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] note in
            self?.dbg("runtime error: \(note.userInfo?[AVCaptureSessionErrorKey] ?? "?")")
        }
        #if os(iOS)
        center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
        ) { [weak self] note in
            self?.dbg("interrupted, reason: \(note.userInfo?[AVCaptureSessionInterruptionReasonKey] ?? "?")")
        }
        center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
        ) { [weak self] _ in
            self?.dbg("interruption ended")
        }
        #endif
    }

    // The session can't start while the app is locked/backgrounded (e.g. a
    // remote `devicectl` launch); retry whenever the app becomes active.
    func ensureRunning() {
        queue.async {
            guard !self.activeStill, !self.session.isRunning else { return }
            if self.session.inputs.isEmpty {
                DispatchQueue.main.async { self.start() }
                return
            }
            self.session.startRunning()
            self.dbg("restart attempt, running: \(self.session.isRunning)")
        }
    }

    // Request camera access on first open, then start the session.
    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        dbg("auth status: \(status.rawValue)")
        switch status {
        case .authorized:
            refreshDevicesAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.dbg("access granted: \(granted)")
                DispatchQueue.main.async {
                    self.denied = !granted
                    if granted { self.refreshDevicesAndRun() }
                }
            }
        default:
            denied = true
            if let first = stillNames.first { select(still: first) }
        }
    }

    func setThresholds(l: Double, a: Double, b: Double) {
        queue.async {
            self.thresholds = (l, a, b)
            if self.activeStill { self.renderStill() }
        }
    }

    func select(deviceID: String) {
        selectedDeviceID = deviceID
        selectedStill = nil
        queue.async {
            self.activeStill = false
            self.stillImage = nil
            self.configureSession(deviceID: deviceID)
        }
    }

    // MARK: Bundled still images (simulated cameras)

    private static func mediaURL(_ name: String? = nil) -> URL? {
        guard var url = Bundle.main.resourceURL?
            .appendingPathComponent("Media", isDirectory: true) else { return nil }
        if let name { url.appendPathComponent(name) }
        return url
    }

    func loadStills() {
        guard let dir = Self.mediaURL() else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        stillNames = files
            .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .map(\.lastPathComponent)
            .sorted()
    }

    func select(still name: String) {
        selectedStill = name
        selectedDeviceID = nil
        queue.async {
            self.activeStill = true
            if self.session.isRunning { self.session.stopRunning() }
            guard let url = Self.mediaURL(name),
                  var image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
            else {
                self.dbg("still load failed: \(name)")
                return
            }
            // Keep slider-drag re-renders cheap.
            let maxDim = max(image.extent.width, image.extent.height)
            if maxDim > 1400 {
                let s = 1400 / maxDim
                image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            }
            self.stillImage = image
            self.dbg("viewing still: \(name)")
            self.renderStill()
        }
    }

    // Runs on `queue`.
    private func renderStill() {
        guard let stillImage else { return }
        setProcessed(process(stillImage), raw: stillImage)
        DispatchQueue.main.async {
            self.hasVideo = true
            self.frameCount += 1
        }
    }

    // MARK: Capture, offline OCR, and local gallery

    // Capture the current frame: saves the original, its Lab-binned version,
    // and (optionally) an HTML rendition of on-device-OCR'd text into
    // Documents/Gallery/<timestamp>/.
    func capturePhoto(ocr: Bool) {
        queue.async {
            if self.activeStill {
                guard let still = self.stillImage else { return }
                let processed = self.process(still)
                guard let processedCG = self.ciContext.createCGImage(
                    processed, from: processed.extent) else { return }
                self.saveCapture(originalCI: still, processedCG: processedCG, ocr: ocr)
            } else if self.session.isRunning, self.session.outputs.contains(self.photoOutput) {
                // Full-resolution still — far more pixels for OCR than a
                // video frame.
                self.photoPendingOCR = ocr
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            } else {
                self.pendingOCR = ocr // fulfilled by the next camera frame
            }
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        queue.async {
            let ocr = self.photoPendingOCR ?? false
            self.photoPendingOCR = nil
            guard error == nil, let cgImage = photo.cgImageRepresentation() else {
                self.dbg("photo capture failed (\(error?.localizedDescription ?? "?")) — using video frame")
                self.pendingOCR = ocr
                return
            }
            var image = CIImage(cgImage: cgImage)
            #if os(iOS)
            if let raw = photo.metadata[kCGImagePropertyOrientation as String] as? UInt32,
               let orientation = CGImagePropertyOrientation(rawValue: raw) {
                image = image.oriented(orientation)
            }
            #endif
            let processed = self.process(image)
            guard let processedCG = self.ciContext.createCGImage(
                processed, from: processed.extent) else { return }
            self.saveCapture(originalCI: image, processedCG: processedCG, ocr: ocr)
        }
    }

    static func galleryDir() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gallery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func loadCaptures() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: Self.galleryDir(), includingPropertiesForKeys: nil)) ?? []
        captures = folders
            .filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { folder in
                let html = folder.appendingPathComponent("text.html")
                return Capture(
                    id: folder.lastPathComponent,
                    original: folder.appendingPathComponent("original.jpg"),
                    lab: folder.appendingPathComponent("lab.jpg"),
                    html: FileManager.default.fileExists(atPath: html.path) ? html : nil)
            }
    }

    // Runs on `queue`.
    private func saveCapture(originalCI: CIImage, processedCG: CGImage, ocr: Bool) {
        guard let originalCG = ciContext.createCGImage(originalCI, from: originalCI.extent)
        else {
            dbg("capture failed: could not render original")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let folder = Self.galleryDir().appendingPathComponent(stamp, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            dbg("capture failed: \(error.localizedDescription)")
            return
        }
        Self.writeJPEG(originalCG, to: folder.appendingPathComponent("original.jpg"))
        Self.writeJPEG(processedCG, to: folder.appendingPathComponent("lab.jpg"))
        if ocr {
            // Off the capture queue — three accurate-mode passes take a
            // couple of seconds and must not stall the live preview.
            DispatchQueue.global(qos: .userInitiated).async {
                var found = 0
                var ocrError: String?
                let html = Self.ocrHTML(from: originalCG, linesFound: &found, error: &ocrError)
                if let html {
                    try? html.write(
                        to: folder.appendingPathComponent("text.html"),
                        atomically: true, encoding: .utf8)
                }
                if let ocrError { self.dbg("ocr error: \(ocrError)") }
                self.dbg("saved \(stamp) · ocr: \(found) lines")
                DispatchQueue.main.async { self.loadCaptures() }
            }
        } else {
            dbg("saved \(stamp)")
            DispatchQueue.main.async { self.loadCaptures() }
        }
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImage(dest, image, options)
        CGImageDestinationFinalize(dest)
    }

    private struct OCRLine {
        let text: String
        let anchorX: Double // px, original image space
        let anchorY: Double
        let fontPx: Double
        let rotation: Int // CSS degrees: 0, -90 (bottom-to-top), 90 (top-to-bottom)
        let sampleRect: CGRect // original-space box, for ink color + dedup
    }

    // On-device OCR via the Vision framework (no network). Each recognized
    // line becomes an absolutely-positioned <div> whose inline style
    // preserves the estimated position, size, rotation, and ink color of
    // the original. Three passes — upright plus both 90° orientations —
    // so vertical text (book spines, posters) is recognized too.
    private static func ocrHTML(
        from cgImage: CGImage, linesFound: inout Int, error errorOut: inout String?
    ) -> String? {
        let width = Double(cgImage.width)
        let height = Double(cgImage.height)
        var lines: [OCRLine] = []

        let passes: [(CGImagePropertyOrientation, Int)] = [(.up, 0), (.right, -90), (.left, 90)]
        for (orientation, cssRotation) in passes {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Vision's default skips text shorter than ~1/32 of the image
            // height; distant/small text needs a much lower floor.
            request.minimumTextHeight = 0.008
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                errorOut = error.localizedDescription
                continue
            }
            // Rotated passes hallucinate more, so hold them to a higher bar.
            let minConfidence: Float = orientation == .up ? 0.2 : 0.55
            let orientedW = orientation == .up ? width : height
            let orientedH = orientation == .up ? height : width

            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= minConfidence else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespaces)
                guard text.count >= (orientation == .up ? 1 : 2) else { continue }

                let box = observation.boundingBox // normalized, origin bottom-left
                let px = box.minX * orientedW // oriented-space top-left, pixels
                let py = (1 - box.maxY) * orientedH
                let boxW = box.width * orientedW
                let boxH = box.height * orientedH

                let anchorX: Double, anchorY: Double
                let sampleRect: CGRect
                switch orientation {
                case .right: // image was rotated 90° CW for this pass
                    anchorX = py
                    anchorY = height - px
                    sampleRect = CGRect(x: py, y: height - px - boxW, width: boxH, height: boxW)
                case .left: // rotated 90° CCW
                    anchorX = width - py
                    anchorY = px
                    sampleRect = CGRect(x: width - py - boxH, y: px, width: boxH, height: boxW)
                default:
                    anchorX = px
                    anchorY = py
                    sampleRect = CGRect(x: px, y: py, width: boxW, height: boxH)
                }

                // In the upright pass, trust the observation's quad: Vision
                // reads rotated text natively and reports a rotated quad,
                // which yields the true angle, glyph height, and anchor.
                if orientation == .up {
                    let tl = CGPoint(
                        x: observation.topLeft.x * width,
                        y: (1 - observation.topLeft.y) * height)
                    let tr = CGPoint(
                        x: observation.topRight.x * width,
                        y: (1 - observation.topRight.y) * height)
                    let bl = CGPoint(
                        x: observation.bottomLeft.x * width,
                        y: (1 - observation.bottomLeft.y) * height)
                    let angle = atan2(tr.y - tl.y, tr.x - tl.x) * 180 / .pi
                    let glyphHeight = hypot(bl.x - tl.x, bl.y - tl.y)
                    let rotation = abs(angle) < 5 ? 0 : Int(angle.rounded())
                    lines.append(OCRLine(
                        text: text, anchorX: tl.x, anchorY: tl.y,
                        fontPx: max(6.0, glyphHeight * 0.8), rotation: rotation,
                        sampleRect: sampleRect))
                    continue
                }

                // Skip rotated hits that overlap text already found upright.
                if cssRotation != 0,
                   lines.contains(where: {
                       let overlap = $0.sampleRect.intersection(sampleRect)
                       return overlap.width * overlap.height > 0.3 * boxW * boxH
                   }) { continue }

                lines.append(OCRLine(
                    text: text, anchorX: anchorX, anchorY: anchorY,
                    fontPx: max(6.0, boxH * 0.8), rotation: cssRotation,
                    sampleRect: sampleRect))
            }
        }
        guard !lines.isEmpty else { return nil }
        linesFound = lines.count

        var divs = ""
        for line in lines {
            let (r, g, b) = inkColor(of: cgImage, in: line.sampleRect)
            let escaped = line.text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let transform = line.rotation == 0
                ? "" : "transform:rotate(\(line.rotation)deg);transform-origin:left top;"
            divs += String(
                format: "<div style=\"position:absolute;left:%.2f%%;top:%.2f%%;"
                    + "font-size:%.0fpx;line-height:1;white-space:nowrap;"
                    + "color:rgb(%d,%d,%d);%@\">%@</div>\n",
                line.anchorX / width * 100, line.anchorY / height * 100,
                line.fontPx, r, g, b, transform, escaped)
        }
        return """
        <!doctype html>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <div style="position:relative;width:100%;aspect-ratio:\(Int(width))/\(Int(height));\
        background:#f8f8f6;overflow:hidden;font-family:-apple-system,sans-serif;">
        \(divs)</div>
        """
    }

    // Estimate the text ("ink") color inside a box: split its pixels into
    // darker/lighter-than-mean clusters and take the minority cluster's mean
    // color — text usually covers less area than its background.
    private static func inkColor(of cgImage: CGImage, in rect: CGRect) -> (Int, Int, Int) {
        guard let crop = cgImage.cropping(to: rect.integral) else { return (0, 0, 0) }
        let w = max(1, min(crop.width, 48))
        let h = max(1, min(crop.height, 48))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return (0, 0, 0) }

        var lumas = [Double]()
        lumas.reserveCapacity(w * h)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            lumas.append(0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1])
                         + 0.114 * Double(pixels[i + 2]))
        }
        let mean = lumas.reduce(0, +) / Double(lumas.count)
        var dark = (r: 0.0, g: 0.0, b: 0.0, n: 0)
        var light = (r: 0.0, g: 0.0, b: 0.0, n: 0)
        var index = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            if lumas[index] < mean {
                dark.r += Double(pixels[i]); dark.g += Double(pixels[i + 1])
                dark.b += Double(pixels[i + 2]); dark.n += 1
            } else {
                light.r += Double(pixels[i]); light.g += Double(pixels[i + 1])
                light.b += Double(pixels[i + 2]); light.n += 1
            }
            index += 1
        }
        let ink = (dark.n > 0 && (light.n == 0 || dark.n <= light.n)) ? dark : light
        guard ink.n > 0 else { return (0, 0, 0) }
        return (Int(ink.r / Double(ink.n)), Int(ink.g / Double(ink.n)),
                Int(ink.b / Double(ink.n)))
    }

    // Runs on `queue`. When the camera can't start, show a bundled still.
    private func fallbackToStill() {
        DispatchQueue.main.async {
            guard self.selectedStill == nil, let first = self.stillNames.first else { return }
            self.dbg("no camera → viewing \(first)")
            self.select(still: first)
        }
    }

    private func refreshDevicesAndRun() {
        #if os(macOS)
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera,
        ]
        #else
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .external,
        ]
        #endif
        devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices
        dbg("cameras: \(devices.map(\.localizedName).joined(separator: ", "))")
        guard let first = devices.first else {
            if let still = stillNames.first { select(still: still) }
            return
        }
        select(deviceID: selectedDeviceID ?? first.uniqueID)
    }

    // Runs on `queue`.
    private func configureSession(deviceID: String) {
        guard let device = AVCaptureDevice(uniqueID: deviceID) else { return }

        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        if session.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.videoSettings =
                [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                dbg("session refused input: \(device.localizedName)")
            }
        } catch {
            dbg("input failed: \(error)")
        }
        session.commitConfiguration()

        if let output = session.outputs.first as? AVCaptureVideoDataOutput,
           let connection = output.connection(with: .video) {
            #if os(iOS)
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            #endif
            if device.position == .front, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        if !session.isRunning { session.startRunning() }
        dbg("session running: \(session.isRunning) (\(device.localizedName))")
        if !session.isRunning { fallbackToStill() }
    }

    private var loggedFirstFrame = false

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !activeStill, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let tStart = Date().timeIntervalSinceReferenceDate
        let rawImage = CIImage(cvPixelBuffer: buffer)
        let processed = process(rawImage)
        let tGraph = Date().timeIntervalSinceReferenceDate
        accGraphMs += (tGraph - tStart) * 1000
        // GPU-direct: hand the (unevaluated) CI graphs to the Metal views.
        // No createCGImage, no GPU→CPU copy, no per-frame main-thread work.
        setProcessed(processed, raw: rawImage)
        if !loggedFirstFrame {
            loggedFirstFrame = true
            dbg("first frame: \(Int(processed.extent.width))x\(Int(processed.extent.height)) (gpu-direct)")
            DispatchQueue.main.async { self.hasVideo = true }
        }
        if let ocr = pendingOCR {
            pendingOCR = nil
            if let processedCG = ciContext.createCGImage(processed, from: processed.extent) {
                saveCapture(
                    originalCI: CIImage(cvPixelBuffer: buffer), processedCG: processedCG, ocr: ocr)
            }
        }
        fpsFrameCount += 1
        let now = Date().timeIntervalSinceReferenceDate
        if fpsWindowStart == 0 { fpsWindowStart = now }
        if now - fpsWindowStart >= 1.0 {
            let frames = Double(max(fpsFrameCount, 1))
            let fps = Double(fpsFrameCount) / (now - fpsWindowStart)
            let graphAvg = accGraphMs / frames
            let batch = fpsFrameCount
            accGraphMs = 0
            fpsWindowStart = now
            fpsFrameCount = 0
            DispatchQueue.main.async {
                self.currentFPS = fps
                self.fpsHistory.append(fps)
                if self.fpsHistory.count > 60 {
                    self.fpsHistory.removeFirst(self.fpsHistory.count - 60)
                }
                self.frameCount += batch
                self.stageStats = String(
                    format: "ci %.1f · draw %.1f ms · gpu-direct",
                    graphAvg, self.drawMsEMA)
            }
        }
    }

    // RGB → Lab (normalized to 0…1), bin each channel at its threshold,
    // Lab → RGB. Runs on `queue`.
    private func process(_ image: CIImage) -> CIImage {
        let t = thresholds

        let toLab = CIFilter.convertRGBtoLab()
        toLab.inputImage = image
        toLab.normalize = true

        // Steep linear ramp centered on each threshold ≈ a step function;
        // the small transition band avoids shimmering at bin edges.
        let steep: CGFloat = 40
        let gate = CIFilter.colorMatrix()
        gate.inputImage = toLab.outputImage
        gate.rVector = CIVector(x: steep, y: 0, z: 0, w: 0)
        gate.gVector = CIVector(x: 0, y: steep, z: 0, w: 0)
        gate.bVector = CIVector(x: 0, y: 0, z: steep, w: 0)
        gate.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        gate.biasVector = CIVector(
            x: 0.5 - steep * t.l, y: 0.5 - steep * t.a, z: 0.5 - steep * t.b, w: 0)

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = gate.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)

        // Map the binary 0/1 bins to displayable Lab extremes: L stays
        // near-full range, a*/b* pull in so reconstructed RGB stays in gamut.
        let remap = CIFilter.colorMatrix()
        remap.inputImage = clamp.outputImage
        remap.rVector = CIVector(x: 0.96, y: 0, z: 0, w: 0)
        remap.gVector = CIVector(x: 0, y: 0.6, z: 0, w: 0)
        remap.bVector = CIVector(x: 0, y: 0, z: 0.6, w: 0)
        remap.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        remap.biasVector = CIVector(x: 0.02, y: 0.2, z: 0.2, w: 0)

        let toRGB = CIFilter.convertLabToRGB()
        toRGB.inputImage = remap.outputImage
        toRGB.normalize = true
        return toRGB.outputImage ?? image
    }
}

// MARK: - Metal-backed video view (GPU-direct, no per-frame CPU copies)

struct MetalCameraView {
    let camera: CameraManager

    final class Coordinator: NSObject, MTKViewDelegate {
        let camera: CameraManager
        let commandQueue: MTLCommandQueue?

        init(camera: CameraManager) {
            self.camera = camera
            commandQueue = camera.metalDevice?.makeCommandQueue()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let image = camera.latestProcessed,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
            let tStart = Date().timeIntervalSinceReferenceDate
            let drawableW = Double(drawable.texture.width)
            let drawableH = Double(drawable.texture.height)
            let scale = min(drawableW / image.extent.width, drawableH / image.extent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let centered = scaled
                .transformed(by: CGAffineTransform(
                    translationX: (drawableW - scaled.extent.width) / 2 - scaled.extent.minX,
                    y: (drawableH - scaled.extent.height) / 2 - scaled.extent.minY))
                .composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0)))
            camera.renderContext.render(
                centered, to: drawable.texture, commandBuffer: commandBuffer,
                bounds: CGRect(x: 0, y: 0, width: drawableW, height: drawableH),
                colorSpace: CGColorSpaceCreateDeviceRGB())
            commandBuffer.present(drawable)
            commandBuffer.commit()
            let ms = (Date().timeIntervalSinceReferenceDate - tStart) * 1000
            camera.drawMsEMA = camera.drawMsEMA * 0.9 + ms * 0.1
        }
    }

    func makeView(coordinator: Coordinator) -> MTKView {
        let view = MTKView(frame: .zero, device: camera.metalDevice)
        view.framebufferOnly = false // CIContext renders into the drawable
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = coordinator
        return view
    }
}

#if os(iOS)
extension MetalCameraView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }
    func makeUIView(context: Context) -> MTKView {
        let view = makeView(coordinator: context.coordinator)
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {}
}
#else
extension MetalCameraView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }
    func makeNSView(context: Context) -> MTKView { makeView(coordinator: context.coordinator) }
    func updateNSView(_ view: MTKView, context: Context) {}
}
#endif

// MARK: - Metal-backed gallery backdrop (continuous 28fps blur, GPU-only)

// Smooth frosted-glass background: blur the live feed at 28fps entirely on
// the GPU. Replaces the 1fps snapshot + crossfade ("LERP") approach, which
// read as a slow strobe and caused motion sickness.
struct MetalBackdropView {
    let camera: CameraManager

    final class Coordinator: NSObject, MTKViewDelegate {
        let camera: CameraManager
        let commandQueue: MTLCommandQueue?

        init(camera: CameraManager) {
            self.camera = camera
            commandQueue = camera.metalDevice?.makeCommandQueue()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let base = camera.latestRaw,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }
            let drawableW = Double(drawable.texture.width)
            let drawableH = Double(drawable.texture.height)
            // Blur at 420p, then scale up to cover the drawable.
            let down = 420.0 / max(base.extent.height, 1)
            let small = base.transformed(by: CGAffineTransform(scaleX: down, y: down))
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = small.clampedToExtent()
            blur.radius = 12
            guard let blurred = blur.outputImage?.cropped(to: small.extent) else { return }
            let cover = max(drawableW / blurred.extent.width, drawableH / blurred.extent.height)
            let scaled = blurred.transformed(by: CGAffineTransform(scaleX: cover, y: cover))
            let centered = scaled
                .transformed(by: CGAffineTransform(
                    translationX: (drawableW - scaled.extent.width) / 2 - scaled.extent.minX,
                    y: (drawableH - scaled.extent.height) / 2 - scaled.extent.minY))
                .composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0)))
            camera.backdropRenderContext.render(
                centered, to: drawable.texture, commandBuffer: commandBuffer,
                bounds: CGRect(x: 0, y: 0, width: drawableW, height: drawableH),
                colorSpace: CGColorSpaceCreateDeviceRGB())
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    func makeView(coordinator: Coordinator) -> MTKView {
        let view = MTKView(frame: .zero, device: camera.metalDevice)
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 28
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = coordinator
        return view
    }
}

#if os(iOS)
extension MetalBackdropView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }
    func makeUIView(context: Context) -> MTKView {
        let view = makeView(coordinator: context.coordinator)
        view.backgroundColor = .black
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {}
}
#else
extension MetalBackdropView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }
    func makeNSView(context: Context) -> MTKView { makeView(coordinator: context.coordinator) }
    func updateNSView(_ view: MTKView, context: Context) {}
}
#endif

// MARK: - FPS monitor (tap to toggle sparkline ↔ expanded)

struct FPSMonitor: View {
    @ObservedObject var camera: CameraManager
    @AppStorage("fpsMonitorExpanded") private var expanded = true

    private var fpsColor: Color {
        camera.currentFPS >= 24 ? .green : camera.currentFPS >= 15 ? .orange : .red
    }

    var body: some View {
        Group {
            if expanded { expandedCard } else { sparkline(width: 64, height: 20).padding(8) }
        }
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(duration: 0.25)) { expanded.toggle() }
        }
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", camera.currentFPS))
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(fpsColor)
                Text("fps").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            sparkline(width: 132, height: 30)
            if let minimum = camera.fpsHistory.min(), !camera.fpsHistory.isEmpty {
                let average = camera.fpsHistory.reduce(0, +) / Double(camera.fpsHistory.count)
                Text(String(format: "min %.0f · avg %.0f · 60s", minimum, average))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if !camera.stageStats.isEmpty {
                Text(camera.stageStats)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(10)
    }

    private func sparkline(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let samples = camera.fpsHistory
            guard samples.count > 1 else { return }
            let top = max(samples.max() ?? 30, 30)
            var path = Path()
            for (i, sample) in samples.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(samples.count - 1)
                let y = size.height * (1 - CGFloat(sample / top))
                i == 0 ? path.move(to: CGPoint(x: x, y: y))
                       : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .color(fpsColor), lineWidth: 1.5)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Vertical slider with an axis gradient track

struct VerticalSlider: View {
    @Binding var value: Double // 0…1, bottom to top
    let label: String
    let gradient: Gradient

    private let trackWidth: CGFloat = 30
    private let thumbHeight: CGFloat = 6

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: trackWidth / 2)
                        .fill(LinearGradient(
                            gradient: gradient, startPoint: .bottom, endPoint: .top))
                        .overlay(
                            RoundedRectangle(cornerRadius: trackWidth / 2)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    RoundedRectangle(cornerRadius: thumbHeight / 2)
                        .fill(.white)
                        .frame(width: trackWidth + 10, height: thumbHeight)
                        .shadow(radius: 2)
                        .offset(y: -value * (geo.size.height - thumbHeight))
                }
                .frame(width: trackWidth)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        value = min(max(1 - g.location.y / geo.size.height, 0), 1)
                    })
            }
            Text(label)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(width: trackWidth + 24)
    }
}

// MARK: - Color separation explorer

// Three blend-moded dots — the "printer dots" of the color-separation
// metaphor. Print mode multiplies C/M/Y inks on white paper; Light mode
// screens R/G/B light on a black screen. Drag the dots to explore how
// the separations recombine where they overlap.
struct SeparationExplorer: View {
    enum Mode: String, CaseIterable {
        case print = "Print · CMY"
        case light = "Light · RGB"
    }

    @State private var mode: Mode = .print
    @State private var offsets: [CGSize] = [
        CGSize(width: -42, height: 32),
        CGSize(width: 42, height: 32),
        CGSize(width: 0, height: -42),
    ]
    @State private var dragStarts: [Int: CGSize] = [:]

    private let dotSize: CGFloat = 130

    private var colors: [Color] {
        switch mode {
        case .print:
            return [
                Color(red: 0, green: 1, blue: 1),   // cyan
                Color(red: 1, green: 0, blue: 1),   // magenta
                Color(red: 1, green: 1, blue: 0),   // yellow
            ]
        case .light:
            return [
                Color(red: 1, green: 0, blue: 0),
                Color(red: 0, green: 1, blue: 0),
                Color(red: 0, green: 0, blue: 1),
            ]
        }
    }

    private var blend: BlendMode { mode == .print ? .multiply : .screen }
    private var paper: Color { mode == .print ? .white : .black }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(paper)
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(colors[i])
                        .frame(width: dotSize, height: dotSize)
                        .blendMode(blend)
                        .offset(offsets[i])
                        .gesture(
                            DragGesture()
                                .onChanged { g in
                                    let start = dragStarts[i] ?? offsets[i]
                                    dragStarts[i] = start
                                    offsets[i] = CGSize(
                                        width: start.width + g.translation.width,
                                        height: start.height + g.translation.height)
                                }
                                .onEnded { _ in dragStarts[i] = nil })
                }
            }
            .compositingGroup()
            .frame(width: 320, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(mode == .print
                 ? "Inks subtract — all three make black"
                 : "Light adds — all three make white")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Main view

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var lThreshold = 0.5
    @State private var aThreshold = 0.5
    @State private var bThreshold = 0.5
    @State private var drawerOpen = true
    @State private var showSeparation = false
    @State private var hudCollapsed = false
    @State private var ocrEnabled = false
    @State private var showGallery = false
    @State private var captureFlash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MetalCameraView(camera: camera)
            if !camera.hasVideo {
                if camera.denied {
                    Text("Camera access is off. Enable it in Settings ▸ Privacy & Security ▸ Camera, then relaunch.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(40)
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
        .overlay(alignment: .topLeading) { cameraPicker.padding(12) }
        .overlay(alignment: .topTrailing) { separationToggle.padding(12) }
        .overlay(alignment: .top) { debugHUD.padding(.top, 64) }
        .overlay(alignment: .center) {
            if showSeparation { SeparationExplorer() }
        }
        .overlay(alignment: .bottom) { drawer }
        .overlay(alignment: .bottomTrailing) {
            captureControls.padding(.trailing, 16).padding(.bottom, controlsBottomPad)
        }
        .overlay(alignment: .bottomLeading) {
            ocrCheckbox.padding(.leading, 16).padding(.bottom, controlsBottomPad)
        }
        // Always-visible perf stamp: pinned to the screen's bottom-left
        // corner, above every other layer (drawer included), so any
        // screenshot or recording captures the perf state. Minimizable to
        // a sparkline by tapping — never removable.
        .overlay(alignment: .bottomLeading) {
            FPSMonitor(camera: camera)
                .padding(.leading, 4)
                .padding(.bottom, 4)
        }
        .sheet(isPresented: $showGallery) {
            GalleryView(camera: camera)
        }
        .onAppear {
            camera.setThresholds(l: lThreshold, a: aThreshold, b: bThreshold)
            camera.loadStills()
            camera.loadCaptures()
            camera.start()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { camera.ensureRunning() }
        }
        .onChange(of: lThreshold) { pushThresholds() }
        .onChange(of: aThreshold) { pushThresholds() }
        .onChange(of: bThreshold) { pushThresholds() }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 360)
        #endif
    }

    private func pushThresholds() {
        camera.setThresholds(l: lThreshold, a: aThreshold, b: bThreshold)
    }

    private var currentCameraName: String {
        camera.devices.first { $0.uniqueID == camera.selectedDeviceID }?.localizedName
            ?? "Camera"
    }

    private var controlsBottomPad: CGFloat { drawerOpen ? 296 : 64 }

    // Circular "take picture" button (bottom right) + gallery access.
    private var captureControls: some View {
        VStack(spacing: 12) {
            Button {
                showGallery = true
            } label: {
                Image(systemName: "photo.stack")
                    .font(.body)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Gallery")

            Button {
                clickFeedback()
                camera.capturePhoto(ocr: ocrEnabled)
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(
                        captureFlash ? Color(red: 1, green: 0.1, blue: 0.15) : .white.opacity(0.9),
                        lineWidth: 2.5))
                    .shadow(color: captureFlash ? .red : .clear, radius: 10)
                    .shadow(color: captureFlash ? .red.opacity(0.6) : .clear, radius: 22)
            }
            .buttonStyle(.plain)
            .help("Take picture")
        }
    }

    // Shutter "click": haptic tap + a 0.1s red neon glow on the button.
    private func clickFeedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #else
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
        withAnimation(.easeIn(duration: 0.04)) { captureFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.12)) { captureFlash = false }
        }
    }

    // Checkbox (bottom left): OCR the capture and save a positioned,
    // color/size-preserving HTML rendition alongside the images.
    private var ocrCheckbox: some View {
        Button {
            ocrEnabled.toggle()
        } label: {
            Label("OCR", systemImage: ocrEnabled ? "checkmark.square.fill" : "square")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Recognize text on capture (on-device)")
    }

    #if os(iOS)
    private func sceneProbe(at date: Date) -> String {
        let states = UIApplication.shared.connectedScenes.map { scene -> String in
            switch scene.activationState {
            case .foregroundActive: return "fgA"
            case .foregroundInactive: return "fgI"
            case .background: return "bg"
            case .unattached: return "un"
            @unknown default: return "?"
            }
        }
        return "screens: \(UIScreen.screens.count) · scenes: [\(states.joined(separator: ","))]"
            + " · heat: \(Self.thermalName)"
    }
    #endif

    static var thermalName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "?"
        }
    }

    // Debug HUD over the camera view. The ticking clock is a main-thread
    // heartbeat: if it freezes, the main thread is blocked; if it ticks but
    // touches do nothing, the problem is touch routing.
    private var debugHUD: some View {
        VStack(alignment: .leading, spacing: 2) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text("♥︎ \(context.date.formatted(date: .omitted, time: .standard))"
                         + " · \(buildTag) · frames: \(camera.frameCount)")
                    #if os(iOS)
                    Text(sceneProbe(at: context.date))
                    #endif
                }
            }
            if !hudCollapsed {
                ForEach(Array(camera.debugLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.yellow)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            withAnimation(.spring(duration: 0.25)) { hudCollapsed.toggle() }
        }
    }

    private var separationToggle: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { showSeparation.toggle() }
        } label: {
            Image(systemName: "circle.hexagongrid.fill")
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        .white.opacity(showSeparation ? 0.8 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help("Explore color separation")
    }

    private var cameraPicker: some View {
        Menu {
            ForEach(camera.devices, id: \.uniqueID) { device in
                Button {
                    camera.select(deviceID: device.uniqueID)
                } label: {
                    if device.uniqueID == camera.selectedDeviceID {
                        Label(device.localizedName, systemImage: "checkmark")
                    } else {
                        Text(device.localizedName)
                    }
                }
            }
            if !camera.stillNames.isEmpty {
                Section("Images") {
                    ForEach(camera.stillNames, id: \.self) { name in
                        Button {
                            camera.select(still: name)
                        } label: {
                            if name == camera.selectedStill {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(camera.selectedStill ?? currentCameraName,
                  systemImage: camera.selectedStill == nil ? "video.fill" : "photo.fill")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .fixedSize()
    }

    private var drawer: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.spring(duration: 0.3)) { drawerOpen.toggle() }
            } label: {
                Image(systemName: drawerOpen ? "chevron.down" : "chevron.up")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if drawerOpen {
                HStack(alignment: .top, spacing: 24) {
                    VerticalSlider(
                        value: $lThreshold, label: "L",
                        gradient: Gradient(colors: [.black, .white]))
                    VerticalSlider(
                        value: $aThreshold, label: "a",
                        gradient: Gradient(colors: [
                            Color(red: 0.0, green: 0.65, blue: 0.30),
                            Color(red: 0.95, green: 0.15, blue: 0.20),
                        ]))
                    VerticalSlider(
                        value: $bThreshold, label: "b",
                        gradient: Gradient(colors: [
                            Color(red: 0.15, green: 0.35, blue: 0.95),
                            Color(red: 0.95, green: 0.85, blue: 0.10),
                        ]))
                }
                .frame(height: 200)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Export formats

enum Exporter {
    struct Line {
        let text: String
        let leftPct: Double, topPct: Double, fontPx: Double
        let rotation: Int
        let r: Int, g: Int, b: Int
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func convert(_ src: URL, type: CFString, ext: String) -> URL? {
        guard let image = loadImage(src) else { return nil }
        let out = src.deletingPathExtension().appendingPathExtension(ext)
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary
        CGImageDestinationAddImage(dest, image, options)
        return CGImageDestinationFinalize(dest) ? out : nil
    }

    static func pdf(_ src: URL) -> URL? {
        guard let image = loadImage(src) else { return nil }
        var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let out = src.deletingPathExtension().appendingPathExtension("pdf")
        guard let ctx = CGContext(out as CFURL, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.draw(image, in: mediaBox)
        ctx.endPDFPage()
        ctx.closePDF()
        return out
    }

    // Parse the OCR lines back out of our own text.html format.
    static func parseLines(in folder: URL) -> [Line] {
        guard let html = try? String(
            contentsOf: folder.appendingPathComponent("text.html"), encoding: .utf8)
        else { return [] }
        let pattern = #"left:([\d.]+)%;top:([\d.]+)%;font-size:(\d+)px;line-height:1;"#
            + #"white-space:nowrap;color:rgb\((\d+),(\d+),(\d+)\);"#
            + #"(?:transform:rotate\((-?\d+)deg\);transform-origin:left top;)?">(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            func group(_ i: Int) -> String {
                guard let r = Range(match.range(at: i), in: html) else { return "" }
                return String(html[r])
            }
            return Line(
                text: group(8),
                leftPct: Double(group(1)) ?? 0, topPct: Double(group(2)) ?? 0,
                fontPx: Double(group(3)) ?? 12,
                rotation: Int(group(7)) ?? 0,
                r: Int(group(4)) ?? 0, g: Int(group(5)) ?? 0, b: Int(group(6)) ?? 0)
        }
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func csv(folder: URL) -> URL? {
        let lines = parseLines(in: folder)
        var out = "text,left_pct,top_pct,font_px,rotation_deg,r,g,b\n"
        for line in lines {
            let quoted = "\"" + unescape(line.text).replacingOccurrences(of: "\"", with: "\"\"") + "\""
            out += "\(quoted),\(line.leftPct),\(line.topPct),\(Int(line.fontPx)),"
                + "\(line.rotation),\(line.r),\(line.g),\(line.b)\n"
        }
        let url = folder.appendingPathComponent("text.csv")
        return (try? out.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    // SVG: the image embedded as base64, with OCR lines as real <text>
    // elements (selectable vectors), rotated where the source text was.
    static func svg(_ src: URL, folder: URL) -> URL? {
        guard let image = loadImage(src), let data = try? Data(contentsOf: src) else { return nil }
        let width = Double(image.width), height = Double(image.height)
        var texts = ""
        for line in parseLines(in: folder) {
            let x = line.leftPct / 100 * width
            let top = line.topPct / 100 * height
            let transform = line.rotation == 0
                ? "" : " transform=\"rotate(\(line.rotation) \(x) \(top))\""
            texts += "<text x=\"\(x)\" y=\"\(top + line.fontPx * 0.8)\" "
                + "font-size=\"\(Int(line.fontPx))\" font-family=\"sans-serif\" "
                + "fill=\"rgb(\(line.r),\(line.g),\(line.b))\"\(transform)>\(line.text)</text>\n"
        }
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
        width="\(Int(width))" height="\(Int(height))" viewBox="0 0 \(Int(width)) \(Int(height))">
        <image href="data:image/jpeg;base64,\(data.base64EncodedString())" \
        width="\(Int(width))" height="\(Int(height))"/>
        \(texts)</svg>
        """
        let url = src.deletingPathExtension().appendingPathExtension("svg")
        return (try? svg.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}

// MARK: - Gold orbit tap feedback (Metal shader in Shaders.metal)

struct GoldOrbitOverlay: View {
    let start: Date

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            if elapsed < 0.9 {
                Rectangle()
                    .fill(Color.white.opacity(0.02))
                    .visualEffect { content, proxy in
                        content.colorEffect(ShaderLibrary.goldOrbit(
                            .float2(proxy.size),
                            .float(Float(elapsed))))
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Share sheet

struct ShareBundle: Identifiable {
    let id = UUID()
    let items: [URL]
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Gallery

private func loadThumbnail(_ url: URL, maxDim: CGFloat = 700) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDim,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

struct GalleryView: View {
    @ObservedObject var camera: CameraManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("photosBannerDismissed") private var bannerDismissed = false
    @AppStorage("galleryBlurBackground") private var blurBackground = true
    @State private var photosStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    @State private var exportTarget: URL?
    @State private var exportFolder: URL?
    @State private var showExportDialog = false
    @State private var toast: String?
    @State private var detailCapture: CameraManager.Capture?
    @State private var goldTap: (id: String, start: Date)?
    @State private var tapCounts: [String: Int] = [:]
    @State private var shareBundle: ShareBundle?

    private var showBanner: Bool {
        !bannerDismissed && photosStatus != .authorized && photosStatus != .limited
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showBanner { permissionBanner }
                List(camera.captures) { capture in
                    row(capture)
                        .listRowBackground(
                            Rectangle().fill(.ultraThinMaterial).opacity(0.75))
                }
                .scrollContentBackground(.hidden)
            }
            .background { backdropView }
            .navigationTitle("Gallery")
            .navigationDestination(item: $detailCapture) { capture in
                CaptureDetailView(capture: capture)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle("Blurred live background", isOn: $blurBackground)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .overlay {
                if camera.captures.isEmpty {
                    Text("No captures yet — tap the camera button.")
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.callout)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.75), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 16)
                }
            }
        }
        // Same perf stamp as the main view — the sheet would otherwise
        // cover it, and gallery perf is exactly what's under investigation.
        .overlay(alignment: .bottomLeading) {
            FPSMonitor(camera: camera)
                .padding(.leading, 4)
                .padding(.bottom, 4)
        }
        .onAppear {
            photosStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        }
        .confirmationDialog(
            "Save / export as…", isPresented: $showExportDialog, titleVisibility: .visible
        ) { exportButtons }
        #if os(iOS)
        .sheet(item: $shareBundle) { bundle in ShareSheet(items: bundle.items) }
        #endif
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
        #endif
    }

    // MARK: rows + gestures

    // The whole row is one "chip" with a manual tap counter — SwiftUI's
    // own multi-tap disambiguation kept losing races inside List, so each
    // tap bumps a count and arms a 0.2s timer; whatever count survives the
    // window dispatches: 1 = expand, 2 = export menu, 3 = share.
    private func row(_ capture: CameraManager.Capture) -> some View {
        HStack(spacing: 8) {
            thumb(capture.original)
            thumb(capture.lab)
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.id).font(.caption.monospaced())
                Text("1×: open · 2×: export · 3×: share")
                    .font(.caption2).foregroundStyle(.secondary)
                if capture.html != nil {
                    Label("text.html", systemImage: "doc.richtext")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .overlay {
            if let gold = goldTap, gold.id == capture.id {
                GoldOrbitOverlay(start: gold.start)
            }
        }
        .highPriorityGesture(TapGesture().onEnded { chipTapped(capture) })
    }

    private func chipTapped(_ capture: CameraManager.Capture) {
        goldTap = (capture.id, Date())
        let count = (tapCounts[capture.id] ?? 0) + 1
        tapCounts[capture.id] = count
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard tapCounts[capture.id] == count else { return } // superseded
            tapCounts[capture.id] = 0
            switch count {
            case 1:
                detailCapture = capture
            case 2:
                exportTarget = capture.original
                exportFolder = capture.original.deletingLastPathComponent()
                showExportDialog = true
            default:
                shareCapture(capture)
            }
        }
    }

    // Share sheet is the kinder path for 3×tap: "Save to Files" lives
    // inside it, alongside AirDrop/Messages — user picks, gets confirmation.
    private func shareCapture(_ capture: CameraManager.Capture) {
        var items: [URL] = []
        if let html = capture.html { items.append(html) }
        if items.isEmpty { items = [capture.original, capture.lab] }
        #if os(iOS)
        shareBundle = ShareBundle(items: items)
        #else
        NSWorkspace.shared.activateFileViewerSelecting(items)
        #endif
    }

    private func thumb(_ url: URL) -> some View {
        Group {
            if let cgImage = loadThumbnail(url, maxDim: 160) {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: blurred live backdrop

    @ViewBuilder private var backdropView: some View {
        if blurBackground {
            MetalBackdropView(camera: camera)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
        }
    }

    // MARK: Photos permission banner

    private var permissionBanner: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color(red: 1.0, green: 0.93, blue: 0.2)) // highlighter yellow
                .containerRelativeFrame(.horizontal) { length, _ in length * 0.05 }
            VStack(alignment: .leading, spacing: 8) {
                Text("Save captures to Photos?").font(.headline)
                Text("“Allow Saving” is the minimum needed to add captures to your "
                     + "camera roll. Grant either and this banner disappears forever.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Allow Saving") { requestPhotos(.addOnly) }
                        .buttonStyle(.borderedProminent)
                    Button("Full Access") { requestPhotos(.readWrite) }
                        .buttonStyle(.bordered)
                }
            }
            .padding(10)
            Spacer(minLength: 24)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottomTrailing) {
            Button {
                bannerDismissed = true // permanent: stored in UserDefaults
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss forever")
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top], 10)
    }

    private func requestPhotos(_ level: PHAccessLevel) {
        PHPhotoLibrary.requestAuthorization(for: level) { _ in
            DispatchQueue.main.async {
                photosStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            }
        }
    }

    // MARK: saving + exporting

    private func saveToCameraRoll(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async { photosStatus = status }
            guard status == .authorized || status == .limited else {
                showToast("Photos permission needed")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
            }) { ok, error in
                showToast(ok ? "Saved to camera roll"
                             : "Save failed: \(error?.localizedDescription ?? "?")")
            }
        }
    }

    @ViewBuilder private var exportButtons: some View {
        Button("HEIC → Photos") { convertAndSave("public.heic" as CFString, "heic") }
        Button("PNG → Photos") { convertAndSave("public.png" as CFString, "png") }
        Button("JPEG → Photos") { convertAndSave("public.jpeg" as CFString, "jpeg") }
        Button("SVG file") {
            guard let target = exportTarget, let folder = exportFolder else { return }
            showToast(Exporter.svg(target, folder: folder).map { "Wrote \($0.lastPathComponent)" }
                      ?? "SVG export failed")
        }
        Button("PDF file") {
            guard let target = exportTarget else { return }
            showToast(Exporter.pdf(target).map { "Wrote \($0.lastPathComponent)" }
                      ?? "PDF export failed")
        }
        Button("CSV (OCR lines)") {
            guard let folder = exportFolder else { return }
            showToast(Exporter.csv(folder: folder).map { "Wrote \($0.lastPathComponent)" }
                      ?? "CSV export failed")
        }
        Button("Cancel", role: .cancel) {}
    }

    private func convertAndSave(_ type: CFString, _ ext: String) {
        guard let target = exportTarget else { return }
        guard let converted = Exporter.convert(target, type: type, ext: ext) else {
            showToast("\(ext.uppercased()) conversion failed")
            return
        }
        saveToCameraRoll(converted)
    }

    private func showToast(_ message: String) {
        DispatchQueue.main.async {
            withAnimation { toast = message }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation { toast = nil }
            }
        }
    }
}

struct CaptureDetailView: View {
    let capture: CameraManager.Capture

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                pane("Original", url: capture.original)
                pane("Lab", url: capture.lab)
                if let html = capture.html {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OCR text (positioned HTML)")
                            .font(.caption).foregroundStyle(.secondary)
                        WebView(url: html)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding()
        }
        .navigationTitle(capture.id)
    }

    private func pane(_ title: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if let cgImage = loadThumbnail(url, maxDim: 1200) {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

#if os(iOS)
struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}
#else
struct WebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { WKWebView() }
    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}
#endif

@main
struct SplitCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
