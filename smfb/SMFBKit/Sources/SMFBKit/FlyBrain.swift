import Foundation
import SMFBCore

/// The cell classes of the simulated fly brain, in the order they are laid
/// out in memory (mirrors `smfb_region` in smfb_core.h).
public enum BrainRegion: Int, CaseIterable, Identifiable, Sendable {
    case ornLeft = 0, ornRight
    case antennalLobeLeft, antennalLobeRight
    case kenyonLeft, kenyonRight
    case aplLeft, aplRight
    case mbonApproachLeft, mbonApproachRight
    case mbonAvoidLeft, mbonAvoidRight
    case lateralHornLeft, lateralHornRight
    case centralComplex
    case descendingLeft, descendingRight, descendingForward
    case mechLeft, mechRight
    case dopamine

    public var id: Int { rawValue }

    var cValue: smfb_region { smfb_region(rawValue: UInt32(rawValue)) }

    /// Short label as the core names it ("KC L", "DN fwd", ...).
    public var name: String { String(cString: smfb_region_name(cValue)) }

    public enum Hemisphere: Sendable { case left, right, midline }

    public var hemisphere: Hemisphere {
        switch smfb_region_is_left(cValue) {
        case 1: return .left
        case 0: return .right
        default: return .midline
        }
    }
}

/// A fly connectome plus the neuron state that runs on it. Thin, owning
/// wrapper over `smfb_brain`; all the work happens in C / NEON.
public final class FlyBrain {
    let ptr: UnsafeMutablePointer<smfb_brain>

    /// - Parameters:
    ///   - scale: 1 is ~1.8k neurons / ~27k synapses; sizes grow linearly.
    ///   - seed: connectome and noise seed. Same seed, same brain, same run.
    public init?(scale: Int, seed: UInt64) {
        guard let p = smfb_brain_create(UInt32(max(1, scale)), seed, nil) else { return nil }
        ptr = p
    }

    deinit { smfb_brain_destroy(ptr) }

    public var neuronCount: Int { Int(smfb_brain_neuron_count(ptr)) }
    public var synapseCount: Int { Int(smfb_brain_synapse_count(ptr)) }
    public var stepCount: UInt64 { ptr.pointee.step_count }
    public var totalSpikes: UInt64 { ptr.pointee.total_spikes }

    /// "neon" on arm64 devices, "portable" on Intel Macs and x86 simulators.
    public var kernelName: String { String(cString: ptr.pointee.k.pointee.name) }

    /// Force the portable kernels (for A/B checks); no-op if already portable.
    public func usePortableKernels() { smfb_brain_use_kernels(ptr, smfb_kernels_portable()) }

    public func step() { smfb_brain_step(ptr) }

    /// Mean activity trace of a region: roughly spikes per neuron per 60 ms.
    public func rate(of region: BrainRegion) -> Float {
        smfb_brain_region_rate(ptr, region.cValue)
    }

    /// Spikes fired by a region on the most recent step.
    public func spikes(in region: BrainRegion) -> Int {
        withUnsafePointer(to: &ptr.pointee.region_spikes) { tuple in
            tuple.withMemoryRebound(to: UInt32.self, capacity: BrainRegion.allCases.count) {
                Int($0[region.rawValue])
            }
        }
    }

    /// Index range of a region's neurons.
    public func span(of region: BrainRegion) -> Range<Int> {
        withUnsafePointer(to: &ptr.pointee.c.pointee.regions) { tuple in
            tuple.withMemoryRebound(to: smfb_region_span.self, capacity: BrainRegion.allCases.count) {
                let s = $0[region.rawValue]
                return Int(s.start)..<Int(s.start + s.count)
            }
        }
    }

    /// Activity trace of one neuron (decays with a 60 ms time constant).
    public func glow(ofNeuron index: Int) -> Float {
        precondition(index >= 0 && index < neuronCount)
        return ptr.pointee.glow[index]
    }

    /// Indices of the neurons that fired on the most recent step.
    public var lastSpikes: [UInt32] {
        Array(UnsafeBufferPointer(start: ptr.pointee.spikes, count: Int(ptr.pointee.n_spikes)))
    }

    public func driveRegion(_ region: BrainRegion, millivolts: Float, fraction: Float = 1) {
        smfb_brain_drive_region(ptr, region.cValue, millivolts, fraction)
    }

    public func clearDrive() { smfb_brain_clear_drive(ptr) }
}
