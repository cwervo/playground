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

// MARK: - Camera capture + Lab processing

let buildTag = "v9"

final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var frame: CGImage?
    @Published var devices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String?
    @Published var denied = false
    @Published var frameCount = 0
    @Published var debugLines: [String] = []
    @Published var stillNames: [String] = []
    @Published var selectedStill: String?

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
        .onAppear {
            camera.setThresholds(l: lThreshold, a: aThreshold, b: bThreshold)
            camera.loadStills()
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

@main
struct SplitCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
