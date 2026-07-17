#!/usr/bin/env swift
//
// MakeAppIcon.swift — the LabScan V2 app icon, generated offscreen by a
// Metal compute shader and written straight to PNG. macOS only:
//
//     swift MakeAppIcon.swift [output-dir]
//
// With no argument it writes AppIcon.png (1024×1024) into
// LabScan/Assets.xcassets/AppIcon.appiconset/ next to this script, plus
// the asset-catalog Contents.json files, so `xcodegen && xcodebuild`
// picks it up with zero clicking.
//
// The technique, as a shareable recipe:
//   1. CoreText typesets a "page" into a CGBitmapContext — here, lines
//      from Richard Hamming's talk "You and Your Research", alternating
//      Times New Roman and IBM Plex Mono (falls back to Menlo if Plex
//      isn't installed).
//   2. The page is uploaded as an MTLTexture and a ~15-line compute
//      kernel composites the LabScan scan-stripe over it: pure red at
//      100% opacity at 50% of the icon height, smoothly fading to 0%
//      at 30% and at 90%.
//   3. The result is read back and written with ImageIO. No windows,
//      no Xcode, no asset pipeline — shader → image.

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Metal
import UniformTypeIdentifiers

let SIZE = 1024

// MARK: - The page (CoreText)

let quotes = [
    "Luck favors the prepared mind.",
    "Knowledge and productivity are like compound interest.",
    "If you do not work on an important problem, it's unlikely you'll do important work.",
    "Great scientists tolerate ambiguity very well.",
    "He who works with the door open gets all kinds of interruptions, but he also occasionally gets clues as to what the world is and what might be important.",
    "It is a poor workman who blames his tools.",
    "What are the important problems of your field? And why are you not working on them?",
    "You should do your job in such a fashion that others can build on top of it.",
]

/// CTFontCreateWithName never fails — it silently substitutes — so check
/// the family we actually got and fall back deliberately.
func resolveFont(_ preferred: String, fallback: String, size: CGFloat) -> CTFont {
    let f = CTFontCreateWithName(preferred as CFString, size, nil)
    let family = CTFontCopyFamilyName(f) as String
    if family.caseInsensitiveCompare(preferred) == .orderedSame { return f }
    FileHandle.standardError.write(Data("note: \"\(preferred)\" not installed, using \(fallback)\n".utf8))
    return CTFontCreateWithName(fallback as CFString, size, nil)
}

/// Typeset the Hamming page: alternating serif/mono lines, each quote
/// repeated past the right edge and staggered left so the block reads as
/// a dense scanned document rather than a poster.
func renderPage() -> (data: Data, bytesPerRow: Int) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: SIZE, height: SIZE, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    ctx.setFillColor(CGColor(srgbRed: 0.965, green: 0.945, blue: 0.905, alpha: 1))  // warm paper
    ctx.fill(CGRect(x: 0, y: 0, width: SIZE, height: SIZE))
    let ink = CGColor(srgbRed: 0.13, green: 0.12, blue: 0.11, alpha: 0.88)

    let serif = resolveFont("Times New Roman", fallback: "Times New Roman", size: 46)
    let mono = resolveFont("IBM Plex Mono", fallback: "Menlo", size: 31)

    var baselineFromTop: CGFloat = 54
    var i = 0
    while baselineFromTop < CGFloat(SIZE) + 40 {
        let useSerif = i % 2 == 0
        let text = String(repeating: quotes[i % quotes.count] + "   ", count: 8)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): useSerif ? serif : mono,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.textPosition = CGPoint(
            x: -CGFloat((i * 137) % 260) - 12,          // stagger, like a mis-fed page
            y: CGFloat(SIZE) - baselineFromTop)          // CG origin is bottom-left
        CTLineDraw(line, ctx)
        baselineFromTop += useSerif ? 58 : 47
        i += 1
    }
    return (Data(bytes: ctx.data!, count: ctx.bytesPerRow * SIZE), ctx.bytesPerRow)
}

// MARK: - The stripe (Metal)

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

// The LabScan scan-stripe: 100% opacity at y = 0.50 of the icon height,
// fading to 0% at y = 0.30 and y = 0.90 (smoothstep on both shoulders),
// with the hairline read-axis of the live scanner bar at dead center.
kernel void icon(texture2d<float, access::read>  page [[texture(0)]],
                 texture2d<float, access::write> out  [[texture(1)]],
                 uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    float y = (float(gid.y) + 0.5) / float(out.get_height());
    float3 rgb = page.read(gid).rgb;

    float a = smoothstep(0.30, 0.50, y) * (1.0 - smoothstep(0.50, 0.90, y));
    rgb = mix(rgb, float3(0.867, 0.078, 0.133), a);

    float axis = 1.0 - smoothstep(0.0015, 0.004, fabs(y - 0.5));
    rgb = mix(rgb, float3(0.55, 0.0, 0.05), axis);

    out.write(float4(rgb, 1.0), gid);
}
"""

func compose(page: Data, bytesPerRow: Int) throws -> [UInt8] {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw NSError(domain: "MakeAppIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "no Metal device (macOS required)"])
    }
    let library = try device.makeLibrary(source: shaderSource, options: nil)
    let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "icon")!)
    let queue = device.makeCommandQueue()!

    func texture(usage: MTLTextureUsage) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: SIZE, height: SIZE, mipmapped: false)
        d.usage = usage
        d.storageMode = .managed  // portable across Apple Silicon + Intel/AMD
        return device.makeTexture(descriptor: d)!
    }
    let pageTex = texture(usage: .shaderRead)
    let outTex = texture(usage: [.shaderWrite, .shaderRead])
    page.withUnsafeBytes { raw in
        pageTex.replace(region: MTLRegionMake2D(0, 0, SIZE, SIZE), mipmapLevel: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: bytesPerRow)
    }

    let cmd = queue.makeCommandBuffer()!
    let enc = cmd.makeComputeCommandEncoder()!
    enc.setComputePipelineState(pipeline)
    enc.setTexture(pageTex, index: 0)
    enc.setTexture(outTex, index: 1)
    enc.dispatchThreadgroups(
        MTLSize(width: (SIZE + 7) / 8, height: (SIZE + 7) / 8, depth: 1),
        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    enc.endEncoding()
    let blit = cmd.makeBlitCommandEncoder()!
    blit.synchronize(resource: outTex)  // flush GPU writes back for CPU readback
    blit.endEncoding()
    cmd.commit()
    cmd.waitUntilCompleted()

    var pixels = [UInt8](repeating: 0, count: SIZE * SIZE * 4)
    outTex.getBytes(&pixels, bytesPerRow: SIZE * 4,
                    from: MTLRegionMake2D(0, 0, SIZE, SIZE), mipmapLevel: 0)
    return pixels
}

// MARK: - The file (ImageIO + asset catalog)

func writePNG(_ pixels: inout [UInt8], to url: URL) throws {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: &pixels, width: SIZE, height: SIZE, bitsPerComponent: 8, bytesPerRow: SIZE * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let image = ctx.makeImage()!
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw NSError(domain: "MakeAppIcon", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "PNG destination failed"]) }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest)
    else { throw NSError(domain: "MakeAppIcon", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "PNG write failed"]) }
}

func run() throws {
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let outDir = CommandLine.arguments.count > 1
        ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        : scriptDir.appendingPathComponent(
            "LabScan/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let (page, bytesPerRow) = renderPage()
    var pixels = try compose(page: page, bytesPerRow: bytesPerRow)
    let png = outDir.appendingPathComponent("AppIcon.png")
    try writePNG(&pixels, to: png)

    // If we're writing into an .appiconset, also emit the catalog JSON so
    // the icon is buildable straight away.
    if outDir.lastPathComponent.hasSuffix(".appiconset") {
        try #"""
        {"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],
         "info":{"author":"xcode","version":1}}
        """#.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        try #"{"info":{"author":"xcode","version":1}}"#.write(
            to: outDir.deletingLastPathComponent().appendingPathComponent("Contents.json"),
            atomically: true, encoding: .utf8)
    }
    print("wrote \(png.path)")
}

do { try run() } catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
