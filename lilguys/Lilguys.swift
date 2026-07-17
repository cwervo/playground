// Lilguys — tiny desktop critters that live on your screen.
//
// Single-file prototype daemon: no .app bundle, no Accessibility or Screen
// Recording permissions. Window geometry (position/size of every on-screen
// window, front-to-back) comes from CGWindowListCopyWindowInfo, which is
// readable without any TCC prompt. Rendering is one full-screen, transparent,
// click-through overlay window driven by a single Metal fragment shader that
// draws every lilguy as a 2D signed-distance-field.
//
// Build & run:   swiftc -O Lilguys.swift -o lilguysd && ./lilguysd [herd.lg]
// (or just:      ./run.sh)
//
// Herd file (.lg) format — one lilguy per line:
//   fuzzball
//   grass x=0.25
//   dandelion x=0.6
// `x` is a fraction of screen width. Lines starting with # are comments.

import AppKit
import MetalKit
import simd

// MARK: - Shader source (compiled at runtime, so we stay a single file)

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;   // points
    float  scale;        // backing scale (pixels per point)
    float  time;
    int    count;
    int    pad0;
    float2 pad1;
};

// One lilguy, packed into three float4s (matches GuyUniform in Swift).
//   a: x, y, size (radius or height), sway
//   b: blink (1 open .. 0 shut), squashX, squashY, growth
//   c: type, seed, lifeAlpha, aux (fuzzball: look dir, dandelion: fall angle)
struct Guy {
    float4 a;
    float4 b;
    float4 c;
};

struct VOut { float4 pos [[position]]; };

vertex VOut vmain(uint vid [[vertex_id]]) {
    // Full-screen triangle.
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
    return v;
}

// Blinkable black eye: an ellipse whose height collapses as blink -> 0.
float eyeMask(float2 p, float2 c, float r, float blink) {
    float2 q = p - c;
    q.y /= max(blink, 0.04);
    return smoothstep(0.75, -0.75, length(q) - r);
}

float4 drawFuzzball(float2 p, Guy g, float t) {
    float2 c = g.a.xy;
    float r = g.a.z;
    float2 d = p - c;
    d.x /= g.b.y;
    d.y /= g.b.z;
    float ang = atan2(d.y, d.x);
    float len = length(d);
    // Two octaves of angular noise make the hairy metaball rim.
    float hair  = fbm(float2(ang * 4.0 + g.c.y * 7.0, t * 0.8)) - 0.5;
    float hair2 = fbm(float2(ang * 15.0 + g.c.y * 13.0, len * 0.12 + t * 1.4)) - 0.5;
    float rr = r * (1.0 + 0.15 * hair + 0.24 * hair2 * smoothstep(r * 0.4, r * 1.2, len));
    float body = smoothstep(2.5, -2.5, len - rr);
    float3 col = mix(float3(0.90, 0.91, 0.96), float3(1.0), smoothstep(r, 0.0, len));
    // Eyes drift toward the direction of travel.
    float2 look = float2(clamp(g.c.w, -1.0, 1.0), -0.2) * r * 0.14;
    float2 eL = c + float2(-0.32, -0.16) * r + look;
    float2 eR = c + float2( 0.32, -0.16) * r + look;
    float er = r * 0.155;
    float e = max(eyeMask(p, eL, er, g.b.x), eyeMask(p, eR, er, g.b.x));
    col = mix(col, float3(0.05), e);
    return float4(col, body * g.c.z);
}

float4 drawGrass(float2 p, Guy g, float t) {
    float2 base = g.a.xy;                     // feet (bottom of the blade)
    float h = g.a.z * g.b.w * g.b.z;          // height * growth * crouch
    if (h < 2.0) return float4(0.0);
    float sway = g.a.w;
    float yUp = base.y - p.y;
    float u = yUp / h;
    if (u < -0.06 || u > 1.15) return float4(0.0);
    float uc = clamp(u, 0.0, 1.0);
    float bend = sway * uc * uc * h * 0.35;
    float xo = (p.x - base.x) - bend;
    float w = mix(5.0, 1.3, uc) * (2.0 - g.b.z); // taper; widen while crouching
    float dist = max(abs(xo) - w, yUp - h);
    float a = smoothstep(1.5, -1.5, dist) * smoothstep(-3.0, 0.0, yUp);
    float3 col = mix(float3(0.18, 0.52, 0.16), float3(0.44, 0.84, 0.30), uc);
    // Small beady eyes near the tip.
    float ue = 0.80;
    float2 ec = float2(base.x + sway * ue * ue * h * 0.35, base.y - ue * h);
    float e = max(eyeMask(p, ec + float2(-2.4, 0.0), 1.7, g.b.x),
                  eyeMask(p, ec + float2( 2.4, 0.0), 1.7, g.b.x));
    col = mix(col, float3(0.03), e);
    return float4(col, a * g.c.z);
}

float4 drawDandelion(float2 p, Guy g, float t) {
    float2 base = g.a.xy;
    // Fall over by rotating the whole coordinate frame around the base.
    float ang = g.c.w;
    float2 q = p - base;
    float ca = cos(ang), sa = sin(ang);
    p = base + float2(ca * q.x + sa * q.y, -sa * q.x + ca * q.y);
    float h = g.a.z * g.b.w;
    if (h < 3.0) return float4(0.0);
    float sway = g.a.w;
    float yUp = base.y - p.y;
    float u = clamp(yUp / h, 0.0, 1.0);
    float bend = sway * u * u * h * 0.25;
    float xo = (p.x - base.x) - bend;
    float stalkD = max(abs(xo) - mix(2.4, 1.2, u), max(yUp - h, -yUp - 2.0));
    float stalkA = smoothstep(1.2, -1.2, stalkD);
    float3 col = float3(0.28, 0.58, 0.20);
    float a = stalkA;
    // Fuzzy seed head.
    float2 headC = float2(base.x + sway * h * 0.25, base.y - h);
    float hr = max(g.a.z * 0.17 * g.b.w, 2.0);
    float2 hd = p - headC;
    float hang = atan2(hd.y, hd.x);
    float fuzz = fbm(float2(hang * 6.0 + g.c.y * 11.0, t * 0.7)) - 0.5;
    float hrr = hr * (1.0 + 0.35 * fuzz);
    float headA = smoothstep(2.0, -2.0, length(hd) - hrr) * 0.95;
    col = mix(col, float3(0.97, 0.97, 1.0), headA);
    a = max(a, headA);
    float er = hr * 0.14 + 0.8;
    float e = max(eyeMask(p, headC + float2(-hr * 0.32, -hr * 0.05), er, g.b.x),
                  eyeMask(p, headC + float2( hr * 0.32, -hr * 0.05), er, g.b.x));
    col = mix(col, float3(0.03), e);
    return float4(col, a * g.c.z);
}

float4 drawSeed(float2 p, Guy g, float t) {
    float2 c = g.a.xy;
    float r = g.a.z;
    float2 d = p - c;
    float ang = atan2(d.y, d.x);
    float rr = r * (1.0 + 0.5 * (fbm(float2(ang * 3.0 + g.c.y * 9.0, t * 1.1)) - 0.5));
    float a = smoothstep(1.5, -1.5, length(d) - rr) * 0.9;
    return float4(float3(0.98), a * g.c.z);
}

fragment float4 fmain(VOut in [[stage_in]],
                      constant Uniforms &u [[buffer(0)]],
                      constant Guy *guys  [[buffer(1)]]) {
    float2 p = in.pos.xy / u.scale;   // work in points, top-left origin
    float3 col = float3(0.0);
    float alpha = 0.0;
    for (int i = 0; i < u.count; i++) {
        Guy g = guys[i];
        int ty = int(g.c.x + 0.5);
        // Cheap bounding-box reject before any noise work.
        float2 gc = g.a.xy;
        float bound = g.a.z * 2.0 + 60.0;
        if (ty == 1 || ty == 2) { gc.y -= g.a.z * 0.6; bound = g.a.z * 1.4 + 80.0; }
        if (abs(p.x - gc.x) > bound || abs(p.y - gc.y) > bound) continue;
        float4 s;
        if      (ty == 0) s = drawFuzzball(p, g, u.time);
        else if (ty == 1) s = drawGrass(p, g, u.time);
        else if (ty == 2) s = drawDandelion(p, g, u.time);
        else              s = drawSeed(p, g, u.time);
        col = mix(col, s.rgb, s.a);
        alpha = alpha + s.a * (1.0 - alpha);
    }
    return float4(col, alpha);
}
"""

// MARK: - Uniform layouts (must match the MSL structs above)

struct FrameUniforms {
    var resolution: SIMD2<Float>
    var scale: Float
    var time: Float
    var count: Int32
    var pad0: Int32 = 0
    var pad1: SIMD2<Float> = .zero
}

struct GuyUniform {
    var a: SIMD4<Float>
    var b: SIMD4<Float>
    var c: SIMD4<Float>
}

let maxGuys = 64

// MARK: - Window observation (permission-free)

struct DesktopWindows {
    var rects: [CGRect] = []        // normal-layer windows, front to back
    var frontmost: CGRect? = nil
    var dock: CGRect? = nil

    static func snapshot(excluding ourWindow: Int) -> DesktopWindows {
        var out = DesktopWindows()
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return out
        }
        for info in list {
            guard let num = info[kCGWindowNumber as String] as? Int, num != ourWindow,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if owner == "Dock" {
                // The Dock bar is long and thin, hugging one screen edge; the
                // Dock process also owns tiny indicators and (sometimes)
                // screen-sized windows, which we must not mistake for it.
                if (bounds.height < 250 && bounds.width > 300) ||
                   (bounds.width < 250 && bounds.height > 300) {
                    out.dock = bounds
                }
                continue
            }
            guard layer == 0, alpha > 0.05,
                  bounds.width > 120, bounds.height > 80 else { continue }
            out.rects.append(bounds)
            if out.frontmost == nil { out.frontmost = bounds }
        }
        return out
    }
}

// MARK: - A* over "sticky" surfaces
// The fuzzball may only occupy grid cells that hug a surface: the screen
// edges, or the border of any window. That makes paths naturally roll along
// the floor, up screen sides, and up window edges toward the stoplights.

struct SurfaceGrid {
    let cell: CGFloat = 36
    let cols: Int
    let rows: Int
    var passable: [Bool]
    let screen: CGRect

    init(screen: CGRect, windows: [CGRect]) {
        self.screen = screen
        cols = max(4, Int(ceil(screen.width / cell)))
        rows = max(4, Int(ceil(screen.height / cell)))
        passable = Array(repeating: false, count: cols * rows)
        let stick: CGFloat = cell * 1.1
        for r in 0..<rows {
            for c in 0..<cols {
                let p = CGPoint(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
                var ok = false
                // Screen edges are always climbable.
                if p.x < stick || p.x > screen.width - stick ||
                   p.y < stick || p.y > screen.height - stick {
                    ok = true
                }
                if !ok {
                    for w in windows where Self.distanceToEdge(p, w) < stick {
                        ok = true
                        break
                    }
                }
                passable[r * cols + c] = ok
            }
        }
    }

    static func distanceToEdge(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(max(r.minX - p.x, 0), p.x - r.maxX)
        let dy = max(max(r.minY - p.y, 0), p.y - r.maxY)
        let outside = hypot(dx, dy)
        if outside > 0 { return outside }
        let inx = min(p.x - r.minX, r.maxX - p.x)
        let iny = min(p.y - r.minY, r.maxY - p.y)
        return min(inx, iny)
    }

    func cellFor(_ p: CGPoint) -> (Int, Int) {
        (min(cols - 1, max(0, Int(p.x / cell))), min(rows - 1, max(0, Int(p.y / cell))))
    }

    func center(_ c: Int, _ r: Int) -> CGPoint {
        CGPoint(x: (CGFloat(c) + 0.5) * cell, y: (CGFloat(r) + 0.5) * cell)
    }

    func isPassable(_ c: Int, _ r: Int) -> Bool {
        c >= 0 && r >= 0 && c < cols && r < rows && passable[r * cols + c]
    }

    // Nearest passable cell to a point (spiral search).
    func nearestPassable(to p: CGPoint) -> (Int, Int)? {
        let (c0, r0) = cellFor(p)
        if isPassable(c0, r0) { return (c0, r0) }
        for radius in 1...8 {
            for dr in -radius...radius {
                for dc in -radius...radius where abs(dr) == radius || abs(dc) == radius {
                    if isPassable(c0 + dc, r0 + dr) { return (c0 + dc, r0 + dr) }
                }
            }
        }
        return nil
    }

    func aStar(from: CGPoint, to: CGPoint) -> [CGPoint]? {
        guard let s = nearestPassable(to: from), let g = nearestPassable(to: to) else { return nil }
        let n = cols * rows
        var gScore = Array(repeating: Float.infinity, count: n)
        var came = Array(repeating: -1, count: n)
        var closed = Array(repeating: false, count: n)
        func idx(_ c: Int, _ r: Int) -> Int { r * cols + c }
        func h(_ c: Int, _ r: Int) -> Float {
            let dx = Float(abs(c - g.0)), dy = Float(abs(r - g.1))
            return max(dx, dy) + 0.414 * min(dx, dy)
        }
        let start = idx(s.0, s.1)
        let goal = idx(g.0, g.1)
        gScore[start] = 0
        var open: [(f: Float, i: Int)] = [(h(s.0, s.1), start)]
        let moves: [(Int, Int, Float)] = [(1,0,1),(-1,0,1),(0,1,1),(0,-1,1),
                                          (1,1,1.414),(1,-1,1.414),(-1,1,1.414),(-1,-1,1.414)]
        while !open.isEmpty {
            var best = 0
            for k in 1..<open.count where open[k].f < open[best].f { best = k }
            let (_, cur) = open.remove(at: best)
            if closed[cur] { continue }
            closed[cur] = true
            if cur == goal { break }
            let cc = cur % cols, cr = cur / cols
            for (dc, dr, cost) in moves {
                let nc = cc + dc, nr = cr + dr
                guard isPassable(nc, nr) else { continue }
                let ni = idx(nc, nr)
                if closed[ni] { continue }
                let tentative = gScore[cur] + cost
                if tentative < gScore[ni] {
                    gScore[ni] = tentative
                    came[ni] = cur
                    open.append((tentative + h(nc, nr), ni))
                }
            }
        }
        guard closed[goal] else { return nil }
        var path: [CGPoint] = []
        var cur = goal
        while cur != -1 {
            path.append(center(cur % cols, cur / cols))
            cur = came[cur]
        }
        return path.reversed()
    }
}

// MARK: - Lilguys

enum GuyType: Int { case fuzzball = 0, grass = 1, dandelion = 2, seed = 3 }

enum DandelionState {
    case growing(elapsed: Double, duration: Double)
    case standing(remaining: Double)
    case falling(progress: Double, direction: CGFloat)
    case dead(fade: Double)
}

enum HopState {
    case grounded(crouchIn: Double)
    case crouching(elapsed: Double)
    case airborne
}

final class Guy {
    var type: GuyType
    var pos: CGPoint
    var vel = CGVector(dx: 0, dy: 0)
    var size: CGFloat
    var sway: Float = 0
    var blink: Float = 1
    var blinkTimer: Double = .random(in: 1...5)
    var blinkPhase: Double = -1        // -1 = not blinking
    var squashX: Float = 1
    var squashY: Float = 1
    var growth: Float = 1
    var life: Float = 1
    var noiseSeed: Float = .random(in: 0..<1)
    var aux: Float = 0                 // fuzzball: eye look; dandelion: fall angle
    var dead = false

    // Behavior state
    var hop: HopState = .grounded(crouchIn: .random(in: 0.3...1.5))
    var hopDir: CGFloat = Bool.random() ? 1 : -1
    var dandelion: DandelionState = .standing(remaining: .random(in: 90...240))
    var seedIsDandelion = false
    var seedDriftPhase: Double = .random(in: 0...(2 * .pi))
    var path: [CGPoint] = []
    var repathTimer: Double = 0
    var groupPhase: Float = 0

    init(type: GuyType, pos: CGPoint, size: CGFloat) {
        self.type = type
        self.pos = pos
        self.size = size
    }

    var uniform: GuyUniform {
        GuyUniform(
            a: SIMD4(Float(pos.x), Float(pos.y), Float(size), sway),
            b: SIMD4(blink, squashX, squashY, growth),
            c: SIMD4(Float(type.rawValue), noiseSeed, life, aux)
        )
    }
}

// MARK: - Simulation

final class Sim {
    var guys: [Guy] = []
    let screen: CGRect
    var windows = DesktopWindows()
    var windowPollTimer: Double = 0
    var time: Double = 0
    var ourWindowNumber = -1
    let gravity: CGFloat = 1400

    init(screen: CGRect, herd: [(String, [String: Double])]) {
        self.screen = screen
        for (kind, opts) in herd {
            let x = CGFloat(opts["x"] ?? .random(in: 0.1...0.9)) * screen.width
            switch kind {
            case "fuzzball":
                let g = Guy(type: .fuzzball, pos: CGPoint(x: x, y: screen.height - 30), size: opts["size"].map { CGFloat($0) } ?? 26)
                guys.append(g)
            case "grass":
                let g = Guy(type: .grass, pos: CGPoint(x: x, y: screen.height), size: opts["size"].map { CGFloat($0) } ?? .random(in: 55...85))
                guys.append(g)
            case "dandelion":
                let g = Guy(type: .dandelion, pos: CGPoint(x: x, y: screen.height), size: opts["size"].map { CGFloat($0) } ?? .random(in: 95...130))
                guys.append(g)
            default:
                fputs("lilguys: unknown lilguy kind '\(kind)' — skipping\n", stderr)
            }
        }
    }

    func groundY(atX x: CGFloat) -> CGFloat {
        if let d = windows.dock, d.minY > screen.height * 0.5, x > d.minX, x < d.maxX {
            return d.minY   // standing on top of the Dock
        }
        return screen.height
    }

    func update(dt rawDt: Double) {
        let dt = min(rawDt, 1.0 / 20.0)   // clamp huge frame gaps (sleep, etc.)
        time += dt
        updateDt = dt

        windowPollTimer -= dt
        if windowPollTimer <= 0 {
            windowPollTimer = 0.5
            windows = DesktopWindows.snapshot(excluding: ourWindowNumber)
        }

        updateWindGroups()

        var newborn: [Guy] = []
        for g in guys {
            updateBlink(g, dt: dt)
            switch g.type {
            case .fuzzball:  updateFuzzball(g, dt: dt)
            case .grass:     updateGrass(g, dt: dt)
            case .dandelion: updateDandelion(g, dt: dt, newborn: &newborn)
            case .seed:      updateSeed(g, dt: dt, newborn: &newborn)
            }
        }
        guys.removeAll { $0.dead }
        for g in newborn where guys.count < maxGuys { guys.append(g) }
    }

    // Eyes: 1 -> 0 -> 1 over ~0.28s, every few seconds.
    func updateBlink(_ g: Guy, dt: Double) {
        if g.blinkPhase >= 0 {
            g.blinkPhase += dt / 0.28
            if g.blinkPhase >= 1 {
                g.blinkPhase = -1
                g.blink = 1
                g.blinkTimer = .random(in: 2...6)
            } else {
                g.blink = Float(abs(cos(.pi * g.blinkPhase)))
            }
        } else {
            g.blinkTimer -= dt
            if g.blinkTimer <= 0 { g.blinkPhase = 0 }
        }
    }

    // Grass blades near each other share a sway phase, so clumps dance together.
    func updateWindGroups() {
        let grass = guys.filter { $0.type == .grass || $0.type == .dandelion }
            .sorted { $0.pos.x < $1.pos.x }
        var groupId = 0
        var lastX: CGFloat = -1e9
        let gust = Float(sin(time * 0.23) + 0.5 * sin(time * 0.531) + 0.3 * sin(time * 1.13))
        for g in grass {
            if g.pos.x - lastX > 170 { groupId += 1 }
            lastX = g.pos.x
            g.groupPhase = Float(groupId) * 1.1
            let amp: Float = g.type == .dandelion ? 0.35 : 0.6
            let target = amp * (0.5 + 0.35 * gust) * Float(sin(time * 1.6 + Double(g.groupPhase))) +
                         0.08 * Float(sin(time * 3.7 + Double(g.noiseSeed) * 20))
            g.sway += (target - g.sway) * Float(min(1, 4 * updateDt))
        }
    }
    private var updateDt: Double = 1.0 / 60.0

    // The climber: A* along sticky surfaces toward the frontmost window's
    // stoplight (close/minimize/maximize) cluster.
    func updateFuzzball(_ g: Guy, dt: Double) {
        let target: CGPoint
        if let front = windows.frontmost {
            target = CGPoint(x: front.minX + 40, y: front.minY + 16)
        } else {
            target = CGPoint(x: screen.width * 0.5, y: screen.height - g.size)
        }

        g.repathTimer -= dt
        let pathEnd = g.path.last
        let targetMoved = pathEnd.map { hypot($0.x - target.x, $0.y - target.y) > 60 } ?? true
        if g.repathTimer <= 0 || (targetMoved && g.repathTimer < 0.8) {
            g.repathTimer = 1.2
            let grid = SurfaceGrid(screen: screen, windows: windows.rects)
            if var p = grid.aStar(from: g.pos, to: target) {
                if !p.isEmpty { p[p.count - 1] = target }
                g.path = p
            }
        }

        let atRest: Bool
        if let next = g.path.first {
            let dx = next.x - g.pos.x, dy = next.y - g.pos.y
            let dist = hypot(dx, dy)
            let speed: CGFloat = 130
            if dist < 7 {
                g.path.removeFirst()
                atRest = g.path.isEmpty
            } else {
                let step = min(speed * dt, dist)
                g.pos.x += dx / dist * step
                g.pos.y += dy / dist * step
                g.aux = Float(max(-1, min(1, dx / 60)))
                atRest = false
            }
        } else {
            atRest = true
        }

        if atRest {
            // Nuzzled up next to the stoplights: bob happily.
            g.squashY = 1 + 0.05 * Float(sin(time * 5 + Double(g.noiseSeed) * 9))
            g.squashX = 2 - g.squashY
            g.aux += (0 - g.aux) * Float(min(1, 3 * dt))
        } else {
            // Rolling wobble.
            g.squashY = 1 + 0.06 * Float(sin(time * 11))
            g.squashX = 2 - g.squashY
        }
    }

    // Grass: crouch, then bounce left/right along the bottom of the screen.
    // If the Dock is in the way, wind up a jump big enough to clear it.
    func updateGrass(_ g: Guy, dt: Double) {
        if g.growth < 1 { g.growth = min(1, g.growth + Float(dt / 15)) }
        let ground = groundY(atX: g.pos.x)

        switch g.hop {
        case .grounded(let crouchIn):
            g.pos.y = ground
            g.squashY += (1 - g.squashY) * Float(min(1, 10 * dt))
            let remaining = crouchIn - dt
            if remaining <= 0 {
                g.hop = .crouching(elapsed: 0)
                if Double.random(in: 0...1) < 0.25 { g.hopDir = -g.hopDir }
            } else {
                g.hop = .grounded(crouchIn: remaining)
            }
        case .crouching(let elapsed):
            let e = elapsed + dt
            let crouchTime = 0.16
            g.squashY = 1 - 0.4 * Float(min(1, e / crouchTime))
            if e >= crouchTime {
                // Peek ahead: is there a step up (the Dock) to clear?
                let ahead = groundY(atX: g.pos.x + g.hopDir * 90)
                let rise = max(0, g.pos.y - ahead)
                let hopHeight: CGFloat = rise > 4 ? rise + 50 : .random(in: 35...70)
                g.vel.dy = -sqrt(2 * gravity * hopHeight)
                g.vel.dx = g.hopDir * .random(in: 70...140) * (rise > 4 ? 1.6 : 1.0)
                g.squashY = 1.25
                g.hop = .airborne
            } else {
                g.hop = .crouching(elapsed: e)
            }
        case .airborne:
            g.vel.dy += gravity * dt
            g.pos.x += g.vel.dx * dt
            g.pos.y += g.vel.dy * dt
            g.squashY += (1 - g.squashY) * Float(min(1, 4 * dt))
            if g.pos.x < 15 { g.pos.x = 15; g.hopDir = 1 }
            if g.pos.x > screen.width - 15 { g.pos.x = screen.width - 15; g.hopDir = -1 }
            let landing = groundY(atX: g.pos.x)
            if g.vel.dy > 0 && g.pos.y >= landing {
                g.pos.y = landing
                g.vel = .zero
                g.squashY = 0.7   // landing squish, relaxes while grounded
                g.hop = .grounded(crouchIn: .random(in: 0.4...2.2))
            }
        }
        g.squashX = 2 - g.squashY
    }

    // Dandelion: stands and sways, occasionally keels over and dies, releasing
    // three seeds — one grows into a new dandelion over 10 minutes, the other
    // two become wandering grass.
    func updateDandelion(_ g: Guy, dt: Double, newborn: inout [Guy]) {
        g.pos.y = groundY(atX: g.pos.x)
        switch g.dandelion {
        case .growing(let elapsed, let duration):
            let e = elapsed + dt
            g.growth = Float(min(1, e / duration))
            if e >= duration {
                g.dandelion = .standing(remaining: .random(in: 90...240))
            } else {
                g.dandelion = .growing(elapsed: e, duration: duration)
            }
        case .standing(let remaining):
            let r = remaining - dt
            if r <= 0 {
                g.dandelion = .falling(progress: 0, direction: Bool.random() ? 1 : -1)
            } else {
                g.dandelion = .standing(remaining: r)
            }
        case .falling(let progress, let direction):
            let p = progress + dt / 1.3
            let eased = CGFloat(p * p)  // accelerate, like tipping over
            g.aux = Float(direction * min(1.45, eased * 1.45))
            if p >= 1 {
                g.dandelion = .dead(fade: 0)
                spawnSeeds(from: g, direction: direction, newborn: &newborn)
            } else {
                g.dandelion = .falling(progress: p, direction: direction)
            }
        case .dead(let fade):
            let f = fade + dt / 2.0
            g.life = Float(max(0, 1 - f))
            if f >= 1 { g.dead = true }
            g.dandelion = .dead(fade: f)
        }
    }

    func spawnSeeds(from g: Guy, direction: CGFloat, newborn: inout [Guy]) {
        // The head ends up roughly a stalk-length sideways from the base.
        let headX = g.pos.x + direction * g.size * CGFloat(g.growth)
        for i in 0..<3 {
            let s = Guy(type: .seed,
                        pos: CGPoint(x: headX + .random(in: -10...10), y: g.pos.y - 20),
                        size: 6)
            s.vel = CGVector(dx: .random(in: -55...55), dy: -.random(in: 20...60))
            s.seedIsDandelion = (i == 0)
            newborn.append(s)
        }
    }

    // Seeds drift on the wind, then land and become their next life.
    func updateSeed(_ g: Guy, dt: Double, newborn: inout [Guy]) {
        g.seedDriftPhase += dt * 3
        g.vel.dy += 60 * dt            // gentle, air-resisted fall
        g.vel.dy = min(g.vel.dy, 45)
        g.vel.dx *= 1 - CGFloat(min(1, 0.4 * dt))
        g.pos.x += g.vel.dx * dt + CGFloat(sin(g.seedDriftPhase)) * 22 * dt
        g.pos.y += g.vel.dy * dt
        g.pos.x = max(15, min(screen.width - 15, g.pos.x))
        let ground = groundY(atX: g.pos.x)
        if g.pos.y >= ground {
            g.dead = true
            let grassCount = guys.filter { $0.type == .grass }.count
            let dandelionCount = guys.filter { $0.type == .dandelion }.count
            if g.seedIsDandelion && dandelionCount < 4 {
                let d = Guy(type: .dandelion, pos: CGPoint(x: g.pos.x, y: ground), size: .random(in: 95...130))
                d.growth = 0
                d.dandelion = .growing(elapsed: 0, duration: 600)   // 10 minutes to grow up
                newborn.append(d)
            } else if !g.seedIsDandelion && grassCount < 20 {
                let b = Guy(type: .grass, pos: CGPoint(x: g.pos.x, y: ground), size: .random(in: 55...85))
                b.growth = 0.05
                newborn.append(b)
            }
        }
    }

    func fillUniforms(into buf: inout [GuyUniform]) -> Int {
        let n = min(guys.count, maxGuys)
        for i in 0..<n { buf[i] = guys[i].uniform }
        return n
    }
}

// MARK: - Renderer

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let sim: Sim
    var lastTime = CACurrentMediaTime()
    var guyBuf = [GuyUniform](repeating: GuyUniform(a: .zero, b: .zero, c: .zero), count: maxGuys)

    init(device: MTLDevice, view: MTKView, sim: Sim) throws {
        self.device = device
        self.sim = sim
        queue = device.makeCommandQueue()!
        let lib = try device.makeLibrary(source: shaderSource, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "vmain")
        desc.fragmentFunction = lib.makeFunction(name: "fmain")
        let att = desc.colorAttachments[0]!
        att.pixelFormat = view.colorPixelFormat
        att.isBlendingEnabled = true
        att.rgbBlendOperation = .add
        att.alphaBlendOperation = .add
        att.sourceRGBBlendFactor = .sourceAlpha
        att.sourceAlphaBlendFactor = .one
        att.destinationRGBBlendFactor = .oneMinusSourceAlpha
        att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try device.makeRenderPipelineState(descriptor: desc)
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        sim.update(dt: dt)

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let scale = view.bounds.width > 0 ? Float(view.drawableSize.width / view.bounds.width) : 2
        var uni = FrameUniforms(
            resolution: SIMD2(Float(view.bounds.width), Float(view.bounds.height)),
            scale: scale,
            time: Float(sim.time),
            count: Int32(sim.fillUniforms(into: &guyBuf))
        )
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uni, length: MemoryLayout<FrameUniforms>.stride, index: 0)
        enc.setFragmentBytes(&guyBuf, length: MemoryLayout<GuyUniform>.stride * maxGuys, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }
}

// MARK: - Herd file (.lg) parsing

func parseHerd(at path: String) -> [(String, [String: Double])] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        fputs("lilguys: couldn't read \(path); using the default herd\n", stderr)
        return defaultHerd()
    }
    var herd: [(String, [String: Double])] = []
    for rawLine in text.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(separator: " ").map(String.init)
        var opts: [String: Double] = [:]
        for p in parts.dropFirst() {
            let kv = p.split(separator: "=", maxSplits: 1)
            if kv.count == 2, let v = Double(kv[1]) { opts[String(kv[0])] = v }
        }
        herd.append((parts[0].lowercased(), opts))
    }
    return herd.isEmpty ? defaultHerd() : herd
}

func defaultHerd() -> [(String, [String: Double])] {
    [("fuzzball", [:]),
     ("grass", ["x": 0.2]), ("grass", ["x": 0.45]), ("grass", ["x": 0.5]),
     ("dandelion", ["x": 0.7])]
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: MTKView!
    var renderer: Renderer!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // screens.first is the display whose CG global origin is (0,0) — the
        // sim's coordinates assume the overlay covers exactly that display.
        guard let screen = NSScreen.screens.first else { fatalError("lilguys: no screen") }
        guard let device = MTLCreateSystemDefaultDevice() else { fatalError("lilguys: no Metal device") }

        let frame = screen.frame
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true                 // fully click-through
        window.level = .screenSaver                      // float above everything
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        view = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let herdPath = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : (FileManager.default.currentDirectoryPath + "/lilguys.lg")
        let herd = FileManager.default.fileExists(atPath: herdPath) ? parseHerd(at: herdPath) : defaultHerd()

        // Simulation runs in top-left-origin "CG" coordinates to match
        // CGWindowListCopyWindowInfo; for the main screen the overlay's
        // top-left is exactly CG (0, 0), so no conversion is needed.
        let sim = Sim(screen: CGRect(origin: .zero, size: frame.size), herd: herd)

        do {
            renderer = try Renderer(device: device, view: view, sim: sim)
        } catch {
            fatalError("lilguys: shader compile failed: \(error)")
        }
        view.delegate = renderer

        window.contentView = view
        view.layer?.isOpaque = false      // let the desktop show through
        window.orderFrontRegardless()
        sim.ourWindowNumber = window.windowNumber

        fputs("lilguys: \(sim.guys.count) lilguys are loose on your desktop. ctrl-c to shoo them away.\n", stderr)
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
