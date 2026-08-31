import Foundation
import CoreVideo
import simd

struct CalibrationData: Codable {
    var map: PlanarMap
    var skin: SkinModel
    var displayID: UInt32
    var maskWidth: Int
    var maskHeight: Int
    var createdAt: Date
}

enum CalibrationStore {
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("Sistine", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("calibration.json")
    }

    static func load() -> CalibrationData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CalibrationData.self, from: data)
    }

    static func save(_ calibration: CalibrationData) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(calibration).write(to: url, options: .atomic)
    }
}

/// Drives the calibration pass: probe orientation, walk a grid of targets,
/// collect a skin sample at each, then solve.
///
/// A 5x4 grid rather than Sistine's four corners. Four points determine the
/// homography exactly, which sounds sufficient and is not: with four points
/// there is no redundancy, so a single sloppy tap silently bends the entire map
/// and there is no residual to measure lens distortion with. Twenty points cost
/// the user fifteen seconds and buy RANSAC something to vote with.
final class Calibrator {
    enum State: Equatable {
        case probingOrientation
        case collecting(targetIndex: Int)
        case solved
        case failed(String)
    }

    private(set) var state: State = .probingOrientation
    private(set) var targets: [SIMD2<Double>] = []
    private(set) var flipX = false
    private(set) var flipY = false

    private let config: Config
    private let screenSize: SIMD2<Double>
    private let displayID: UInt32
    private let maskSize: SIMD2<Int>

    private var cameraSamples: [SIMD2<Double>] = []
    private var screenSamples: [SIMD2<Double>] = []
    private var skinSamples: [SIMD2<Float>] = []

    private var dwellFrames = 0
    private var dwellAccumulator = SIMD2<Double>(0, 0)
    private var awaitingLift = false

    // Orientation probe bookkeeping
    private var probeFrames = 0
    private var pairedWithFlip = 0
    private var pairedWithoutFlip = 0
    private static let probeFramesPerOrientation = 45

    init(config: Config, screenSize: SIMD2<Double>, displayID: UInt32, maskSize: SIMD2<Int>) {
        self.config = config
        self.screenSize = screenSize
        self.displayID = displayID
        self.maskSize = maskSize
        self.targets = Calibrator.makeTargets(config: config, screenSize: screenSize)
    }

    var currentTarget: SIMD2<Double>? {
        if case .collecting(let i) = state, i < targets.count { return targets[i] }
        return nil
    }

    var progress: (done: Int, total: Int) {
        if case .collecting(let i) = state { return (i, targets.count) }
        return (targets.count, targets.count)
    }

    /// Inset from the screen edge: a target in the literal corner sits where the
    /// camera's view of the glass is most oblique and least reliable, and where
    /// the user's finger is half off the bezel.
    private static func makeTargets(config: Config, screenSize: SIMD2<Double>) -> [SIMD2<Double>] {
        let inset = SIMD2(screenSize.x * 0.07, screenSize.y * 0.09)
        let span = screenSize - inset * 2
        var out: [SIMD2<Double>] = []
        for row in 0..<config.calibrationRows {
            for col in 0..<config.calibrationColumns {
                let u = config.calibrationColumns == 1 ? 0.5
                      : Double(col) / Double(config.calibrationColumns - 1)
                let v = config.calibrationRows == 1 ? 0.5
                      : Double(row) / Double(config.calibrationRows - 1)
                out.append(SIMD2(inset.x + span.x * u, inset.y + span.y * v))
            }
        }
        return out
    }

    /// Feed one frame's detection result. Returns true when the pass is over.
    @discardableResult
    func consume(contact: GlassContact?,
                 phase: TouchPhase,
                 pixelBuffer: CVPixelBuffer?) -> Bool
    {
        switch state {
        case .probingOrientation:
            probe(contact: contact)
            return false

        case .collecting(let index):
            collect(index: index, contact: contact, phase: phase, pixelBuffer: pixelBuffer)
            return false

        case .solved, .failed:
            return true
        }
    }

    /// Which way up the mirror leaves the image depends on how the user taped it
    /// on, so measure it instead of asking. The correct orientation is the one
    /// that yields finger/reflection *pairs*; the wrong one puts the reflection
    /// above the finger, where the pairing rule rejects it.
    private func probe(contact: GlassContact?) {
        let paired = (contact != nil && (contact!.gap > 0 || contact!.confidence > 0.5))
        if flipY {
            if paired { pairedWithFlip += 1 }
        } else {
            if paired { pairedWithoutFlip += 1 }
        }
        probeFrames += 1

        if probeFrames == Calibrator.probeFramesPerOrientation {
            flipY = true
        } else if probeFrames >= Calibrator.probeFramesPerOrientation * 2 {
            flipY = pairedWithFlip > pairedWithoutFlip
            state = .collecting(targetIndex: 0)
        }
    }

    private func collect(index: Int,
                         contact: GlassContact?,
                         phase: TouchPhase,
                         pixelBuffer: CVPixelBuffer?)
    {
        // Require a clean lift between targets, so one long press cannot be
        // consumed as two taps.
        if awaitingLift {
            if phase != .touching { awaitingLift = false }
            return
        }

        guard let contact, phase == .touching else {
            dwellFrames = 0
            dwellAccumulator = .zero
            return
        }

        dwellFrames += 1
        dwellAccumulator += SIMD2(Double(contact.point.x), Double(contact.point.y))

        if let pixelBuffer {
            // Sample the finger's interior, a little above the glass plane,
            // rather than the contact point itself (which straddles the gap).
            let interior = SIMD2(contact.point.x, contact.point.y - max(contact.widthPx, 8))
            skinSamples.append(contentsOf: ChromaSampler.sample(
                pixelBuffer: pixelBuffer, aroundMaskPoint: interior,
                maskSize: maskSize, flipX: flipX, flipY: flipY))
        }

        let needed = max(1, Int(config.calibrationDwellSeconds * Double(config.targetFPS)))
        guard dwellFrames >= needed else { return }

        cameraSamples.append(dwellAccumulator / Double(dwellFrames))
        screenSamples.append(targets[index])
        dwellFrames = 0
        dwellAccumulator = .zero
        awaitingLift = true

        let next = index + 1
        state = next < targets.count ? .collecting(targetIndex: next) : solve()
    }

    private func solve() -> State {
        guard let map = PlanarMap.build(cameraPoints: cameraSamples,
                                        screenPoints: screenSamples,
                                        screenSize: screenSize,
                                        flipX: flipX,
                                        flipY: flipY)
        else { return .failed("Could not fit a homography — the taps were too collinear or too noisy.") }

        let stats = map.residualStatistics
        if stats.mean > 40 {
            return .failed(String(format:
                "Fit is too loose (mean residual %.1f pt). Re-seat the mirror and try again.",
                stats.mean))
        }
        result = CalibrationData(map: map,
                                 skin: SkinModel.fit(samples: skinSamples) ?? .prior,
                                 displayID: displayID,
                                 maskWidth: maskSize.x,
                                 maskHeight: maskSize.y,
                                 createdAt: Date())
        return .solved
    }

    private(set) var result: CalibrationData?
}
