import Foundation
import simd

/// Mirrors of the structs in Shaders.metal. `GPUTypes.verifyLayout()` is called
/// once at startup so a divergence fails loudly instead of producing garbage runs.
enum GPUTypes {
    static let maxRuns = 4
    static let columnRunsStride = 48

    static func verifyLayout() {
        precondition(MemoryLayout<SkinParams>.stride == 64, "SkinParams layout drifted from Shaders.metal")
        precondition(MemoryLayout<MorphParams>.stride == 16, "MorphParams layout drifted from Shaders.metal")
        precondition(MemoryLayout<RLEParams>.stride == 16, "RLEParams layout drifted from Shaders.metal")
    }
}

struct SkinParams {
    var mean: SIMD2<Float>
    var invCov: SIMD3<Float>   // 16-byte aligned, so this struct is 48 bytes
    var threshold: Float
    var lumaMin: Float
    var lumaMax: Float
    var flipX: UInt32
    var flipY: UInt32
}

struct MorphParams {
    var radius: UInt32
    var dilate: UInt32
    var horizontal: UInt32
    var _pad: UInt32 = 0
}

struct RLEParams {
    var minRunLength: UInt32
    var _pad0: UInt32 = 0
    var _pad1: UInt32 = 0
    var _pad2: UInt32 = 0
}

/// Zero-copy view over the run buffer the GPU just filled. Each column is
/// `columnRunsStride` bytes: count, 4 starts, 4 ends, padding.
struct ColumnRunTable {
    let base: UnsafePointer<UInt32>
    let width: Int

    init(buffer: UnsafeRawPointer, width: Int) {
        self.base = buffer.assumingMemoryBound(to: UInt32.self)
        self.width = width
    }

    private func word(_ column: Int, _ index: Int) -> Int {
        Int(base[column * (GPUTypes.columnRunsStride / 4) + index])
    }

    func runCount(_ column: Int) -> Int { min(word(column, 0), GPUTypes.maxRuns) }
    func start(_ column: Int, _ run: Int) -> Int { word(column, 1 + run) }
    func end(_ column: Int, _ run: Int) -> Int { word(column, 1 + GPUTypes.maxRuns + run) }
    func length(_ column: Int, _ run: Int) -> Int { end(column, run) - start(column, run) + 1 }
}
