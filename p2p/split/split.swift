// split.swift — single-file image channel-splitting library.
//
// One job: accept an image, return channel-split versions of it.
//
// Library use:
//   let splits = try ChannelSplitter.split(cgImage: image)
//   splits[.red]  // CGImage containing only the red channel
//
// CLI use (runs the file directly):
//   swift split.swift input.png [output-dir]
//   → writes input.red.png, input.green.png, input.blue.png

import Foundation
import CoreGraphics
import ImageIO
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum Channel: String, CaseIterable, Sendable {
    case red, green, blue

    /// Byte offset of this channel in premultiplied-last RGBA8 pixel data.
    var offset: Int {
        switch self {
        case .red: return 0
        case .green: return 1
        case .blue: return 2
        }
    }
}

/// How each split image represents its channel.
public enum SplitStyle: Sendable {
    /// Keep the channel in its own color plane, zero the others
    /// (the classic RGB-split look).
    case tinted
    /// Render the channel's intensity as a grayscale image.
    case grayscale
}

public enum ChannelSplitError: Error, CustomStringConvertible {
    case unreadableImage(String)
    case contextCreationFailed
    case imageCreationFailed(Channel)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .unreadableImage(let path): return "could not read image at \(path)"
        case .contextCreationFailed: return "could not create drawing context"
        case .imageCreationFailed(let c): return "could not build \(c.rawValue) channel image"
        case .writeFailed(let path): return "could not write \(path)"
        }
    }
}

public enum ChannelSplitter {

    /// Split a CGImage into one image per color channel.
    public static func split(
        cgImage: CGImage,
        style: SplitStyle = .tinted
    ) throws -> [Channel: CGImage] {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ChannelSplitError.contextCreationFailed }

        var result: [Channel: CGImage] = [:]
        for channel in Channel.allCases {
            var channelPixels = [UInt8](repeating: 0, count: pixels.count)
            for pixel in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
                let value = pixels[pixel + channel.offset]
                switch style {
                case .tinted:
                    channelPixels[pixel + channel.offset] = value
                case .grayscale:
                    channelPixels[pixel] = value
                    channelPixels[pixel + 1] = value
                    channelPixels[pixel + 2] = value
                }
                channelPixels[pixel + 3] = pixels[pixel + 3]
            }

            let data = Data(channelPixels)
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bitsPerPixel: bytesPerPixel * 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                  )
            else { throw ChannelSplitError.imageCreationFailed(channel) }
            result[channel] = image
        }
        return result
    }

    /// Convenience: load an image from disk and split it.
    public static func split(
        contentsOf url: URL,
        style: SplitStyle = .tinted
    ) throws -> [Channel: CGImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ChannelSplitError.unreadableImage(url.path) }
        return try split(cgImage: image, style: style)
    }

    /// Write a CGImage to disk as a PNG.
    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { throw ChannelSplitError.writeFailed(url.path) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ChannelSplitError.writeFailed(url.path)
        }
    }
}

// MARK: - CLI entry point (only when run as a script / main file)

func runCLI() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        print("usage: swift split.swift <image> [output-dir]")
        exit(64)
    }
    let input = URL(fileURLWithPath: args[1])
    let outputDir = args.count >= 3
        ? URL(fileURLWithPath: args[2], isDirectory: true)
        : input.deletingLastPathComponent()
    let stem = input.deletingPathExtension().lastPathComponent

    do {
        try FileManager.default.createDirectory(
            at: outputDir, withIntermediateDirectories: true)
        let splits = try ChannelSplitter.split(contentsOf: input)
        for (channel, image) in splits.sorted(by: { $0.key.offset < $1.key.offset }) {
            let out = outputDir.appendingPathComponent("\(stem).\(channel.rawValue).png")
            try ChannelSplitter.writePNG(image, to: out)
            print(out.path)
        }
    } catch {
        print("split: \(error)")
        exit(1)
    }
}

runCLI()
