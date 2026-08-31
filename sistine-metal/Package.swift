// swift-tools-version: 5.9
import PackageDescription

// SwiftPM compiles any .metal files that live in a target's source directory
// into a `default.metallib` inside Bundle.module. If your toolchain doesn't,
// run Scripts/build-metallib.sh and MetalContext will find the loose library.
let package = Package(
    name: "Sistine",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Sistine",
            path: "Sources/Sistine",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AppKit"),
            ]
        )
    ]
)
