import Foundation
import Metal
import CoreVideo
import simd

/// The whole computer-vision stage: four compute dispatches per frame, one
/// command buffer, one small readback.
///
///   luma+chroma -> skin_mask -> open (erode,dilate) -> close (dilate,erode) -> column_rle
///
/// Everything up to the run table stays on the GPU in private storage. Only the
/// run table (width * 48 bytes, ~60 KB at 720p) crosses back to the CPU, so the
/// per-frame PCIe/UMA traffic is a rounding error and there is no image-sized
/// map/unmap stall of the kind cv2.findContours forces.
final class SegmentationPipeline {
    private let ctx: MetalContext
    private let skin: MTLComputePipelineState
    private let morph: MTLComputePipelineState
    private let rle: MTLComputePipelineState

    private let width: Int
    private let height: Int

    private var maskA: MTLTexture
    private var maskB: MTLTexture
    private let runBuffer: MTLBuffer
    private let roiBuffer: MTLBuffer

    /// Retained so the HUD can draw the same frame the detector saw.
    private(set) var lastMask: MTLTexture

    init(ctx: MetalContext, width: Int, height: Int) throws {
        self.ctx = ctx
        self.width = width
        self.height = height
        self.skin = try ctx.pipeline("skin_mask")
        self.morph = try ctx.pipeline("morph")
        self.rle = try ctx.pipeline("column_rle")

        self.maskA = ctx.makeMaskTexture(width: width, height: height)
        self.maskB = ctx.makeMaskTexture(width: width, height: height)
        self.lastMask = maskA

        self.runBuffer = ctx.device.makeBuffer(
            length: width * GPUTypes.columnRunsStride, options: .storageModeShared)!
        self.roiBuffer = ctx.device.makeBuffer(
            length: width * MemoryLayout<SIMD2<UInt32>>.stride, options: .storageModeShared)!
        setROI(nil)
    }

    /// Per-column [yMin, yMax) clip, derived from the calibrated screen quad.
    /// This is the single most effective robustness measure in the app: without
    /// it, a forearm resting below the near bezel is a huge skin blob that
    /// out-votes the fingertip in every frame.
    func setROI(_ quad: [SIMD2<Float>]?) {
        let p = roiBuffer.contents().assumingMemoryBound(to: SIMD2<UInt32>.self)
        guard let quad, quad.count == 4 else {
            for x in 0..<width { p[x] = SIMD2(0, UInt32(height)) }
            return
        }
        // Rasterise the quad's vertical extent per column with a 12 px margin so
        // a fingertip crossing the screen edge is not clipped mid-gesture.
        let margin: Float = 12
        for x in 0..<width {
            var lo = Float(height)
            var hi: Float = 0
            let fx = Float(x)
            for i in 0..<4 {
                let a = quad[i], b = quad[(i + 1) % 4]
                if (a.x <= fx && fx <= b.x) || (b.x <= fx && fx <= a.x), abs(b.x - a.x) > 0.0001 {
                    let t = (fx - a.x) / (b.x - a.x)
                    let y = a.y + t * (b.y - a.y)
                    lo = min(lo, y)
                    hi = max(hi, y)
                }
            }
            if hi <= lo {
                p[x] = SIMD2(0, 0)          // column lies outside the screen quad
            } else {
                let y0 = max(0, Int(lo - margin))
                let y1 = min(height, Int(hi + margin))
                p[x] = SIMD2(UInt32(y0), UInt32(y1))
            }
        }
    }

    /// Encodes the frame's work and calls `completion` off the GPU completion
    /// handler with a view over the freshly written run table.
    func process(luma: MTLTexture,
                 chroma: MTLTexture,
                 skinParams: SkinParams,
                 config: Config,
                 completion: @escaping (ColumnRunTable) -> Void)
    {
        // makeComputeCommandEncoder() defaults to MTLDispatchType.serial, so the
        // ping-pong below gets an implicit barrier between dispatches.
        guard let cb = ctx.queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return }

        var skinParams = skinParams
        enc.setTexture(luma, index: 0)
        enc.setTexture(chroma, index: 1)
        enc.setTexture(maskA, index: 2)
        enc.setBytes(&skinParams, length: MemoryLayout<SkinParams>.stride, index: 0)
        enc.dispatch2D(skin, width: width, height: height)

        // open = erode then dilate (kill speckle); close = dilate then erode
        // (bridge the specular highlight that splits a fingernail in two).
        let r = config.morphRadius
        morphPass(enc, from: maskA, to: maskB, radius: r, dilate: false, horizontal: true)
        morphPass(enc, from: maskB, to: maskA, radius: r, dilate: false, horizontal: false)
        morphPass(enc, from: maskA, to: maskB, radius: r, dilate: true,  horizontal: true)
        morphPass(enc, from: maskB, to: maskA, radius: r, dilate: true,  horizontal: false)
        morphPass(enc, from: maskA, to: maskB, radius: r, dilate: true,  horizontal: true)
        morphPass(enc, from: maskB, to: maskA, radius: r, dilate: true,  horizontal: false)
        morphPass(enc, from: maskA, to: maskB, radius: r, dilate: false, horizontal: true)
        morphPass(enc, from: maskB, to: maskA, radius: r, dilate: false, horizontal: false)

        var rleParams = RLEParams(minRunLength: config.minRunLength)
        enc.setTexture(maskA, index: 0)
        enc.setBuffer(runBuffer, offset: 0, index: 0)
        enc.setBuffer(roiBuffer, offset: 0, index: 1)
        enc.setBytes(&rleParams, length: MemoryLayout<RLEParams>.stride, index: 2)
        enc.dispatch1D(rle, count: width)

        enc.endEncoding()

        let buffer = runBuffer
        let w = width
        cb.addCompletedHandler { [weak self] _ in
            guard self != nil else { return }
            completion(ColumnRunTable(buffer: buffer.contents(), width: w))
        }
        lastMask = maskA
        cb.commit()
    }

    private func morphPass(_ enc: MTLComputeCommandEncoder,
                           from src: MTLTexture, to dst: MTLTexture,
                           radius: UInt32, dilate: Bool, horizontal: Bool)
    {
        var p = MorphParams(radius: radius,
                            dilate: dilate ? 1 : 0,
                            horizontal: horizontal ? 1 : 0)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        enc.setBytes(&p, length: MemoryLayout<MorphParams>.stride, index: 0)
        enc.dispatch2D(morph, width: width, height: height)
    }
}
