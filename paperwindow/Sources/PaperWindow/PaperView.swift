import MetalKit
import QuartzCore
import simd

protocol PaperViewDelegate: AnyObject {
    func paperViewDidRequestExit(_ view: PaperView)
}

/// The stage: a transparent Metal view that runs the sheet simulation and turns
/// mouse drags into pulls on the paper.
final class PaperView: MTKView {

    weak var paperDelegate: PaperViewDelegate?

    private let sheet: ElasticSheet
    private let renderer: Renderer
    private var lastTime = CACurrentMediaTime()
    private var accumulator: Double = 0

    private let fixedStep: Double = 1.0 / 120.0
    private let cornerGrabRadius: CGFloat = 34
    private let bodyGrabRadius: CGFloat = 40
    /// Downward pull per substep, in points. ~700 pt/s² at 120 Hz.
    private static let gravityStrength: Float = 0.05

    init?(frame: CGRect, image: CGImage, restRect: CGRect, options: Options) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let sheet = ElasticSheet(frame: restRect,
                                 spacing: CGFloat(options.gridSpacing),
                                 stiffness: Float(options.stiffness))
        // Small per-iteration pull: the sheet takes about a second to settle,
        // overshooting and wobbling on the way, instead of snapping rigidly flat.
        sheet.springBack = 0.0018 * Float(options.springBack)
        sheet.gravity = options.gravity ? PaperView.gravityStrength : 0
        self.sheet = sheet

        guard let renderer = Renderer(device: device,
                                      pixelFormat: .bgra8Unorm,
                                      image: image,
                                      cols: sheet.cols,
                                      rows: sheet.rows) else { return nil }
        renderer.drawShadow = options.shadow
        self.renderer = renderer

        super.init(frame: frame, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        framebufferOnly = true
        enableSetNeedsDisplay = false
        isPaused = false
        preferredFramesPerSecond = 120
        autoResizeDrawable = true
        wantsLayer = true
        layer?.isOpaque = false
        (layer as? CAMetalLayer)?.isOpaque = false
    }

    required init(coder: NSCoder) { fatalError("not supported") }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    // MARK: - Live texture

    func updateTexture(_ image: CGImage) { renderer.update(image: image) }

    // MARK: - Frame loop

    override func draw(_ dirtyRect: NSRect) {
        let now = CACurrentMediaTime()
        // Clamp so a stall (or a drag of the title bar) does not explode the sim.
        accumulator = min(accumulator + (now - lastTime), 0.1)
        lastTime = now

        var substeps = 0
        while accumulator >= fixedStep {
            substeps += 1
            accumulator -= fixedStep
        }
        if substeps > 0 {
            for n in 1...substeps {
                sheet.step(progress: Float(n) / Float(substeps))
            }
            sheet.commitGrabTarget()
        }

        renderer.draw(sheet: sheet, in: self)
    }

    // MARK: - Grabbing

    private func viewPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = viewPoint(event)
        // A click that lands nowhere near the sheet is not a grab.
        guard let index = sheet.corner(near: point, radius: cornerGrabRadius)
                ?? sheet.nearest(to: point, within: bodyGrabRadius) else { return }
        sheet.beginGrab(index: index, at: point)
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard sheet.isGrabbing else { return }
        sheet.moveGrab(to: viewPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        if sheet.isGrabbing { sheet.moveGrab(to: viewPoint(event)) }
        sheet.endGrab()
        cursorForPoint(viewPoint(event)).set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !sheet.isGrabbing else { return }
        cursorForPoint(viewPoint(event)).set()
    }

    private func cursorForPoint(_ point: CGPoint) -> NSCursor {
        sheet.corner(near: point, radius: cornerGrabRadius) != nil ? .openHand : .arrow
    }

    // MARK: - Keys

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:                       // esc
            paperDelegate?.paperViewDidRequestExit(self)
        case 49:                       // space
            sheet.flap()
        case 5:                        // g
            sheet.gravity = sheet.gravity > 0 ? 0 : PaperView.gravityStrength
        case 15:                       // r
            sheet.reset()
        default:
            super.keyDown(with: event)
        }
    }
}
