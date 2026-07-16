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

// MARK: - Camera capture + Lab processing

let buildTag = "v11-ocr2"

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                           AVCapturePhotoCaptureDelegate {
    @Published var frame: CGImage?
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String?
    @Published var denied = false
    @Published var frameCount = 0
    @Published var debugLines: [String] = []
    @Published var stillNames: [String] = []
    @Published var selectedStill: String?
    @Published var captures: [Capture] = []

    struct Capture: Identifiable {
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
    private let ciContext = CIContext()
    // Only read/written on `queue` (the capture callback queue).
    private var thresholds: (l: Double, a: Double, b: Double) = (0.5, 0.5, 0.5)
    private var stillImage: CIImage?
    private var activeStill = false
    private var pendingOCR: Bool? // queue-confined; non-nil = capture requested
    private var photoPendingOCR: Bool? // queue-confined
    private let photoOutput = AVCapturePhotoOutput()

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
        let processed = process(stillImage)
        guard let cgImage = ciContext.createCGImage(processed, from: processed.extent) else {
            return
        }
        DispatchQueue.main.async {
            self.frame = cgImage
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
        let processed = process(CIImage(cvPixelBuffer: buffer))
        guard let cgImage = ciContext.createCGImage(processed, from: processed.extent) else {
            if !loggedFirstFrame { dbg("createCGImage failed") }
            return
        }
        if !loggedFirstFrame {
            loggedFirstFrame = true
            dbg("first frame: \(cgImage.width)x\(cgImage.height)")
        }
        if let ocr = pendingOCR {
            pendingOCR = nil
            saveCapture(originalCI: CIImage(cvPixelBuffer: buffer), processedCG: cgImage, ocr: ocr)
        }
        DispatchQueue.main.async {
            self.frame = cgImage
            self.frameCount += 1
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let frame = camera.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if camera.denied {
                Text("Camera access is off. Enable it in Settings ▸ Privacy & Security ▸ Camera, then relaunch.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(40)
            } else {
                ProgressView().tint(.white)
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
        .sheet(isPresented: $showGallery) {
            GalleryView(captures: camera.captures)
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
                camera.capturePhoto(ocr: ocrEnabled)
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            .help("Take picture")
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
    }
    #endif

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
    let captures: [CameraManager.Capture]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(captures) { capture in
                NavigationLink {
                    CaptureDetailView(capture: capture)
                } label: {
                    HStack(spacing: 8) {
                        thumb(capture.original)
                        thumb(capture.lab)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(capture.id).font(.caption.monospaced())
                            if capture.html != nil {
                                Label("text.html", systemImage: "doc.richtext")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if captures.isEmpty {
                    Text("No captures yet — tap the camera button.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 420)
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
