#!/usr/bin/env swift
//
//  GenerateIcon.swift — the LabScan V2 app icon, from one file.
//
//    swift GenerateIcon.swift [output.png]
//
//  A fun, reproducible technique for making app icons: typeset a texture with
//  CoreText, then hand it to a Metal compute kernel that does the actual
//  design work, and write the result straight into the asset catalog.
//
//  The icon: a page of type — alternating lines of Times New Roman and
//  IBM Plex Mono, brief excerpts from Richard Hamming's 1986 talk
//  "You and Your Research" — crossed by a red bar that is fully opaque at
//  50% of the icon's height and fades to transparent at 30% and 90%.
//
//  Requires macOS + Metal. Falls back to Menlo if IBM Plex Mono is not
//  installed (brew install --cask font-ibm-plex-mono).
//
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import Metal
import UniformTypeIdentifiers

let SIZE = 1024

// MARK: - 1. Typeset the background texture (CoreText → CGContext)

// Brief excerpts, Richard Hamming, "You and Your Research" (1986).
let excerpts = [
    "Luck favors the prepared mind.",
    "What are the important problems of your field?",
    "Knowledge and productivity are like compound interest.",
    "Great scientists tolerate ambiguity.",
    "Work with your door open.",
    "It is not sufficient to do a job, you have to sell it.",
    "Why do so few scientists make significant contributions?",
]

func font(_ name: String, _ size: CGFloat, fallback: String) -> CTFont {
    let f = CTFontCreateWithName(name as CFString, size, nil)
    if CTFontCopyPostScriptName(f) as String != name {
        FileHandle.standardError.write("warning: \(name) not installed, using \(fallback)\n".data(using: .utf8)!)
        return CTFontCreateWithName(fallback as CFString, size, nil)
    }
    return f
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let page = CGContext(data: nil, width: SIZE, height: SIZE,
                           bitsPerComponent: 8, bytesPerRow: SIZE * 4, space: space,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create CGContext")
}

// Warm paper, dark ink.
page.setFillColor(CGColor(srgbRed: 0.98, green: 0.962, blue: 0.925, alpha: 1))
page.fill(CGRect(x: 0, y: 0, width: SIZE, height: SIZE))

let serif = font("TimesNewRomanPSMT", 36, fallback: "Georgia")
let mono  = font("IBMPlexMono", 28, fallback: "Menlo-Regular")

let lineHeight: CGFloat = 41
var row = 0
var baseline = CGFloat(SIZE) - 30      // CG origin is bottom-left; walk down from the top
while baseline > -lineHeight {
    let text = excerpts[row % excerpts.count]
    // Repeat each excerpt past the right edge so every row reads as a full line of type.
    let filled = Array(repeating: text, count: 12).joined(separator: "   ")
    let ink = CGColor(srgbRed: 0.13, green: 0.11, blue: 0.10,
                      alpha: 0.5 + 0.4 * abs(sin(Double(row) * 1.7)))
    let attr = NSAttributedString(string: filled, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: (row % 2 == 0) ? serif : mono,
        kCTForegroundColorAttributeName as NSAttributedString.Key: ink,
    ])
    page.textPosition = CGPoint(x: -CGFloat((row * 53) % 140), y: baseline)
    CTLineDraw(CTLineCreateWithAttributedString(attr), page)
    baseline -= lineHeight
    row += 1
}

// MARK: - 2. The shader (Metal source, compiled at runtime)

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

// Vertical opacity of the red bar, y in [0,1] measured from the top:
// 0 at y=0.30, 1 at y=0.50, 0 at y=0.90.
static float stripeAlpha(float y) {
    return min(smoothstep(0.30, 0.50, y), 1.0 - smoothstep(0.50, 0.90, y));
}

kernel void iconKernel(texture2d<float, access::read>  pageTex [[texture(0)]],
                       texture2d<float, access::write> outTex  [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
    float2 uv = (float2(gid) + 0.5) / float2(outTex.get_width(), outTex.get_height());

    float3 page = pageTex.read(gid).rgb;

    float a = stripeAlpha(uv.y);
    // Deep crimson at the fades, bright lab red at full strength.
    float3 red = mix(float3(0.48, 0.02, 0.07), float3(0.88, 0.10, 0.12), a);

    outTex.write(float4(mix(page, red, a), 1.0), gid);
}
"""

// MARK: - 3. Run it (CGContext → MTLTexture → kernel → PNG)

guard let device = MTLCreateSystemDefaultDevice(),
      let queue = device.makeCommandQueue() else { fatalError("no Metal device") }

let library = try device.makeLibrary(source: shaderSource, options: nil)
let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "iconKernel")!)

let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                    width: SIZE, height: SIZE, mipmapped: false)
desc.usage = [.shaderRead]
let pageTex = device.makeTexture(descriptor: desc)!
pageTex.replace(region: MTLRegionMake2D(0, 0, SIZE, SIZE), mipmapLevel: 0,
                withBytes: page.data!, bytesPerRow: SIZE * 4)

desc.usage = [.shaderWrite]
let outTex = device.makeTexture(descriptor: desc)!

let cmd = queue.makeCommandBuffer()!
let enc = cmd.makeComputeCommandEncoder()!
enc.setComputePipelineState(pipeline)
enc.setTexture(pageTex, index: 0)
enc.setTexture(outTex, index: 1)
let tg = MTLSize(width: 16, height: 16, depth: 1)
enc.dispatchThreadgroups(MTLSize(width: (SIZE + 15) / 16, height: (SIZE + 15) / 16, depth: 1),
                         threadsPerThreadgroup: tg)
enc.endEncoding()
cmd.commit()
cmd.waitUntilCompleted()

var pixels = [UInt8](repeating: 0, count: SIZE * SIZE * 4)
outTex.getBytes(&pixels, bytesPerRow: SIZE * 4, from: MTLRegionMake2D(0, 0, SIZE, SIZE), mipmapLevel: 0)

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "LabScan/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
let image = pixels.withUnsafeMutableBytes { buf -> CGImage in
    CGContext(data: buf.baseAddress, width: SIZE, height: SIZE,
              bitsPerComponent: 8, bytesPerRow: SIZE * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath) (\(SIZE)x\(SIZE))")
