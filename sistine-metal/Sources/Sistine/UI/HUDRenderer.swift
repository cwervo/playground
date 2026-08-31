import Foundation
import Metal
import MetalKit
import CoreGraphics
import CoreText
import AppKit
import simd

/// Draws the debug overlay: a camera/mask preview panel plus vector annotation.
///
/// Division of labour is deliberate. CoreGraphics draws everything vector and
/// textual — calibration rings, crosshairs, the readout — into one bitmap, once
/// per frame, because that is the API that already knows how to rasterise text
/// and strokes well. Metal composites that bitmap over the GPU-resident camera
/// and mask textures, because those never need to touch the CPU at all.
final class HUDRenderer: NSObject, MTKViewDelegate {
    private let ctx: MetalContext
    private let state: HUDStateBox

    private var panelPipeline: MTLRenderPipelineState!
    private var overlayPipeline: MTLRenderPipelineState!

    private var overlayTexture: MTLTexture?
    private var overlayContext: CGContext?
    private var overlaySize = CGSize.zero
    private let blankTexture: MTLTexture

    /// Latest camera + mask textures, published by the vision stage.
    private let textureLock = NSLock()
    private var cameraTexture: MTLTexture?
    private var maskTexture: MTLTexture?

    /// The overlay bitmap is redrawn every frame, so cap it well below Retina
    /// resolution — at 3024x1964 a full CoreGraphics repaint costs more than the
    /// entire vision pipeline.
    private let maxOverlayDimension: CGFloat = 1920

    init(ctx: MetalContext, state: HUDStateBox, pixelFormat: MTLPixelFormat) throws {
        self.ctx = ctx
        self.state = state
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
        self.blankTexture = ctx.device.makeTexture(descriptor: d)!
        super.init()
        try makePipelines(pixelFormat: pixelFormat)
    }

    func publish(camera: MTLTexture?, mask: MTLTexture?) {
        textureLock.lock()
        cameraTexture = camera
        maskTexture = mask
        textureLock.unlock()
    }

    private func makePipelines(pixelFormat: MTLPixelFormat) throws {
        func make(_ fragment: String) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = ctx.library.makeFunction(name: "hud_vertex")
            d.fragmentFunction = ctx.library.makeFunction(name: fragment)
            let a = d.colorAttachments[0]!
            a.pixelFormat = pixelFormat
            a.isBlendingEnabled = true
            // Premultiplied source-over: both shaders emit premultiplied colour.
            a.sourceRGBBlendFactor = .one
            a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try ctx.device.makeRenderPipelineState(descriptor: d)
        }
        panelPipeline = try make("hud_fragment")
        overlayPipeline = try make("overlay_fragment")
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let cb = ctx.queue.makeCommandBuffer() else { return }

        let snapshot = state.value
        let pointSize = view.bounds.size
        redrawOverlay(pointSize: pointSize, state: snapshot)

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let enc = cb.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        // 1. Camera + mask preview, confined to a corner viewport.
        textureLock.lock()
        let camera = cameraTexture
        let mask = maskTexture
        textureLock.unlock()

        if snapshot.enabled, let camera, let mask {
            let scale = drawable.texture.width > 0
                ? CGFloat(drawable.texture.width) / max(pointSize.width, 1) : 1
            let panel = panelRect(in: pointSize)
            enc.setViewport(MTLViewport(
                originX: Double(panel.minX * scale), originY: Double(panel.minY * scale),
                width: Double(panel.width * scale), height: Double(panel.height * scale),
                znear: 0, zfar: 1))
            enc.setRenderPipelineState(panelPipeline)
            enc.setFragmentTexture(camera, index: 0)
            enc.setFragmentTexture(mask, index: 1)
            enc.setFragmentTexture(overlayTexture ?? blankTexture, index: 2)
            var alpha: Float = 0.82
            enc.setFragmentBytes(&alpha, length: MemoryLayout<Float>.size, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // 2. Full-screen vector layer on top.
        if let overlayTexture {
            enc.setViewport(MTLViewport(
                originX: 0, originY: 0,
                width: Double(drawable.texture.width), height: Double(drawable.texture.height),
                znear: 0, zfar: 1))
            enc.setRenderPipelineState(overlayPipeline)
            enc.setFragmentTexture(overlayTexture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    /// MTLViewport's origin is top-left of the render target, so a bottom-left
    /// panel needs the explicit flip. The preview lives at the bottom of the
    /// screen on purpose: it is inside the camera's own field of view, and the
    /// top of the display is where the mirror's view of the glass is densest.
    private func panelRect(in size: CGSize) -> CGRect {
        let w = min(size.width * 0.28, 460)
        let h = w * 9 / 16
        return CGRect(x: 24, y: size.height - h - 24, width: w, height: h)
    }

    // MARK: - CoreGraphics layer

    private func redrawOverlay(pointSize: CGSize, state s: HUDState) {
        guard pointSize.width > 1, pointSize.height > 1 else { return }
        let scale = min(1, maxOverlayDimension / max(pointSize.width, pointSize.height))
        let px = CGSize(width: (pointSize.width * scale).rounded(),
                        height: (pointSize.height * scale).rounded())

        if overlayContext == nil || overlaySize != px {
            overlaySize = px
            overlayContext = CGContext(
                data: nil, width: Int(px.width), height: Int(px.height),
                bitsPerComponent: 8, bytesPerRow: Int(px.width) * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue)
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: Int(px.width), height: Int(px.height),
                mipmapped: false)
            d.usage = .shaderRead
            d.storageMode = .shared
            overlayTexture = ctx.device.makeTexture(descriptor: d)
        }
        guard let g = overlayContext, let tex = overlayTexture else { return }

        g.clear(CGRect(origin: .zero, size: px))
        g.saveGState()
        // Flip to a top-left origin so overlay coordinates match CGDisplayBounds
        // and CGEvent — one coordinate convention end to end.
        g.translateBy(x: 0, y: px.height)
        g.scaleBy(x: scale, y: -scale)
        g.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        drawCalibration(g, state: s, size: pointSize)
        drawCursor(g, state: s)
        drawReadout(g, state: s, size: pointSize)

        g.restoreGState()

        tex.replace(region: MTLRegionMake2D(0, 0, Int(px.width), Int(px.height)),
                    mipmapLevel: 0,
                    withBytes: g.data!,
                    bytesPerRow: g.bytesPerRow)
    }

    private func drawCalibration(_ g: CGContext, state s: HUDState, size: CGSize) {
        guard let target = s.calibrationTarget else { return }

        // Dim the rest of the screen so the eye — and the finger — go to the ring
        // and nowhere else. Blues and whites only: the camera is looking at this
        // very image, and a warm target would land inside the skin ellipse.
        g.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 0.88))
        g.fill(CGRect(origin: .zero, size: size))

        for (radius, alpha) in [(46.0, 0.25), (30.0, 0.45), (16.0, 0.9)] {
            g.setStrokeColor(CGColor(red: 0.35, green: 0.75, blue: 1.0, alpha: alpha))
            g.setLineWidth(2)
            g.strokeEllipse(in: CGRect(x: target.x - radius, y: target.y - radius,
                                       width: radius * 2, height: radius * 2))
        }
        g.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        g.fillEllipse(in: CGRect(x: target.x - 4, y: target.y - 4, width: 8, height: 8))

        if let p = s.calibrationProgress {
            text(g, "Touch the ring   \(p.done + 1) / \(p.total)",
                 at: CGPoint(x: size.width / 2 - 110, y: size.height - 90), size: 20)
        }
        if let banner = s.banner {
            text(g, banner, at: CGPoint(x: size.width / 2 - 240, y: 70), size: 16)
        }
    }

    private func drawCursor(_ g: CGContext, state s: HUDState) {
        guard s.enabled, let p = s.screenPoint else { return }
        let touching = s.phase == .touching
        let r: CGFloat = touching ? 12 : 20
        g.setStrokeColor(touching
            ? CGColor(red: 0.2, green: 1.0, blue: 0.7, alpha: 0.95)
            : CGColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 0.55))
        g.setLineWidth(touching ? 3 : 1.5)
        g.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    }

    private func drawReadout(_ g: CGContext, state s: HUDState, size: CGSize) {
        guard s.enabled else { return }
        var lines = [
            String(format: "%.0f fps   %.1f ms", s.fps, s.frameMilliseconds),
            "phase   \(s.phase)",
        ]
        if let c = s.contact {
            lines.append(String(format: "gap     %.1f px", c.gap))
            lines.append(String(format: "width   %.0f px", c.widthPx))
            lines.append(String(format: "ratio   %.3f", c.normalizedGap))
        } else {
            lines.append("gap     --")
        }

        let origin = CGPoint(x: 24, y: size.height - CGFloat(lines.count) * 18 - 34)
        g.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        g.fill(CGRect(x: origin.x - 10, y: origin.y - 20,
                      width: 220, height: CGFloat(lines.count) * 18 + 26))
        for (i, line) in lines.enumerated() {
            text(g, line, at: CGPoint(x: origin.x, y: origin.y + CGFloat(i) * 18), size: 12)
        }
    }

    private func text(_ g: CGContext, _ string: String, at point: CGPoint, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes))
        g.textPosition = point
        CTLineDraw(line, g)
    }
}
