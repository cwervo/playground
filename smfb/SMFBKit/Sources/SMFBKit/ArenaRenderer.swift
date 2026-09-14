#if canImport(CoreGraphics) && canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation

/// Which layers to draw. The watch gets the arena and a bare brain; larger
/// screens get labels, a spike sparkline and a stats line.
public struct ArenaStyle: Sendable {
    public var showBrain = true
    public var showLabels = true
    public var showSparkline = true
    public var showStats = true
    /// Brain panel width as a fraction of the arena width.
    public var brainPanelFraction: CGFloat = 0.30
    /// Mouse body length as a fraction of the arena width.
    public var mouseScale: CGFloat = 0.075
    public var textScale: CGFloat = 1

    public init() {}

    public static let watch: ArenaStyle = {
        var s = ArenaStyle()
        s.showLabels = false; s.showSparkline = false; s.showStats = false
        s.brainPanelFraction = 0.42; s.mouseScale = 0.16
        return s
    }()
    public static let phone: ArenaStyle = {
        var s = ArenaStyle()
        s.brainPanelFraction = 0.46; s.mouseScale = 0.11; s.textScale = 0.9
        return s
    }()
    public static let television: ArenaStyle = {
        var s = ArenaStyle()
        s.brainPanelFraction = 0.26; s.mouseScale = 0.06; s.textScale = 1.6
        return s
    }()
    public static let desktop = ArenaStyle()
}

/// Pure CoreGraphics. Called with a y-down context (SwiftUI's `Canvas` on
/// every platform); a y-up context is flipped on entry so the same code runs
/// inside an `NSView.draw(_:)` too.
public enum ArenaRenderer {
    struct RGBA { var r: CGFloat; var g: CGFloat; var b: CGFloat; var a: CGFloat = 1 }

    static let floorColor    = RGBA(r: 0.93, g: 0.89, b: 0.80)
    static let floorGrain    = RGBA(r: 0.80, g: 0.74, b: 0.62, a: 0.35)
    static let wallColor     = RGBA(r: 0.42, g: 0.33, b: 0.24)
    static let furColor      = RGBA(r: 0.56, g: 0.55, b: 0.58)
    static let furShade      = RGBA(r: 0.40, g: 0.39, b: 0.43)
    static let earColor      = RGBA(r: 0.93, g: 0.68, b: 0.70)
    static let noseColor     = RGBA(r: 0.85, g: 0.42, b: 0.48)
    static let crumbColor    = RGBA(r: 0.62, g: 0.42, b: 0.20)
    static let crumbDark     = RGBA(r: 0.45, g: 0.29, b: 0.12)
    static let plumeColor    = RGBA(r: 0.95, g: 0.70, b: 0.25)
    static let inkColor      = RGBA(r: 0.16, g: 0.13, b: 0.10)
    static let panelColor    = RGBA(r: 0.10, g: 0.09, b: 0.12, a: 0.86)
    static let neuronIdle    = RGBA(r: 0.35, g: 0.36, b: 0.48)
    static let neuronHot     = RGBA(r: 1.00, g: 0.80, b: 0.25)
    static let neuronInhib   = RGBA(r: 0.45, g: 0.70, b: 1.00)
    static let edgeColor     = RGBA(r: 0.55, g: 0.55, b: 0.70, a: 0.30)
    static let labelColor    = RGBA(r: 0.85, g: 0.85, b: 0.90)

    // MARK: - Entry point

    public static func draw(_ s: WorldSnapshot, in ctx: CGContext, rect: CGRect, style: ArenaStyle,
                            cursor: CGPoint? = nil, now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        ctx.saveGState()
        if ctx.ctm.d > 0 {                 // y-up host: flip to y-down
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        ctx.translateBy(x: rect.minX, y: rect.minY)
        let W = rect.width
        let unit = W                       // world width == 1
        let arena = CGRect(x: 0, y: 0, width: W, height: rect.height)

        drawFloor(ctx, arena, now: now)
        for pellet in s.food { drawPlume(ctx, pellet, unit: unit, now: now) }
        for pellet in s.food { drawCrumbs(ctx, pellet, unit: unit) }
        drawMouse(ctx, s.mouse, unit: unit, length: W * style.mouseScale, now: now)
        if let c = cursor { drawCursor(ctx, CGPoint(x: c.x * unit, y: c.y * unit), size: W * 0.03, now: now) }
        drawWalls(ctx, arena, bumpLeft: s.bumpLeft, bumpRight: s.bumpRight, mouse: s.mouse, unit: unit)

        if style.showBrain {
            let pw = W * style.brainPanelFraction
            let ph = pw * 0.78
            let panel = CGRect(x: W - pw - 8, y: 8, width: pw, height: ph)
            drawBrainPanel(ctx, panel, s, style: style)
        }
        if style.showStats {
            let line = String(format: "%@ · %d neurons · %d synapses · %.1fk steps/s · crumbs eaten %d",
                              s.kernelName.uppercased(), s.neuronCount, s.synapseCount,
                              s.stepsPerSecond / 1000, s.pelletsEaten)
            drawText(line, at: CGPoint(x: 10, y: rect.height - 10), size: 11 * style.textScale,
                     color: inkColor, align: .left, baseline: .bottom, in: ctx)
            if s.paused {
                drawText("PAUSED", at: CGPoint(x: W / 2, y: rect.height / 2), size: 28 * style.textScale,
                         color: RGBA(r: 0.16, g: 0.13, b: 0.10, a: 0.55), align: .center, baseline: .middle, in: ctx)
            }
        }
        ctx.restoreGState()
    }

    // MARK: - Arena

    static func drawFloor(_ ctx: CGContext, _ r: CGRect, now: TimeInterval) {
        set(fill: floorColor, ctx); ctx.fill(r)
        // a little cork grain, deterministic so it doesn't shimmer
        set(fill: floorGrain, ctx)
        var seed: UInt32 = 0x9E37_79B9
        let n = Int(r.width * r.height / 2600) + 20
        for _ in 0..<n {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let x = CGFloat(seed >> 8 & 0xFFFF) / 65535 * r.width
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let y = CGFloat(seed >> 8 & 0xFFFF) / 65535 * r.height
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let d = 1.5 + CGFloat(seed >> 8 & 0xFF) / 255 * 3
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d * 0.6))
        }
    }

    static func drawWalls(_ ctx: CGContext, _ r: CGRect, bumpLeft: Float, bumpRight: Float,
                          mouse: MouseState, unit: CGFloat) {
        set(stroke: wallColor, ctx)
        ctx.setLineWidth(max(3, unit * 0.008))
        ctx.stroke(r.insetBy(dx: 1.5, dy: 1.5))
        if bumpLeft > 0 || bumpRight > 0 {
            // flash the wall segment nearest the nose
            let nx = CGFloat(mouse.x) * unit, ny = CGFloat(mouse.y) * unit
            let dists = [nx, r.width - nx, ny, r.height - ny]
            let side = dists.indices.min { dists[$0] < dists[$1] } ?? 0
            set(fill: RGBA(r: 0.95, g: 0.55, b: 0.30, a: 0.35), ctx)
            let t: CGFloat = max(6, unit * 0.02)
            let seg: CGRect
            switch side {
            case 0: seg = CGRect(x: 0, y: ny - unit * 0.08, width: t, height: unit * 0.16)
            case 1: seg = CGRect(x: r.width - t, y: ny - unit * 0.08, width: t, height: unit * 0.16)
            case 2: seg = CGRect(x: nx - unit * 0.08, y: 0, width: unit * 0.16, height: t)
            default: seg = CGRect(x: nx - unit * 0.08, y: r.height - t, width: unit * 0.16, height: t)
            }
            ctx.fill(seg)
        }
    }

    static func drawPlume(_ ctx: CGContext, _ p: FoodPellet, unit: CGFloat, now: TimeInterval) {
        let cx = CGFloat(p.x) * unit, cy = CGFloat(p.y) * unit
        let pulse = 0.5 + 0.5 * sin(now * 1.7 + Double(p.x * 13 + p.y * 7))
        let rings = 3
        for i in 0..<rings {
            let f = (CGFloat(i) + CGFloat(pulse)) / CGFloat(rings)
            let rad = unit * (0.05 + 0.20 * f) * CGFloat(0.4 + 0.6 * p.amount)
            let a = CGFloat(p.amount) * 0.10 * (1 - f)
            set(stroke: RGBA(r: plumeColor.r, g: plumeColor.g, b: plumeColor.b, a: a), ctx)
            ctx.setLineWidth(max(1, unit * 0.004))
            ctx.strokeEllipse(in: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2))
        }
    }

    static func drawCrumbs(_ ctx: CGContext, _ p: FoodPellet, unit: CGFloat) {
        let cx = CGFloat(p.x) * unit, cy = CGFloat(p.y) * unit
        let base = unit * 0.012 * CGFloat(0.35 + 0.65 * max(0, p.amount))
        let offsets: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 1.4), (1.3, -0.6, 1.0), (-1.1, 0.9, 0.9), (0.4, 1.4, 0.7), (-1.4, -1.1, 0.6)]
        let visible = Int(ceil(Double(offsets.count) * Double(max(0.2, p.amount))))
        for (i, o) in offsets.prefix(visible).enumerated() {
            let r = base * o.2
            set(fill: i % 2 == 0 ? crumbColor : crumbDark, ctx)
            ctx.fillEllipse(in: CGRect(x: cx + o.0 * base - r, y: cy + o.1 * base - r, width: 2 * r, height: 2 * r))
        }
    }

    static func drawCursor(_ ctx: CGContext, _ c: CGPoint, size: CGFloat, now: TimeInterval) {
        let pulse = CGFloat(0.85 + 0.15 * sin(now * 5))
        let r = size * pulse
        set(stroke: RGBA(r: 0.2, g: 0.45, b: 0.9, a: 0.9), ctx)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.move(to: CGPoint(x: c.x - r * 1.5, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + r * 1.5, y: c.y))
        ctx.move(to: CGPoint(x: c.x, y: c.y - r * 1.5)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + r * 1.5))
        ctx.strokePath()
    }

    // MARK: - The mouse

    /// A top-down mouse, drawn facing +x and then rotated to its heading.
    static func drawMouse(_ ctx: CGContext, _ m: MouseState, unit: CGFloat, length L: CGFloat, now: TimeInterval) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(m.x) * unit, y: CGFloat(m.y) * unit)
        ctx.rotate(by: CGFloat(m.heading))

        // shadow
        set(fill: RGBA(r: 0, g: 0, b: 0, a: 0.16), ctx)
        ctx.fillEllipse(in: CGRect(x: -L * 0.50, y: -L * 0.22 + L * 0.05, width: L * 0.95, height: L * 0.46))

        // tail: a wiggly curve trailing behind the body
        let wig = CGFloat(sin(Double(m.tailPhase)))
        set(stroke: noseColor, ctx)
        ctx.setLineWidth(max(1.5, L * 0.045))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: -L * 0.42, y: 0))
        ctx.addCurve(to: CGPoint(x: -L * 1.05, y: L * 0.10 * wig),
                     control1: CGPoint(x: -L * 0.65, y: -L * 0.22 * wig),
                     control2: CGPoint(x: -L * 0.85, y: L * 0.28 * wig))
        ctx.strokePath()

        // feet: four little ovals, front/back pairs out of phase
        let g = Double(m.gaitPhase)
        let stride = L * 0.08 * CGFloat(min(1, m.speed * 8))
        set(fill: furShade, ctx)
        let feet: [(CGFloat, CGFloat)] = [(0.18, -0.26), (0.18, 0.26), (-0.22, -0.24), (-0.22, 0.24)]
        for (i, (fx, fy)) in feet.enumerated() {
            let phase = g + (i == 0 || i == 3 ? 0 : Double.pi)
            let dx = stride * CGFloat(sin(phase))
            ctx.fillEllipse(in: CGRect(x: L * fx + dx - L * 0.05, y: L * fy - L * 0.035, width: L * 0.10, height: L * 0.07))
        }

        // body and head
        let chew = CGFloat(m.eating) * CGFloat(0.5 + 0.5 * sin(now * 22)) * 0.06
        set(fill: furColor, ctx)
        ctx.fillEllipse(in: CGRect(x: -L * 0.50, y: -L * 0.24, width: L * 0.85, height: L * 0.48))
        ctx.fillEllipse(in: CGRect(x: L * 0.12, y: -L * (0.20 + chew), width: L * 0.50, height: L * (0.40 + 2 * chew)))
        set(fill: RGBA(r: 0.80, g: 0.79, b: 0.82), ctx)      // belly highlight
        ctx.fillEllipse(in: CGRect(x: -L * 0.30, y: -L * 0.10, width: L * 0.45, height: L * 0.20))

        // ears
        for sy in [-1.0, 1.0] as [CGFloat] {
            set(fill: furShade, ctx)
            ctx.fillEllipse(in: CGRect(x: L * 0.16, y: sy * L * 0.24 - L * 0.11, width: L * 0.22, height: L * 0.22))
            set(fill: earColor, ctx)
            ctx.fillEllipse(in: CGRect(x: L * 0.19, y: sy * L * 0.24 - L * 0.075, width: L * 0.15, height: L * 0.15))
        }

        // eyes, nose, whiskers
        set(fill: inkColor, ctx)
        for sy in [-1.0, 1.0] as [CGFloat] {
            ctx.fillEllipse(in: CGRect(x: L * 0.42, y: sy * L * 0.09 - L * 0.03, width: L * 0.06, height: L * 0.06))
        }
        set(fill: noseColor, ctx)
        ctx.fillEllipse(in: CGRect(x: L * 0.58, y: -L * 0.035, width: L * 0.08, height: L * 0.07))
        set(stroke: RGBA(r: 0.25, g: 0.22, b: 0.20, a: 0.8), ctx)
        ctx.setLineWidth(max(0.8, L * 0.015))
        for sy in [-1.0, 1.0] as [CGFloat] {
            for k in 0..<3 {
                let a = sy * (0.35 + 0.35 * CGFloat(k))
                ctx.move(to: CGPoint(x: L * 0.55, y: sy * L * 0.02))
                ctx.addLine(to: CGPoint(x: L * 0.55 + L * 0.30 * cos(a), y: sy * L * 0.02 + L * 0.30 * sin(a)))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Brain schematic

    /// Schematic positions (0...1) of each region inside the panel, antennae
    /// at the bottom (the fly faces down the page) and descending neurons at
    /// the top where the neck connective would leave the brain.
    static let layout: [CGPoint] = [
        CGPoint(x: 0.14, y: 0.90), CGPoint(x: 0.86, y: 0.90),   // ORN
        CGPoint(x: 0.28, y: 0.74), CGPoint(x: 0.72, y: 0.74),   // AL
        CGPoint(x: 0.27, y: 0.40), CGPoint(x: 0.73, y: 0.40),   // KC
        CGPoint(x: 0.15, y: 0.30), CGPoint(x: 0.85, y: 0.30),   // APL
        CGPoint(x: 0.36, y: 0.56), CGPoint(x: 0.64, y: 0.56),   // MBON+
        CGPoint(x: 0.24, y: 0.58), CGPoint(x: 0.76, y: 0.58),   // MBON-
        CGPoint(x: 0.10, y: 0.62), CGPoint(x: 0.90, y: 0.62),   // LH
        CGPoint(x: 0.50, y: 0.44),                              // CX
        CGPoint(x: 0.40, y: 0.14), CGPoint(x: 0.60, y: 0.14),   // DN L/R
        CGPoint(x: 0.50, y: 0.06),                              // DN fwd
        CGPoint(x: 0.04, y: 0.78), CGPoint(x: 0.96, y: 0.78),   // MECH
        CGPoint(x: 0.50, y: 0.26),                              // DAN
    ]

    /// The main pathways, for the faint wiring diagram behind the nodes.
    static let wiring: [(BrainRegion, BrainRegion, Bool)] = [   // (pre, post, inhibitory)
        (.ornLeft, .antennalLobeLeft, false), (.ornRight, .antennalLobeRight, false),
        (.antennalLobeLeft, .kenyonLeft, false), (.antennalLobeRight, .kenyonRight, false),
        (.antennalLobeLeft, .lateralHornLeft, false), (.antennalLobeRight, .lateralHornRight, false),
        (.kenyonLeft, .aplLeft, false), (.kenyonRight, .aplRight, false),
        (.aplLeft, .kenyonLeft, true), (.aplRight, .kenyonRight, true),
        (.kenyonLeft, .mbonApproachLeft, false), (.kenyonRight, .mbonApproachRight, false),
        (.kenyonLeft, .mbonAvoidLeft, false), (.kenyonRight, .mbonAvoidRight, false),
        (.lateralHornLeft, .descendingLeft, false), (.lateralHornRight, .descendingRight, false),
        (.lateralHornLeft, .centralComplex, false), (.lateralHornRight, .centralComplex, false),
        (.mbonApproachLeft, .descendingLeft, false), (.mbonApproachRight, .descendingRight, false),
        (.mbonAvoidLeft, .descendingRight, false), (.mbonAvoidRight, .descendingLeft, false),
        (.centralComplex, .descendingForward, false), (.centralComplex, .descendingLeft, false), (.centralComplex, .descendingRight, false),
        (.mechLeft, .descendingRight, false), (.mechRight, .descendingLeft, false),
        (.dopamine, .mbonAvoidLeft, true), (.dopamine, .mbonAvoidRight, true),
    ]

    static let regionSizes: [CGFloat] = [
        64, 64, 32, 32, 512, 512, 4, 4, 8, 8, 8, 8, 64, 64, 256, 16, 16, 16, 32, 32, 16,
    ]

    static func drawBrainPanel(_ ctx: CGContext, _ r: CGRect, _ s: WorldSnapshot, style: ArenaStyle) {
        ctx.saveGState()
        let path = CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)
        set(fill: panelColor, ctx)
        ctx.addPath(path); ctx.fillPath()

        // brain outline: two lobes
        set(stroke: RGBA(r: 0.5, g: 0.5, b: 0.65, a: 0.25), ctx)
        ctx.setLineWidth(1)
        let lobe = CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.20, width: r.width * 0.88, height: r.height * 0.66)
        ctx.strokeEllipse(in: lobe)

        func pos(_ region: BrainRegion) -> CGPoint {
            let p = layout[region.rawValue]
            return CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
        }

        // wiring
        ctx.setLineWidth(max(0.8, r.width * 0.004))
        for (pre, post, inh) in wiring {
            let a = pos(pre), b = pos(post)
            let hot = CGFloat(min(1, s.rate(of: pre) / 2.5))
            let c = inh ? neuronInhib : neuronHot
            set(stroke: RGBA(r: c.r, g: c.g, b: c.b, a: 0.10 + 0.55 * hot), ctx)
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        }

        // nodes
        for region in BrainRegion.allCases {
            let p = pos(region)
            let rate = s.rate(of: region)
            let hot = CGFloat(min(1, rate / 3))
            let base = r.width * (0.018 + 0.006 * log2(max(1, regionSizes[region.rawValue] / 4)))
            let rad = base * (1 + 0.35 * hot)
            let inhib = region == .aplLeft || region == .aplRight
            let c = inhib ? neuronInhib : neuronHot
            // glow halo
            if hot > 0.05 {
                set(fill: RGBA(r: c.r, g: c.g, b: c.b, a: 0.30 * hot), ctx)
                ctx.fillEllipse(in: CGRect(x: p.x - rad * 1.8, y: p.y - rad * 1.8, width: rad * 3.6, height: rad * 3.6))
            }
            set(fill: mix(neuronIdle, c, hot), ctx)
            ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
            if style.showLabels {
                let above = region == .ornLeft || region == .ornRight || region == .mechLeft || region == .mechRight
                drawText(region.name, at: CGPoint(x: p.x, y: p.y + (above ? -rad - 2 : rad + 2)),
                         size: max(7, r.width * 0.032) * style.textScale, color: labelColor,
                         align: .center, baseline: above ? .bottom : .top, in: ctx)
            }
        }

        // sparkline of network activity
        if style.showSparkline, !s.activityHistory.isEmpty {
            let box = CGRect(x: r.minX + 8, y: r.maxY - r.height * 0.14, width: r.width * 0.42, height: r.height * 0.10)
            let peak = max(1, s.activityHistory.max() ?? 1)
            set(stroke: RGBA(r: 0.9, g: 0.75, b: 0.35, a: 0.9), ctx)
            ctx.setLineWidth(1)
            for (i, v) in s.activityHistory.enumerated() {
                let x = box.minX + CGFloat(i) / CGFloat(s.activityHistory.count - 1) * box.width
                let y = box.maxY - CGFloat(v / peak) * box.height
                if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.strokePath()
            if style.showLabels {
                drawText("spikes / step", at: CGPoint(x: box.minX, y: box.maxY + 2), size: max(7, r.width * 0.03) * style.textScale,
                         color: RGBA(r: 0.7, g: 0.7, b: 0.78), align: .left, baseline: .top, in: ctx)
            }
        }

        // odor and motor bars along the bottom right
        let bars: [(String, Float, RGBA)] = [
            ("odor L", s.odorLeft, plumeColor), ("odor R", s.odorRight, plumeColor),
            ("turn L", s.descendingLeft, neuronHot), ("turn R", s.descendingRight, neuronHot),
            ("fwd", s.descendingForward, neuronHot),
        ]
        let bw = r.width * 0.07, gap = r.width * 0.012
        var bx = r.maxX - 8 - CGFloat(bars.count) * (bw + gap)
        let by = r.maxY - 8, bh = r.height * 0.13
        for (label, value, color) in bars {
            let h = bh * CGFloat(min(1, value))
            set(fill: RGBA(r: 1, g: 1, b: 1, a: 0.08), ctx)
            ctx.fill(CGRect(x: bx, y: by - bh, width: bw, height: bh))
            set(fill: color, ctx)
            ctx.fill(CGRect(x: bx, y: by - h, width: bw, height: h))
            if style.showLabels {
                drawText(label, at: CGPoint(x: bx + bw / 2, y: by - bh - 2), size: max(6, r.width * 0.026) * style.textScale,
                         color: RGBA(r: 0.7, g: 0.7, b: 0.78), align: .center, baseline: .bottom, in: ctx)
            }
            bx += bw + gap
        }
        ctx.restoreGState()
    }

    // MARK: - Helpers

    static func set(fill c: RGBA, _ ctx: CGContext) { ctx.setFillColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
    static func set(stroke c: RGBA, _ ctx: CGContext) { ctx.setStrokeColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
    static func mix(_ a: RGBA, _ b: RGBA, _ t: CGFloat) -> RGBA {
        RGBA(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t, a: a.a + (b.a - a.a) * t)
    }

    enum Align { case left, center, right }
    enum Baseline { case top, middle, bottom }

    /// CoreText into a y-down context: flip locally so glyphs stand upright.
    static func drawText(_ text: String, at p: CGPoint, size: CGFloat, color: RGBA,
                         align: Align, baseline: Baseline, in ctx: CGContext) {
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil)
        let cg = CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: cg]
        guard let str = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(str)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let x: CGFloat
        switch align {
        case .left: x = p.x
        case .center: x = p.x - width / 2
        case .right: x = p.x - width
        }
        let baseY: CGFloat
        switch baseline {
        case .top: baseY = p.y + ascent
        case .middle: baseY = p.y + (ascent - descent) / 2
        case .bottom: baseY = p.y - descent
        }
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.translateBy(x: x, y: baseY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
#endif
