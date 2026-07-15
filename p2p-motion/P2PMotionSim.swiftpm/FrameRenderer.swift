import UIKit

// Renders the camera node's first-person 160x120 monochrome frame,
// mimicking the low-res grayscale imagery of the UW insect-scale camera.
enum FrameRenderer {
    static let width = 160.0
    static let height = 120.0
    static let horizon = 52.0
    static let fov = Double.pi / 3

    static func render(beetle: Beetle) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { rc in
            let ctx = rc.cgContext

            func gray(_ v: Double) -> CGColor {
                let c = CGFloat(max(0, min(1, v / 255)))
                return UIColor(white: c, alpha: 1).cgColor
            }

            // sky
            drawVerticalGradient(ctx, from: 200, to: 138, rect: CGRect(x: 0, y: 0, width: width, height: horizon))
            // ground
            drawVerticalGradient(ctx, from: 90, to: 38, rect: CGRect(x: 0, y: horizon, width: width, height: height - horizon))

            // objects, far to near (obstacles + the hub box)
            struct Obj { let x, y, r, d: Double; let isHub: Bool }
            var objs = Room.obstacles.map {
                Obj(x: $0.x, y: $0.y, r: $0.r, d: hypot(beetle.x - $0.x, beetle.y - $0.y), isHub: false)
            }
            objs.append(Obj(x: Room.hub.x, y: Room.hub.y, r: 26,
                            d: hypot(beetle.x - Room.hub.x, beetle.y - Room.hub.y), isHub: true))
            objs.sort { $0.d > $1.d }

            for o in objs {
                var rel = atan2(o.y - beetle.y, o.x - beetle.x) - beetle.heading
                while rel > .pi { rel -= 2 * .pi }
                while rel < -.pi { rel += 2 * .pi }
                guard abs(rel) <= fov / 2 + 0.35 else { continue }
                let x = width / 2 + (rel / (fov / 2)) * (width / 2)
                let s = max(3, min(90, o.r * 1500 / (o.d * o.d + 40) + o.r * 26 / (o.d + 8)))
                let shade = max(40, min(190, 200 - o.d * 0.35))
                ctx.setFillColor(gray(shade))
                if o.isHub {
                    ctx.fill(CGRect(x: x - s * 0.7, y: horizon - s * 0.9, width: s * 1.4, height: s * 0.9))
                    ctx.fill(CGRect(x: x - 1, y: horizon - s * 1.6, width: 2, height: s * 0.7))
                    let ar = max(1.5, s * 0.12)
                    ctx.fillEllipse(in: CGRect(x: x - ar, y: horizon - s * 1.6 - ar, width: 2 * ar, height: 2 * ar))
                } else {
                    ctx.fillEllipse(in: CGRect(x: x - s, y: horizon - s * 0.72, width: 2 * s, height: 2 * s * 0.72))
                }
            }

            // sensor grain: cheap noise speckles instead of per-pixel math
            for _ in 0..<1400 {
                let v = Double.random(in: 0...255)
                ctx.setFillColor(UIColor(white: CGFloat(v / 255), alpha: 0.14).cgColor)
                ctx.fill(CGRect(x: .random(in: 0..<width), y: .random(in: 0..<height), width: 1, height: 1))
            }

            // vignette
            let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.55).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(grad,
                                       startCenter: CGPoint(x: width / 2, y: height / 2), startRadius: 30,
                                       endCenter: CGPoint(x: width / 2, y: height / 2), endRadius: 110,
                                       options: .drawsAfterEndLocation)
            }
        }
    }

    private static func drawVerticalGradient(_ ctx: CGContext, from: Double, to: Double, rect: CGRect) {
        let colors = [UIColor(white: CGFloat(from / 255), alpha: 1).cgColor,
                      UIColor(white: CGFloat(to / 255), alpha: 1).cgColor] as CFArray
        guard let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: rect.minY),
                               end: CGPoint(x: 0, y: rect.maxY),
                               options: [])
        ctx.restoreGState()
    }
}
