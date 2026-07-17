#!/usr/bin/env swift
// GenerateIcon.swift — single-file app-icon generator for Folk.
//
// Renders 4 gold metaballs on a white background. Ball positions encode the
// creation time: hours, minutes, seconds, and milliseconds each place one
// ball on its own concentric ring (angle = fraction of the unit, 12 o'clock
// = zero). Every build's icon is therefore a unique, glanceable timestamp.
//
// Usage (macOS):
//   swift tools/GenerateIcon.swift [output.png]
// Default output: folk-ios/Folk/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
// (relative to the repo, when run from the repo root)

import Foundation
import CoreGraphics
import ImageIO

let size = 1024
let dim = Double(size)

// --- Time -> ball positions (same layout as the in-app metaball clock) ----

let now = Date()
let cal = Calendar.current
let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
let hh = comps.hour ?? 0
let mm = comps.minute ?? 0
let ss = comps.second ?? 0
let ms = (comps.nanosecond ?? 0) / 1_000_000

let cx = dim / 2
let cy = dim / 2
let specs: [(value: Double, unit: Double, ringFrac: Double)] = [
    (Double(hh), 24, 0.10),
    (Double(mm), 60, 0.17),
    (Double(ss), 60, 0.24),
    (Double(ms), 1000, 0.31),
]

var balls: [(x: Double, y: Double)] = []
for s in specs {
    let angle = 2 * Double.pi * s.value / s.unit - Double.pi / 2
    let r = dim * s.ringFrac
    balls.append((cx + r * cos(angle), cy + r * sin(angle)))
}

let ballRadius = dim * 0.115
let r2 = ballRadius * ballRadius

// --- Render the field -----------------------------------------------------

// Gold on white, with a slightly deeper gold rim at the blob edge.
let gold = (r: 0.83, g: 0.68, b: 0.21)
let rim = (r: 0.62, g: 0.48, b: 0.12)

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

var pixels = [UInt8](repeating: 255, count: size * size * 4)
for py in 0..<size {
    for px in 0..<size {
        let x = Double(px) + 0.5
        let y = Double(py) + 0.5
        var field = 0.0
        for b in balls {
            let dx = x - b.x
            let dy = y - b.y
            field += r2 / max(dx * dx + dy * dy, 1e-6)
        }
        let coverage = smoothstep(0.96, 1.06, field)
        let rimMix = 1.0 - smoothstep(1.06, 1.45, field)   // deeper gold at the edge
        let cr = gold.r + (rim.r - gold.r) * rimMix
        let cg = gold.g + (rim.g - gold.g) * rimMix
        let cb = gold.b + (rim.b - gold.b) * rimMix
        let i = (py * size + px) * 4
        pixels[i]     = UInt8(((1 - coverage) + cr * coverage) * 255)
        pixels[i + 1] = UInt8(((1 - coverage) + cg * coverage) * 255)
        pixels[i + 2] = UInt8(((1 - coverage) + cb * coverage) * 255)
        pixels[i + 3] = 255
    }
}

// --- Write PNG ------------------------------------------------------------

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let defaultOut = scriptDir
    .appendingPathComponent("../Folk/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    .standardizedFileURL.path
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOut

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: &pixels,
                              width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: size * 4,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let image = context.makeImage() else {
    fputs("error: could not create image context\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("error: could not open \(outPath) for writing\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("error: failed to write PNG\n", stderr)
    exit(1)
}

print(String(format: "AppIcon generated for %02d:%02d:%02d.%03d -> %@", hh, mm, ss, ms, outPath))
