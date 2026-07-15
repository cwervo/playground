import SwiftUI
import Combine

// Simulation of the UW motion-triggered insect-scale camera:
// a tiny camera board rides a beetle; an accelerometer wakes it only when the
// beetle moves; it captures a 160x120 monochrome frame, JPEG-compresses it and
// radios the packets to a more powerful hub across the room, which stores and
// processes the photos. All photos persist on-device (network-last).

struct Obstacle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var r: Double
}

// Room geometry, deliberately nonisolated so the frame renderer and the
// Canvas renderer closure can read it off the main actor.
enum Room {
    static let w = 820.0
    static let h = 430.0
    static let hub = CGPoint(x: 740, y: 215)
    static let obstacles = [
        Obstacle(x: 250, y: 110, r: 34), Obstacle(x: 430, y: 300, r: 46),
        Obstacle(x: 560, y: 120, r: 28), Obstacle(x: 180, y: 330, r: 30),
        Obstacle(x: 640, y: 330, r: 22),
    ]

    static func lineBlocked(from a: CGPoint, to b: CGPoint) -> Bool {
        for o in obstacles {
            let l2 = pow(b.x - a.x, 2) + pow(b.y - a.y, 2)
            let t = max(0, min(1, ((o.x - a.x) * (b.x - a.x) + (o.y - a.y) * (b.y - a.y)) / l2))
            let px = a.x + t * (b.x - a.x), py = a.y + t * (b.y - a.y)
            if hypot(px - o.x, py - o.y) < o.r { return true }
        }
        return false
    }
}

enum LinkType: String, CaseIterable, Identifiable {
    case ble = "BLE"
    case wifi = "WiFi"
    case ir = "IR"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ble: return "Bluetooth LE"
        case .wifi: return "WiFi"
        case .ir: return "IR (line-of-sight)"
        }
    }
    var mtu: Int          { switch self { case .ble: return 244;  case .wifi: return 1400; case .ir: return 64 } }
    var pktPerTick: Int   { switch self { case .ble: return 3;    case .wifi: return 10;   case .ir: return 2 } }
    var energyPerPkt: Double { switch self { case .ble: return 0.20; case .wifi: return 0.55; case .ir: return 0.06 } }
    var baseLoss: Double  { switch self { case .ble: return 0.04; case .wifi: return 0.02; case .ir: return 0.10 } }
    var range: Double     { switch self { case .ble: return 520;  case .wifi: return 900;  case .ir: return 420 } }
    var needsLoS: Bool    { self == .ir }
}

enum NodeState: String {
    case sleep = "SLEEP", wake = "WAKE", tx = "TX"
}

struct LogLine: Identifiable {
    enum Kind { case cam, link, hub, error }
    let id = UUID()
    let t: Double
    let kind: Kind
    let text: String
}

struct Beetle {
    var x = 120.0, y = 220.0
    var heading = 0.0
    var speed = 0.0
    var prevSpeed = 0.0
    var accel = 0.0
    var wiggle = 0.0
    var pause = 1.2
    var target: CGPoint? = nil
}

struct Packet: Identifiable {
    let id = UUID()
    var progress: Double
    let ok: Bool
    let wobble: Double
}

struct Transfer {
    var jpeg: Data
    var total: Int
    var sent = 0
    var retries = 0
    var frame: Int
    var quality: Double
}

@MainActor
final class SimModel: ObservableObject {
    @Published var beetle = Beetle()
    @Published var charge = 38.0
    @Published var state = NodeState.sleep
    @Published var stateNote = ""
    @Published var link = LinkType.ble
    @Published var quality = 0.45
    @Published var wakeThreshold = 0.18
    @Published var harvestRate = 0.55
    @Published var extraLoss = 0.08
    @Published var paused = false
    @Published var particles: [Packet] = []
    @Published var transfer: Transfer? = nil
    @Published var viewfinder: UIImage? = nil
    @Published var log: [LogLine] = []
    @Published var framesCaptured = 0
    @Published var packetsAcked = 0
    @Published var packetsLost = 0
    @Published var energySpent = 0.0

    let store = PhotoStore()

    private var t = 0.0
    private var cooldown = 0.0
    private var vfTimer = 0.0
    private var timer: Timer? = nil
    private let dt = 1.0 / 30.0
    private let captureCost = 6.0

    init() {
        addLog(.hub, "hub online — \(store.photos.count) photo(s) restored from device storage")
        addLog(.cam, "camera node booted · accelerometer armed · motion-triggered capture")
        viewfinder = FrameRenderer.render(beetle: beetle)
        timer = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit { timer?.invalidate() }

    func addLog(_ kind: LogLine.Kind, _ text: String) {
        log.append(LogLine(t: t, kind: kind, text: text))
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    var hubDistance: Double { hypot(beetle.x - Room.hub.x, beetle.y - Room.hub.y) }

    var linkLoss: Double {
        var loss = link.baseLoss + extraLoss
            + min(0.5, max(0, (hubDistance - link.range * 0.55) / link.range))
        if link.needsLoS && Room.lineBlocked(from: CGPoint(x: beetle.x, y: beetle.y), to: Room.hub) {
            loss = 1
        }
        return min(1, max(0, loss))
    }

    func nudge() {
        beetle.pause = 0
        beetle.speed = 70
        beetle.accel = max(beetle.accel, 0.6)
        beetle.target = CGPoint(x: .random(in: 50...(Room.w - 140)),
                                y: .random(in: 40...(Room.h - 40)))
    }

    func send(to point: CGPoint) {
        beetle.target = point
        beetle.pause = 0
    }

    // MARK: - main loop

    private func tick() {
        guard !paused else { return }
        t += dt
        cooldown = max(0, cooldown - dt)
        tickBeetle()
        tickEnergy()
        if transfer == nil {
            state = beetle.accel >= wakeThreshold ? .wake : .sleep
            tryCapture()
        }
        tickTransfer()
        for i in particles.indices { particles[i].progress += dt * 1.6 }
        particles.removeAll { $0.progress >= 1 }
        vfTimer -= dt
        if vfTimer <= 0 {
            viewfinder = FrameRenderer.render(beetle: beetle)
            vfTimer = transfer != nil ? 0.5 : 0.18
        }
    }

    private func tickBeetle() {
        var b = beetle
        if b.pause > 0 {
            b.pause -= dt
            b.speed *= 0.8
        } else {
            if b.target == nil || hypot(b.x - (b.target?.x ?? 0), b.y - (b.target?.y ?? 0)) < 12 {
                if Double.random(in: 0...1) < 0.35 {
                    b.pause = .random(in: 0.8...3.5)   // death-feigning beetles like to stop
                    b.target = nil
                } else {
                    b.target = CGPoint(x: .random(in: 50...(Room.w - 140)),
                                       y: .random(in: 40...(Room.h - 40)))
                }
            }
            if let tgt = b.target {
                let want = atan2(tgt.y - b.y, tgt.x - b.x)
                var d = want - b.heading
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                b.heading += max(-2.2 * dt, min(2.2 * dt, d))
                b.speed = max(0, min(70, b.speed + .random(in: -30...60) * dt))
            }
        }
        b.wiggle += b.speed * dt * 0.6
        b.x = max(20, min(Room.w - 20, b.x + cos(b.heading) * b.speed * dt))
        b.y = max(20, min(Room.h - 20, b.y + sin(b.heading) * b.speed * dt))
        // crude accelerometer: change in speed + gait wiggle while walking
        let jerk = abs(b.speed - b.prevSpeed) / max(dt, 1e-3) / 900
        let gait = b.speed > 4 ? 0.15 + b.speed / 300 : 0
        b.accel = max(0, min(1, 0.92 * b.accel + 0.08 * (jerk + gait + .random(in: 0...0.02))))
        b.prevSpeed = b.speed
        beetle = b
    }

    private func tickEnergy() {
        // motion harvesting + ambient trickle
        let harvested = (beetle.speed / 70) * harvestRate * 7.5 * dt + 0.35 * dt
        charge = max(0, min(100, charge + harvested))
    }

    private func tryCapture() {
        guard beetle.accel >= wakeThreshold, cooldown <= 0 else { return }
        guard charge >= captureCost + 2 else {
            stateNote = "(motion seen, waiting for charge)"
            return
        }
        charge -= captureCost
        energySpent += captureCost
        let frame = FrameRenderer.render(beetle: beetle)
        guard let jpeg = frame.jpegData(compressionQuality: quality) else { return }
        viewfinder = frame
        framesCaptured += 1
        transfer = Transfer(jpeg: jpeg,
                            total: max(1, Int(ceil(Double(jpeg.count) / Double(link.mtu)))),
                            frame: framesCaptured,
                            quality: quality)
        state = .tx
        stateNote = ""
        cooldown = 2.5
        addLog(.cam, String(format: "motion %.2f g ≥ %.2f g → frame #%d captured (%d B, q=%.2f, %d pkts over %@)",
                            beetle.accel, wakeThreshold, framesCaptured, jpeg.count,
                            quality, transfer!.total, link.displayName))
    }

    private func tickTransfer() {
        guard var tr = transfer else { return }
        let loss = linkLoss
        var budget = link.pktPerTick
        while budget > 0 && tr.sent < tr.total {
            budget -= 1
            if charge < link.energyPerPkt {
                stateNote = "(recharging mid-transfer)"
                transfer = tr
                return
            }
            charge -= link.energyPerPkt
            energySpent += link.energyPerPkt
            let ok = Double.random(in: 0...1) >= loss
            particles.append(Packet(progress: 0, ok: ok, wobble: .random(in: -8...8)))
            if ok { tr.sent += 1; packetsAcked += 1 }
            else { tr.retries += 1; packetsLost += 1 }
            if loss >= 1 { break }
        }
        stateNote = loss >= 1 ? "(IR blocked — no line of sight)" : ""
        if tr.sent >= tr.total {
            let rec = store.add(jpeg: tr.jpeg, frame: tr.frame, pkts: tr.total,
                                retries: tr.retries, link: link.displayName, quality: tr.quality)
            addLog(.link, "frame #\(tr.frame): \(tr.total)/\(tr.total) pkts ACKed (\(tr.retries) retries)")
            addLog(.hub, "stored photo #\(rec.id) (\(rec.bytes) B); edge extraction available in viewer")
            transfer = nil
            state = .sleep
        } else {
            transfer = tr
        }
    }
}
