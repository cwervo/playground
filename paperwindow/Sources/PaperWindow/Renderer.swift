import MetalKit
import simd

struct MeshVertex {
    var position: SIMD2<Float> = .zero   // view points
    var uv: SIMD2<Float> = .zero
    var shade: Float = 1
    var pad: Float = 0
}

struct MeshUniforms {
    var viewport: SIMD2<Float> = .zero
    var offset: SIMD2<Float> = .zero
    var isShadow: Float = 0
    var alpha: Float = 1
    var pad: SIMD2<Float> = .zero
}

/// Draws the deformed sheet: a textured triangle grid, plus a cheap offset copy
/// underneath for the drop shadow.
final class Renderer {

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var texture: MTLTexture
    private let indexBuffer: MTLBuffer
    private let indexCount: Int

    private var vertexBuffers: [MTLBuffer] = []
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: 3)

    private var scratch: [MeshVertex]

    var drawShadow = true
    var shadowOffset = SIMD2<Float>(7, -10)
    var shadowAlpha: Float = 0.28

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, image: CGImage, cols: Int, rows: Int) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        let loader = MTKTextureLoader(device: device)
        // Load the raw sRGB bytes: the drawable is a plain bgra8Unorm surface, so
        // no colour space conversion should happen on the way in or out.
        guard let texture = try? loader.newTexture(cgImage: image, options: [
            .SRGB: NSNumber(value: false),
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ]) else { return nil }
        self.texture = texture

        guard let library = try? device.makeLibrary(source: Renderer.shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "paper_vertex"),
              let fragmentFunction = library.makeFunction(name: "paper_fragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        attachment.isBlendingEnabled = true
        // Fragments are premultiplied, which is also what CoreAnimation wants
        // from a transparent layer.
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipeline = pipeline

        var indices: [UInt32] = []
        indices.reserveCapacity((cols - 1) * (rows - 1) * 6)
        for j in 0..<(rows - 1) {
            for i in 0..<(cols - 1) {
                let a = UInt32(j * cols + i)
                let b = a + 1
                let c = UInt32((j + 1) * cols + i)
                let d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        indexCount = indices.count
        guard let indexBuffer = device.makeBuffer(bytes: indices,
                                                  length: indices.count * MemoryLayout<UInt32>.stride,
                                                  options: .storageModeShared) else { return nil }
        self.indexBuffer = indexBuffer

        let vertexCount = cols * rows
        scratch = Array(repeating: MeshVertex(), count: vertexCount)
        for _ in 0..<3 {
            guard let buffer = device.makeBuffer(length: vertexCount * MemoryLayout<MeshVertex>.stride,
                                                 options: .storageModeShared) else { return nil }
            vertexBuffers.append(buffer)
        }
    }

    /// Swap in freshly captured pixels (used by --live).
    func update(image: CGImage) {
        let loader = MTKTextureLoader(device: device)
        if let new = try? loader.newTexture(cgImage: image, options: [
            .SRGB: NSNumber(value: false),
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ]) {
            texture = new
        }
    }

    func draw(sheet: ElasticSheet, in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = queue.makeCommandBuffer()
        else { return }

        inFlight.wait()
        bufferIndex = (bufferIndex + 1) % vertexBuffers.count
        let vertexBuffer = vertexBuffers[bufferIndex]
        fillVertices(from: sheet)
        scratch.withUnsafeBytes { raw in
            vertexBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            inFlight.signal()
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)

        var uniforms = MeshUniforms()
        uniforms.viewport = SIMD2(Float(view.bounds.width), Float(view.bounds.height))

        if drawShadow {
            uniforms.offset = shadowOffset
            uniforms.isShadow = 1
            uniforms.alpha = shadowAlpha
            encode(&uniforms, with: encoder)
        }

        uniforms.offset = .zero
        uniforms.isShadow = 0
        uniforms.alpha = 1
        encode(&uniforms, with: encoder)

        encoder.endEncoding()
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func encode(_ uniforms: inout MeshUniforms, with encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MeshUniforms>.stride, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: indexCount,
                                      indexType: .uint32,
                                      indexBuffer: indexBuffer,
                                      indexBufferOffset: 0)
    }

    /// Copies the lattice into vertices and shades it from the local distortion:
    /// stretched paper catches the light, squashed and sheared paper falls dark.
    private func fillVertices(from sheet: ElasticSheet) {
        let cols = sheet.cols, rows = sheet.rows
        let du = sheet.cellW, dv = sheet.cellH
        let pos = sheet.pos

        for j in 0..<rows {
            for i in 0..<cols {
                let index = j * cols + i
                let ip = min(i + 1, cols - 1), im = max(i - 1, 0)
                let jp = min(j + 1, rows - 1), jm = max(j - 1, 0)

                let dxdu = (pos[j * cols + ip] - pos[j * cols + im]) / (Float(ip - im) * du)
                let dxdv = (pos[jp * cols + i] - pos[jm * cols + i]) / (Float(jp - jm) * dv)

                // |det J| is the local area ratio; the dot of the normalised
                // columns is how far the cell has been sheared out of square.
                let area = abs(dxdu.x * dxdv.y - dxdu.y * dxdv.x)
                var shear: Float = 0
                let lu = simd_length(dxdu), lv = simd_length(dxdv)
                if lu > 1e-5 && lv > 1e-5 {
                    shear = abs(simd_dot(dxdu / lu, dxdv / lv))
                }
                let shade = min(1.6, max(0.5, 1 + 0.95 * (area - 1) - 0.8 * shear))

                scratch[index] = MeshVertex(
                    position: pos[index],
                    uv: SIMD2(Float(i) / Float(cols - 1), Float(j) / Float(rows - 1)),
                    shade: shade)
            }
        }
    }

    // MARK: - Shaders

    private static let shaderSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Vertex {
        float2 position;
        float2 uv;
        float  shade;
        float  pad;
    };

    struct Uniforms {
        float2 viewport;
        float2 offset;
        float  isShadow;
        float  alpha;
        float2 pad;
    };

    struct Varying {
        float4 position [[position]];
        float2 uv;
        float  shade;
    };

    vertex Varying paper_vertex(uint vid [[vertex_id]],
                                device const Vertex *verts [[buffer(0)]],
                                constant Uniforms &u [[buffer(1)]])
    {
        Vertex v = verts[vid];
        float2 p = v.position + u.offset;
        float2 ndc = (p / u.viewport) * 2.0 - 1.0;

        Varying out;
        out.position = float4(ndc, 0.0, 1.0);
        out.uv = v.uv;
        out.shade = v.shade;
        return out;
    }

    fragment float4 paper_fragment(Varying in [[stage_in]],
                                   constant Uniforms &u [[buffer(1)]],
                                   texture2d<float> tex [[texture(0)]])
    {
        constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
        float4 c = tex.sample(s, in.uv);

        if (u.isShadow > 0.5) {
            // Premultiplied black, shaped by the sheet's own alpha.
            return float4(0.0, 0.0, 0.0, c.a * u.alpha);
        }

        // The texture arrives premultiplied, so scaling rgb and a together keeps
        // it that way.
        return float4(c.rgb * in.shade * u.alpha, c.a * u.alpha);
    }
    """#
}
