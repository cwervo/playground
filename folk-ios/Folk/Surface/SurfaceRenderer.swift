// SurfaceRenderer.swift
// Translates the Surface's instruction list into Metal draw calls each frame.
// Shapes are tessellated to triangles on the CPU and drawn with a flat-color
// pipeline; metaballs get their own full-screen field pass.

import Foundation
import Metal
import MetalKit
import simd

struct ShapeVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

struct SurfaceUniforms {
    var viewport: SIMD2<Float>
}

struct MetaballUniforms {
    var centers: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>,
                  SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)
    var viewport: SIMD2<Float>
    var color: SIMD4<Float>
    var radius: Float
    var count: Int32

    init() {
        let z = SIMD2<Float>(0, 0)
        centers = (z, z, z, z, z, z, z, z)
        viewport = SIMD2(1, 1)
        color = SIMD4(1, 1, 1, 1)
        radius = 0
        count = 0
    }
}

final class SurfaceRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let shapePipeline: MTLRenderPipelineState
    private let metaballPipeline: MTLRenderPipelineState

    /// Called at the start of every frame so the VM can produce this
    /// frame's instructions.
    var onFrame: ((CGSize) -> Void)?

    /// The current instruction list (set by the engine each tick).
    var instructions: [DrawInstruction] = []

    private var viewportPoints = CGSize(width: 1, height: 1)

    init?(pixelFormat: MTLPixelFormat) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            return nil
        }
        self.device = device
        self.queue = queue

        func makePipeline(vertex: String, fragment: String) -> MTLRenderPipelineState? {
            guard let vfn = library.makeFunction(name: vertex),
                  let ffn = library.makeFunction(name: fragment) else { return nil }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            let att = desc.colorAttachments[0]!
            att.pixelFormat = pixelFormat
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .sourceAlpha
            att.sourceAlphaBlendFactor = .sourceAlpha
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: desc)
        }

        guard let shape = makePipeline(vertex: "shape_vertex", fragment: "shape_fragment"),
              let meta = makePipeline(vertex: "metaball_vertex", fragment: "metaball_fragment") else {
            return nil
        }
        shapePipeline = shape
        metaballPipeline = meta
        super.init()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // We work in points; nothing to do here.
    }

    func draw(in view: MTKView) {
        viewportPoints = view.bounds.size
        if viewportPoints.width < 1 || viewportPoints.height < 1 { return }

        onFrame?(viewportPoints)

        // The first clear instruction sets the background; default is
        // Folk-projector black.
        var clear = RGBA.black
        for case .clear(let c) in instructions {
            clear = c
            break
        }
        view.clearColor = MTLClearColor(red: Double(clear.r), green: Double(clear.g),
                                        blue: Double(clear.b), alpha: Double(clear.a))

        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        // Tessellate shapes in instruction order, flushing the vertex batch
        // whenever a metaball pass interleaves.
        enum Segment {
            case shapes(Range<Int>)
            case metaballs(MetaballUniforms)
        }
        var vertices: [ShapeVertex] = []
        var segments: [Segment] = []
        var segmentStart = 0

        func flushShapes() {
            if vertices.count > segmentStart {
                segments.append(.shapes(segmentStart..<vertices.count))
            }
            segmentStart = vertices.count
        }

        let viewport = SIMD2<Float>(Float(viewportPoints.width), Float(viewportPoints.height))

        for instruction in instructions {
            switch instruction {
            case .clear, .text:
                continue
            case .line(let a, let b, let thickness, let color):
                appendLine(&vertices, a, b, thickness, color.simd)
            case .rect(let origin, let size, let color):
                appendRect(&vertices, origin, size, color.simd)
            case .circle(let center, let radius, let thickness, let color):
                if let t = thickness {
                    appendRing(&vertices, center, radius, t, color.simd)
                } else {
                    appendDisc(&vertices, center, radius, color.simd)
                }
            case .metaballs(let centers, let radius, let color):
                flushShapes()
                var u = MetaballUniforms()
                u.viewport = viewport
                u.color = color.simd
                u.radius = radius
                u.count = Int32(min(centers.count, 8))
                withUnsafeMutableBytes(of: &u.centers) { raw in
                    let buf = raw.bindMemory(to: SIMD2<Float>.self)
                    for (i, c) in centers.prefix(8).enumerated() { buf[i] = c }
                }
                segments.append(.metaballs(u))
            }
        }
        flushShapes()

        var uniforms = SurfaceUniforms(viewport: viewport)
        let vertexBuffer: MTLBuffer? = vertices.isEmpty ? nil :
            device.makeBuffer(bytes: vertices,
                              length: vertices.count * MemoryLayout<ShapeVertex>.stride,
                              options: .storageModeShared)

        for segment in segments {
            switch segment {
            case .shapes(let range):
                guard let buffer = vertexBuffer else { continue }
                encoder.setRenderPipelineState(shapePipeline)
                encoder.setVertexBuffer(buffer, offset: range.lowerBound * MemoryLayout<ShapeVertex>.stride, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<SurfaceUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: range.count)
            case .metaballs(var u):
                encoder.setRenderPipelineState(metaballPipeline)
                encoder.setFragmentBytes(&u, length: MemoryLayout<MetaballUniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Tessellation

    private func appendLine(_ out: inout [ShapeVertex],
                            _ a: SIMD2<Float>, _ b: SIMD2<Float>,
                            _ thickness: Float, _ color: SIMD4<Float>) {
        let d = b - a
        let len = max(sqrt(d.x * d.x + d.y * d.y), 1e-4)
        let n = SIMD2<Float>(-d.y / len, d.x / len) * (thickness / 2)
        let p0 = a + n, p1 = a - n, p2 = b + n, p3 = b - n
        out.append(ShapeVertex(position: p0, color: color))
        out.append(ShapeVertex(position: p1, color: color))
        out.append(ShapeVertex(position: p2, color: color))
        out.append(ShapeVertex(position: p1, color: color))
        out.append(ShapeVertex(position: p3, color: color))
        out.append(ShapeVertex(position: p2, color: color))
    }

    private func appendRect(_ out: inout [ShapeVertex],
                            _ origin: SIMD2<Float>, _ size: SIMD2<Float>,
                            _ color: SIMD4<Float>) {
        let p0 = origin
        let p1 = origin + SIMD2<Float>(size.x, 0)
        let p2 = origin + SIMD2<Float>(0, size.y)
        let p3 = origin + size
        out.append(ShapeVertex(position: p0, color: color))
        out.append(ShapeVertex(position: p1, color: color))
        out.append(ShapeVertex(position: p2, color: color))
        out.append(ShapeVertex(position: p1, color: color))
        out.append(ShapeVertex(position: p3, color: color))
        out.append(ShapeVertex(position: p2, color: color))
    }

    private func appendDisc(_ out: inout [ShapeVertex],
                            _ center: SIMD2<Float>, _ radius: Float,
                            _ color: SIMD4<Float>) {
        let segments = 48
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            out.append(ShapeVertex(position: center, color: color))
            out.append(ShapeVertex(position: center + radius * SIMD2(cos(a0), sin(a0)), color: color))
            out.append(ShapeVertex(position: center + radius * SIMD2(cos(a1), sin(a1)), color: color))
        }
    }

    private func appendRing(_ out: inout [ShapeVertex],
                            _ center: SIMD2<Float>, _ radius: Float,
                            _ thickness: Float, _ color: SIMD4<Float>) {
        let segments = 64
        let rOuter = radius + thickness / 2
        let rInner = max(radius - thickness / 2, 0)
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let d0 = SIMD2<Float>(cos(a0), sin(a0))
            let d1 = SIMD2<Float>(cos(a1), sin(a1))
            let o0 = center + rOuter * d0
            let o1 = center + rOuter * d1
            let i0 = center + rInner * d0
            let i1 = center + rInner * d1
            out.append(ShapeVertex(position: o0, color: color))
            out.append(ShapeVertex(position: i0, color: color))
            out.append(ShapeVertex(position: o1, color: color))
            out.append(ShapeVertex(position: i0, color: color))
            out.append(ShapeVertex(position: i1, color: color))
            out.append(ShapeVertex(position: o1, color: color))
        }
    }
}
