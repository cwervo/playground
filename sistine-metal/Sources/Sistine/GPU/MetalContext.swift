import Foundation
import Metal
import CoreVideo

/// A camera-backed texture and the CoreVideo objects that must stay alive with it.
struct CameraTexture {
    let texture: MTLTexture
    let retained: CVMetalTexture
    let pixelBuffer: CVPixelBuffer
}

enum MetalError: Error, CustomStringConvertible {
    case noDevice
    case noLibrary
    case missingFunction(String)
    case textureCache(CVReturn)

    var description: String {
        switch self {
        case .noDevice: return "No Metal device (this needs a Mac with a GPU Metal supports)."
        case .noLibrary: return "Could not load default.metallib. Run Scripts/build-metallib.sh."
        case .missingFunction(let n): return "Shader function '\(n)' missing from the metallib."
        case .textureCache(let r): return "CVMetalTextureCacheCreate failed (\(r))."
        }
    }
}

/// Device, queue, shader library, and the CVPixelBuffer -> MTLTexture bridge.
/// The texture cache is what keeps capture zero-copy: the camera's IOSurface is
/// handed to the GPU directly, never memcpy'd through the CPU.
final class MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    private let textureCache: CVMetalTextureCache

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw MetalError.noDevice }
        self.device = device
        self.queue = device.makeCommandQueue()!
        self.library = try MetalContext.loadLibrary(device: device)

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else { throw MetalError.textureCache(status) }
        self.textureCache = cache
    }

    /// SwiftPM, a hand-built metallib and an .app bundle each put the shader
    /// library somewhere different. Probing by URL rather than referencing
    /// `Bundle.module` keeps this compiling on toolchains that do not emit a
    /// resource bundle for a Metal-only resource set.
    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let lib = device.makeDefaultLibrary() { return lib }

        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var candidates: [URL] = [
            Bundle.main.url(forResource: "default", withExtension: "metallib"),
            executableDirectory.appendingPathComponent("default.metallib"),
            URL(fileURLWithPath: ".build/default.metallib"),
        ].compactMap { $0 }

        // SwiftPM emits <Product>_<Target>.bundle beside the binary.
        if let siblings = try? FileManager.default.contentsOfDirectory(
            at: executableDirectory, includingPropertiesForKeys: nil) {
            for bundle in siblings where bundle.pathExtension == "bundle" {
                candidates.append(bundle.appendingPathComponent("Contents/Resources/default.metallib"))
                candidates.append(bundle.appendingPathComponent("default.metallib"))
            }
        }

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let lib = try? device.makeLibrary(URL: url) { return lib }
        }
        throw MetalError.noLibrary
    }

    func pipeline(_ name: String) throws -> MTLComputePipelineState {
        guard let fn = library.makeFunction(name: name) else { throw MetalError.missingFunction(name) }
        return try device.makeComputePipelineState(function: fn)
    }

    /// Wraps one plane of a biplanar pixel buffer. Plane 0 is full-resolution
    /// luma (r8Unorm); plane 1 is half-resolution interleaved CbCr (rg8Unorm).
    ///
    /// The CVMetalTexture wrapper must outlive every use of the MTLTexture it
    /// vends — it is what keeps the underlying IOSurface alive — so it is
    /// returned alongside rather than dropped on the floor. Letting it go is the
    /// classic way to get a texture that reads as garbage under memory pressure
    /// and works perfectly in every test.
    func texture(from pixelBuffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat) -> CameraTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        var ref: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            format, width, height, plane, &ref)
        guard status == kCVReturnSuccess, let ref,
              let texture = CVMetalTextureGetTexture(ref) else { return nil }
        return CameraTexture(texture: texture, retained: ref, pixelBuffer: pixelBuffer)
    }

    func flushTextureCache() {
        CVMetalTextureCacheFlush(textureCache, 0)
    }

    func makeMaskTexture(width: Int, height: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)!
    }
}

extension MTLComputeCommandEncoder {
    /// Dispatch helper that respects the pipeline's own preferred widths instead
    /// of hardcoding a threadgroup size.
    func dispatch2D(_ pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        let tg = MTLSize(width: w, height: h, depth: 1)
        let grid = MTLSize(width: (width + w - 1) / w, height: (height + h - 1) / h, depth: 1)
        setComputePipelineState(pipeline)
        dispatchThreadgroups(grid, threadsPerThreadgroup: tg)
    }

    func dispatch1D(_ pipeline: MTLComputePipelineState, count: Int) {
        let w = min(pipeline.maxTotalThreadsPerThreadgroup, 64)
        setComputePipelineState(pipeline)
        dispatchThreadgroups(MTLSize(width: (count + w - 1) / w, height: 1, depth: 1),
                             threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1))
    }
}
