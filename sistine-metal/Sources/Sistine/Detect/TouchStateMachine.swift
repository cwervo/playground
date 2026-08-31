import Foundation
import simd

enum TouchPhase: Equatable {
    case away          // no finger over the glass
    case hovering
    case touching
}

enum TouchEvent: Equatable {
    case moved(SIMD2<Float>)        // glass-space point, finger not touching
    case down(SIMD2<Float>)
    case dragged(SIMD2<Float>)
    case up(SIMD2<Float>)
    case lost
}

/// Schmitt trigger on the perspective-normalised gap, plus dropout tolerance.
///
/// Two hysteresis bands are what make this usable: a single threshold chatters
/// at the moment of contact because the gap measurement is quantised to whole
/// pixels and the last pixel of approach is also the noisiest. Requiring N
/// consecutive frames on each side turns a 60 Hz stream of noisy booleans into a
/// clean edge at the cost of ~33 ms.
struct TouchStateMachine {
    private(set) var phase: TouchPhase = .away

    private var belowCount = 0
    private var aboveCount = 0
    private var missingCount = 0
    private var lastPoint = SIMD2<Float>(0, 0)

    mutating func reset() {
        phase = .away
        belowCount = 0
        aboveCount = 0
        missingCount = 0
    }

    mutating func update(contact: GlassContact?, config: Config) -> TouchEvent? {
        guard let contact else {
            missingCount += 1
            // A finger that vanishes for a frame or two is almost always a
            // segmentation dropout, not a lift. Releasing a drag on one bad
            // frame is far more annoying than 60 ms of extra latency on a lift.
            if missingCount >= config.dropoutFrames {
                let wasDown = phase == .touching
                phase = .away
                belowCount = 0
                aboveCount = 0
                return wasDown ? .up(lastPoint) : .lost
            }
            return nil
        }

        missingCount = 0
        lastPoint = contact.point
        let ratio = contact.normalizedGap

        if ratio <= config.touchDownRatio {
            belowCount += 1
            aboveCount = 0
        } else if ratio >= config.touchUpRatio {
            aboveCount += 1
            belowCount = 0
        } else {
            // Inside the dead band: hold whatever state we are in.
            belowCount = 0
            aboveCount = 0
        }

        switch phase {
        case .away:
            phase = belowCount >= config.downFrames ? .touching : .hovering
            return phase == .touching ? .down(contact.point) : .moved(contact.point)

        case .hovering:
            if belowCount >= config.downFrames {
                phase = .touching
                return .down(contact.point)
            }
            return .moved(contact.point)

        case .touching:
            if aboveCount >= config.upFrames {
                phase = .hovering
                return .up(contact.point)
            }
            return .dragged(contact.point)
        }
    }
}
