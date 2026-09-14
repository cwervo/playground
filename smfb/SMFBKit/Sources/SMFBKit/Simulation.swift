import Foundation
import SMFBCore
#if canImport(Combine)
import Combine
#else
// Headless Linux builds: enough of Combine for the class to compile.
public protocol ObservableObject: AnyObject {}
@propertyWrapper public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
#endif

public struct FoodPellet: Sendable, Equatable {
    public var x: Float
    public var y: Float
    /// 1 = fresh, 0 = gone.
    public var amount: Float
}

public struct MouseState: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var heading: Float
    public var speed: Float
    public var gaitPhase: Float
    public var tailPhase: Float
    /// 0..1, ramps up while chewing.
    public var eating: Float
}

/// Everything the renderer needs for one frame. Built on the simulation
/// thread under a lock and handed to the UI by value.
public struct WorldSnapshot: Sendable {
    /// Arena size in world units; width is always 1.
    public var width: Float = 1
    public var height: Float = 1
    public var mouse = MouseState(x: 0.5, y: 0.5, heading: 0, speed: 0, gaitPhase: 0, tailPhase: 0, eating: 0)
    public var food: [FoodPellet] = []
    public var odorLeft: Float = 0
    public var odorRight: Float = 0
    public var descendingLeft: Float = 0
    public var descendingRight: Float = 0
    public var descendingForward: Float = 0
    public var bumpLeft: Float = 0
    public var bumpRight: Float = 0
    public var reward: Float = 0
    public var time: Double = 0
    public var pelletsEaten: Int = 0
    /// Indexed by `BrainRegion.rawValue`.
    public var regionRates: [Float] = Array(repeating: 0, count: BrainRegion.allCases.count)
    public var regionSpikes: [Int] = Array(repeating: 0, count: BrainRegion.allCases.count)
    /// Network-wide spikes per step, newest last (about three seconds).
    public var activityHistory: [Float] = []
    public var neuronCount: Int = 0
    public var synapseCount: Int = 0
    public var kernelName: String = ""
    /// Brain steps per wall-clock second, measured (1000 = real time).
    public var stepsPerSecond: Double = 0
    public var paused = false

    public func rate(of region: BrainRegion) -> Float { regionRates[region.rawValue] }
}

/// Runs the world on its own thread at a fixed tick and publishes snapshots.
/// The views poll `currentSnapshot()` every display frame; nothing about the
/// simulation itself is tied to the display refresh rate.
public final class Simulation: ObservableObject {
    public struct Config: Sendable {
        public var scale: Int
        public var seed: UInt64
        /// Simulation thread tick rate.
        public var tickHz: Double
        /// Sim seconds per wall second.
        public var timeScale: Double

        public init(scale: Int, seed: UInt64 = 1, tickHz: Double = 120, timeScale: Double = 1) {
            self.scale = scale
            self.seed = seed
            self.tickHz = tickHz
            self.timeScale = timeScale
        }

        /// A connectome size each device can step in real time with room to spare.
        public static var forCurrentDevice: Config {
            #if os(watchOS)
            return Config(scale: 2, tickHz: 60)
            #elseif os(tvOS)
            return Config(scale: 8)
            #elseif os(iOS)
            return Config(scale: 8)
            #else
            return Config(scale: 16)
            #endif
        }
    }

    public private(set) var config: Config
    public private(set) var brain: FlyBrain

    private let lock = NSLock()
    private var world = smfb_world()
    private var snapshot = WorldSnapshot()
    private var history: [Float] = Array(repeating: 0, count: 180)
    private var pendingFood: [(Float, Float)] = []
    private var pendingAspect: Float?
    private var pendingClear = false
    private var pendingReset: UInt64?
    private var pausedFlag = false
    private var timeScale: Double
    private var running = false
    private var thread: Thread?
    private var stepsAtLastRateSample: UInt64 = 0
    private var rateSampleTime: TimeInterval = 0
    private var measuredStepsPerSecond: Double = 0

    @Published public private(set) var isRunning = false
    @Published public private(set) var isPaused = false

    public init(config: Config) {
        var cfg = config
        var candidate = FlyBrain(scale: cfg.scale, seed: cfg.seed)
        while candidate == nil && cfg.scale > 1 {       // out of memory: shrink
            cfg.scale /= 2
            candidate = FlyBrain(scale: cfg.scale, seed: cfg.seed)
        }
        guard let built = candidate else { fatalError("SMFB: could not allocate even a scale-1 brain") }
        self.config = cfg
        self.brain = built
        self.timeScale = cfg.timeScale
        smfb_world_init(&world, 1, 1)
        snapshot = Simulation.makeSnapshot(world: world, brain: built, history: history,
                                           stepsPerSecond: 0, paused: false)
    }

    deinit {
        lock.lock(); running = false; lock.unlock()
    }

    // MARK: - Control

    public func start() {
        lock.lock()
        if running { lock.unlock(); return }
        running = true
        lock.unlock()
        let t = Thread { [weak self] in self?.loop() }
        t.name = "smfb.simulation"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        DispatchQueue.main.async { self.isRunning = true }
    }

    public func stop() {
        lock.lock()
        running = false
        lock.unlock()
        thread = nil
        if Thread.isMainThread { isRunning = false } else { DispatchQueue.main.async { self.isRunning = false } }
    }

    public func setPaused(_ paused: Bool) {
        lock.lock(); pausedFlag = paused; lock.unlock()
        if Thread.isMainThread { isPaused = paused } else { DispatchQueue.main.async { self.isPaused = paused } }
    }

    public func togglePaused() { setPaused(!isPaused) }

    /// Sim seconds per wall second (0.1 ... 4). Clamped.
    public var speed: Double {
        get { lock.lock(); defer { lock.unlock() }; return timeScale }
        set { lock.lock(); timeScale = min(4, max(0.1, newValue)); lock.unlock() }
    }

    /// Drop a pellet. `point` is in view coordinates of a view with `size`.
    public func dropFood(at point: CGPoint, in size: CGSize) {
        guard size.width > 0 else { return }
        let x = Float(point.x / size.width)
        let y = Float(point.y / size.width)      // world units: width == 1
        dropFood(x: x, y: y)
    }

    /// Drop a pellet at world coordinates (x in 0...1, y in 0...aspect).
    public func dropFood(x: Float, y: Float) {
        lock.lock(); pendingFood.append((x, y)); lock.unlock()
    }

    public func clearFood() { lock.lock(); pendingClear = true; lock.unlock() }

    /// Fresh brain (new seed) and an empty arena.
    public func reset(seed: UInt64? = nil) {
        lock.lock(); pendingReset = seed ?? (config.seed &+ 1); lock.unlock()
    }

    /// Arena height / width. Called by the view when its size changes.
    public func setAspect(_ aspect: Float) {
        guard aspect.isFinite, aspect > 0 else { return }
        lock.lock(); pendingAspect = aspect; lock.unlock()
    }

    public func currentSnapshot() -> WorldSnapshot {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    /// Step synchronously (tests, previews). Only meaningful while stopped.
    public func advance(seconds: Double) {
        lock.lock(); defer { lock.unlock() }
        applyPending()
        var remaining = seconds
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 60.0)
            smfb_world_step(&world, brain.ptr, Float(dt))
            remaining -= dt
        }
        pushHistory()
        snapshot = Simulation.makeSnapshot(world: world, brain: brain, history: history,
                                           stepsPerSecond: 0, paused: pausedFlag)
    }

    // MARK: - Thread

    private func loop() {
        var last = Date().timeIntervalSinceReferenceDate
        rateSampleTime = last
        stepsAtLastRateSample = brain.stepCount
        let tick = 1.0 / config.tickHz
        while true {
            let now = Date().timeIntervalSinceReferenceDate
            let dt = now - last
            last = now
            lock.lock()
            if !running { lock.unlock(); return }
            applyPending()
            if !pausedFlag {
                smfb_world_step(&world, brain.ptr, Float(dt * timeScale))
            }
            if now - rateSampleTime >= 1 {
                let steps = brain.stepCount - stepsAtLastRateSample
                measuredStepsPerSecond = Double(steps) / (now - rateSampleTime)
                stepsAtLastRateSample = brain.stepCount
                rateSampleTime = now
            }
            pushHistory()
            snapshot = Simulation.makeSnapshot(world: world, brain: brain, history: history,
                                               stepsPerSecond: measuredStepsPerSecond, paused: pausedFlag)
            lock.unlock()
            let spent = Date().timeIntervalSinceReferenceDate - now
            if tick - spent > 0 { Thread.sleep(forTimeInterval: tick - spent) }
        }
    }

    /// Must hold `lock`.
    private func applyPending() {
        if let seed = pendingReset {
            pendingReset = nil
            if let fresh = FlyBrain(scale: config.scale, seed: seed) {
                brain = fresh
                config.seed = seed
            }
            let h = world.height
            smfb_world_init(&world, 1, h)
            history = Array(repeating: 0, count: history.count)
            stepsAtLastRateSample = 0
        }
        if pendingClear {
            pendingClear = false
            world.n_food = 0
            world.reward = 0
        }
        if let aspect = pendingAspect {
            pendingAspect = nil
            world.height = aspect
            world.mouse.y = min(world.mouse.y, aspect - 0.02)
            let count = Int(world.n_food)
            withUnsafeMutablePointer(to: &world.food) { tuple in
                tuple.withMemoryRebound(to: smfb_food.self, capacity: Int(SMFB_MAX_FOOD)) { food in
                    for i in 0..<count { food[i].y = min(food[i].y, aspect - 0.03) }
                }
            }
        }
        for (x, y) in pendingFood { smfb_world_drop_food(&world, x, y) }
        pendingFood.removeAll(keepingCapacity: true)
    }

    /// Must hold `lock`.
    private func pushHistory() {
        history.removeFirst()
        history.append(Float(brain.ptr.pointee.n_spikes))
    }

    private static func makeSnapshot(world: smfb_world, brain: FlyBrain, history: [Float],
                                     stepsPerSecond: Double, paused: Bool) -> WorldSnapshot {
        var s = WorldSnapshot()
        s.width = world.width
        s.height = world.height
        let m = world.mouse
        s.mouse = MouseState(x: m.x, y: m.y, heading: m.heading, speed: m.speed,
                             gaitPhase: m.gait_phase, tailPhase: m.tail_phase, eating: m.eating)
        var w = world
        s.food = withUnsafePointer(to: &w.food) { tuple in
            tuple.withMemoryRebound(to: smfb_food.self, capacity: Int(SMFB_MAX_FOOD)) { food in
                (0..<Int(world.n_food)).map { FoodPellet(x: food[$0].x, y: food[$0].y, amount: food[$0].amount) }
            }
        }
        s.odorLeft = world.odor_l
        s.odorRight = world.odor_r
        s.descendingLeft = world.rate_dn_l
        s.descendingRight = world.rate_dn_r
        s.descendingForward = world.rate_dn_fwd
        s.bumpLeft = world.bump_l
        s.bumpRight = world.bump_r
        s.reward = world.reward
        s.time = world.time_s
        s.pelletsEaten = Int(world.pellets_eaten)
        for r in BrainRegion.allCases {
            s.regionRates[r.rawValue] = brain.rate(of: r)
            s.regionSpikes[r.rawValue] = brain.spikes(in: r)
        }
        s.activityHistory = history
        s.neuronCount = brain.neuronCount
        s.synapseCount = brain.synapseCount
        s.kernelName = brain.kernelName
        s.stepsPerSecond = stepsPerSecond
        s.paused = paused
        return s
    }
}
