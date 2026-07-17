// Renderer.swift — Metal renderer for FolkBoy's simulated table.
//
// Draws a FolkFrame (the display list the folk engine emits) onto the
// output pane: a virtual "page" (sheet of paper on the folk table)
// centered in the view, with outlines, fills, highlights, circles,
// and CoreText-rasterized labels/titles.

import Foundation
import MetalKit
import UIKit

enum FolkColor {
    static let named: [String: (Float, Float, Float)] = [
        "white": (1.00, 1.00, 1.00), "black": (0.00, 0.00, 0.00),
        "red": (0.94, 0.22, 0.20), "green": (0.22, 0.82, 0.35),
        "blue": (0.23, 0.42, 0.98), "yellow": (0.99, 0.88, 0.19),
        "gold": (0.98, 0.76, 0.18), "orange": (0.98, 0.56, 0.15),
        "purple": (0.62, 0.28, 0.87), "magenta": (0.93, 0.24, 0.78),
        "pink": (0.99, 0.60, 0.75), "cyan": (0.20, 0.85, 0.90),
        "skyblue": (0.42, 0.75, 0.98), "gray": (0.60, 0.60, 0.60),
        "grey": (0.60, 0.60, 0.60), "brown": (0.62, 0.42, 0.24),
        "teal": (0.13, 0.60, 0.58), "navy": (0.10, 0.13, 0.45),
        "lime": (0.62, 0.94, 0.17), "maroon": (0.55, 0.10, 0.15),
        "silver": (0.78, 0.78, 0.80), "violet": (0.75, 0.48, 0.94),
        "turquoise": (0.24, 0.88, 0.79), "salmon": (0.98, 0.55, 0.48),
        "coral": (0.99, 0.50, 0.37), "indigo": (0.33, 0.20, 0.72),
        "crimson": (0.86, 0.10, 0.28), "hotpink": (1.00, 0.42, 0.71),
        "olive": (0.50, 0.50, 0.11), "tan": (0.82, 0.71, 0.55),
    ]

    static func rgb(_ name: String?) -> (Float, Float, Float) {
        guard let raw = name?.lowercased() else { return (1, 1, 1) }
        if raw.hasPrefix("#"), raw.count == 7,
           let v = UInt32(raw.dropFirst(), radix: 16) {
            return (Float((v >> 16) & 0xff) / 255,
                    Float((v >> 8) & 0xff) / 255,
                    Float(v & 0xff) / 255)
        }
        return named[raw] ?? (1, 1, 1)
    }

    static func rgba(_ name: String?, alpha: Float) -> SIMD4<Float> {
        let c = rgb(name)
        return SIMD4<Float>(c.0, c.1, c.2, alpha)
    }

    static func uiColor(_ name: String?) -> UIColor {
        let c = rgb(name)
        return UIColor(red: CGFloat(c.0), green: CGFloat(c.1),
                       blue: CGFloat(c.2), alpha: 1)
    }
}

final class FolkRenderer: NSObject, MTKViewDelegate {
    // Matches SolidVertex/TexVertex in Shaders.metal (packed floats).
    private struct SolidVertex { var x, y: Float; var r, g, b, a: Float }
    private struct TexVertex { var x, y, u, v: Float }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let texPipeline: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader
    private var textCache: [String: (texture: MTLTexture, size: CGSize)] = [:]

    var frame: FolkFrame?

    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        mtkView.device = device
        guard let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue
        self.textureLoader = MTKTextureLoader(device: device)

        func makePipeline(vertex: String, fragment: String,
                          premultiplied: Bool) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            let att = desc.colorAttachments[0]!
            att.pixelFormat = mtkView.colorPixelFormat
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = premultiplied ? .one : .sourceAlpha
            att.sourceAlphaBlendFactor = premultiplied ? .one : .sourceAlpha
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: desc)
        }
        do {
            solidPipeline = try makePipeline(vertex: "solid_vertex",
                                             fragment: "solid_fragment",
                                             premultiplied: false)
            texPipeline = try makePipeline(vertex: "tex_vertex",
                                           fragment: "tex_fragment",
                                           premultiplied: true)
        } catch {
            return nil
        }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let W = Float(view.drawableSize.width)
        let H = Float(view.drawableSize.height)
        guard W > 0, H > 0 else {
            enc.endEncoding(); cmd.commit(); return
        }
        var viewport = SIMD2<Float>(W, H)
        let scale = Float(view.contentScaleFactor)

        // The virtual page, centered on the table.
        let pw = W * 0.62
        let ph = H * 0.62
        let px = (W - pw) / 2
        let py = (H - ph) / 2

        var solid: [SolidVertex] = []
        appendRect(&solid, px, py, pw, ph, SIMD4<Float>(0.12, 0.13, 0.16, 1))

        var labelOps: [FolkOp] = []
        var titleOps: [FolkOp] = []
        var drawtextOps: [FolkOp] = []
        var errorOps: [FolkOp] = []
        var outlineIndex = 0

        for op in frame?.display ?? [] {
            switch op.op {
            case "fill":
                appendRect(&solid, px, py, pw, ph, FolkColor.rgba(op.color, alpha: 1))
            case "highlight":
                appendRect(&solid, px, py, pw, ph, FolkColor.rgba(op.color, alpha: 0.35))
            case "outline":
                let t = Float(op.thickness ?? 3) * scale
                // Stack multiple outlines outward so all stay visible.
                let inset = Float(outlineIndex) * (t + 3 * scale)
                outlineIndex += 1
                appendBorder(&solid,
                             px - inset, py - inset,
                             pw + 2 * inset, ph + 2 * inset,
                             thickness: t,
                             color: FolkColor.rgba(op.color, alpha: 1))
            case "circle":
                let cx = px + pw / 2 + Float(op.x ?? 0) * scale
                let cy = py + ph / 2 + Float(op.y ?? 0) * scale
                appendCircle(&solid, cx, cy,
                             radius: Float(op.radius ?? 40) * scale,
                             filled: op.filled ?? false,
                             lineWidth: 2 * scale,
                             color: FolkColor.rgba(op.color, alpha: 1))
            case "label": labelOps.append(op)
            case "title": titleOps.append(op)
            case "drawtext": drawtextOps.append(op)
            case "error": errorOps.append(op)
            default: break
            }
        }

        enc.setRenderPipelineState(solidPipeline)
        enc.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)
        if !solid.isEmpty,
           let buf = device.makeBuffer(bytes: solid,
                                       length: solid.count * MemoryLayout<SolidVertex>.stride,
                                       options: []) {
            enc.setVertexBuffer(buf, offset: 0, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: solid.count)
        }

        // Text on top.
        enc.setRenderPipelineState(texPipeline)
        enc.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 1)

        let pageMaxTextWidth = CGFloat(pw) * 0.9

        // Labels: stacked, centered on the page.
        let labels = labelOps.compactMap {
            textTexture($0.text ?? "", colorName: $0.color ?? "white",
                        fontSize: 15, maxWidth: pageMaxTextWidth)
        }
        let totalLabelH = labels.reduce(Float(0)) { $0 + Float($1.size.height) + 4 }
        var yCursor = py + ph / 2 - totalLabelH / 2
        for entry in labels {
            drawTexture(enc, entry,
                        x: px + pw / 2 - Float(entry.size.width) / 2, y: yCursor)
            yCursor += Float(entry.size.height) + 4
        }

        // Titles: above the page.
        var titleY = py - 8 * scale
        for op in titleOps.reversed() {
            if let entry = textTexture(op.text ?? "", colorName: op.color ?? "white",
                                       fontSize: 13, maxWidth: pageMaxTextWidth) {
                titleY -= Float(entry.size.height)
                drawTexture(enc, entry,
                            x: px + pw / 2 - Float(entry.size.width) / 2, y: titleY)
                titleY -= 4
            }
        }

        // drawtext: top-left corner of the page, stacked.
        var dtY = py + 6 * scale
        for op in drawtextOps {
            if let entry = textTexture(op.text ?? "", colorName: op.color ?? "white",
                                       fontSize: 13, maxWidth: pageMaxTextWidth) {
                drawTexture(enc, entry, x: px + 6 * scale, y: dtY)
                dtY += Float(entry.size.height) + 2
            }
        }

        // Errors: top-left of the whole screen, in red.
        var errY = Float(8) * scale
        for op in errorOps {
            if let entry = textTexture(op.text ?? "error", colorName: "red",
                                       fontSize: 11, maxWidth: CGFloat(W) * 0.95) {
                drawTexture(enc, entry, x: 8 * scale, y: errY)
                errY += Float(entry.size.height) + 2
            }
        }

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    // MARK: - geometry helpers

    private func appendRect(_ v: inout [SolidVertex],
                            _ x: Float, _ y: Float, _ w: Float, _ h: Float,
                            _ c: SIMD4<Float>) {
        let pts: [(Float, Float)] = [
            (x, y), (x + w, y), (x, y + h),
            (x + w, y), (x + w, y + h), (x, y + h),
        ]
        for p in pts {
            v.append(SolidVertex(x: p.0, y: p.1, r: c.x, g: c.y, b: c.z, a: c.w))
        }
    }

    private func appendBorder(_ v: inout [SolidVertex],
                              _ x: Float, _ y: Float, _ w: Float, _ h: Float,
                              thickness t: Float, color c: SIMD4<Float>) {
        appendRect(&v, x - t, y - t, w + 2 * t, t, c)          // top
        appendRect(&v, x - t, y + h, w + 2 * t, t, c)          // bottom
        appendRect(&v, x - t, y, t, h, c)                      // left
        appendRect(&v, x + w, y, t, h, c)                      // right
    }

    private func appendCircle(_ v: inout [SolidVertex],
                              _ cx: Float, _ cy: Float,
                              radius: Float, filled: Bool, lineWidth: Float,
                              color c: SIMD4<Float>) {
        let segments = 48
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi
            let a1 = Float(i + 1) / Float(segments) * 2 * .pi
            if filled {
                v.append(SolidVertex(x: cx, y: cy, r: c.x, g: c.y, b: c.z, a: c.w))
                v.append(SolidVertex(x: cx + radius * cos(a0), y: cy + radius * sin(a0),
                                     r: c.x, g: c.y, b: c.z, a: c.w))
                v.append(SolidVertex(x: cx + radius * cos(a1), y: cy + radius * sin(a1),
                                     r: c.x, g: c.y, b: c.z, a: c.w))
            } else {
                let r0 = radius - lineWidth / 2
                let r1 = radius + lineWidth / 2
                let p00 = (cx + r0 * cos(a0), cy + r0 * sin(a0))
                let p01 = (cx + r1 * cos(a0), cy + r1 * sin(a0))
                let p10 = (cx + r0 * cos(a1), cy + r0 * sin(a1))
                let p11 = (cx + r1 * cos(a1), cy + r1 * sin(a1))
                for p in [p00, p01, p10, p01, p11, p10] {
                    v.append(SolidVertex(x: p.0, y: p.1, r: c.x, g: c.y, b: c.z, a: c.w))
                }
            }
        }
    }

    // MARK: - text

    private func textTexture(_ text: String, colorName: String,
                             fontSize: CGFloat, maxWidth: CGFloat)
        -> (texture: MTLTexture, size: CGSize)? {
        guard !text.isEmpty else { return nil }
        let key = "\(text)|\(colorName)|\(Int(fontSize))|\(Int(maxWidth))"
        if let hit = textCache[key] { return hit }
        if textCache.count > 256 { textCache.removeAll() }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: FolkColor.uiColor(colorName),
        ]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: max(maxWidth, 20), height: 2000),
            options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        let pointSize = CGSize(width: ceil(bounds.width) + 4,
                               height: ceil(bounds.height) + 4)

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 2
        fmt.opaque = false
        let image = UIGraphicsImageRenderer(size: pointSize, format: fmt).image { _ in
            (text as NSString).draw(
                with: CGRect(origin: CGPoint(x: 2, y: 2), size: bounds.size),
                options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        }
        guard let cg = image.cgImage,
              let tex = try? textureLoader.newTexture(cgImage: cg, options: [.SRGB: false])
        else { return nil }

        // Pixel size in drawable units (renderer format scale 2 ≈ retina).
        let entry = (texture: tex,
                     size: CGSize(width: pointSize.width * 2, height: pointSize.height * 2))
        textCache[key] = entry
        return entry
    }

    private func drawTexture(_ enc: MTLRenderCommandEncoder,
                             _ entry: (texture: MTLTexture, size: CGSize),
                             x: Float, y: Float) {
        let w = Float(entry.size.width)
        let h = Float(entry.size.height)
        let verts: [TexVertex] = [
            TexVertex(x: x, y: y, u: 0, v: 0),
            TexVertex(x: x + w, y: y, u: 1, v: 0),
            TexVertex(x: x, y: y + h, u: 0, v: 1),
            TexVertex(x: x + w, y: y, u: 1, v: 0),
            TexVertex(x: x + w, y: y + h, u: 1, v: 1),
            TexVertex(x: x, y: y + h, u: 0, v: 1),
        ]
        enc.setVertexBytes(verts, length: verts.count * MemoryLayout<TexVertex>.stride, index: 0)
        enc.setFragmentTexture(entry.texture, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: verts.count)
    }
}
