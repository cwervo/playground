// swift-tools-version: 5.9
import PackageDescription

// SMFBKit — the Shannon Mouse Fly Brain as a Swift package.
//
//   SMFBCore   plain C + arm64 NEON assembly: connectome, LIF kernels, world.
//              The .S file compiles to an empty object on x86 simulators and
//              dispatch.c then picks the portable C kernels.
//   SMFBKit    Swift wrapper, the CoreGraphics renderer and the SwiftUI views
//              shared by the iOS, macOS, watchOS and tvOS app targets.
//
// The package also builds on Linux (`swift build`, `swift test`): the SwiftUI
// and CoreGraphics files are behind `#if canImport(...)`, so what remains is
// the headless simulation and its tests.
let package = Package(
    name: "SMFBKit",
    platforms: [.iOS(.v16), .macOS(.v13), .watchOS(.v9), .tvOS(.v16)],
    products: [
        .library(name: "SMFBCore", targets: ["SMFBCore"]),
        .library(name: "SMFBKit", targets: ["SMFBKit"]),
    ],
    targets: [
        .target(
            name: "SMFBCore",
            path: "Sources/SMFBCore",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SMFBKit",
            dependencies: ["SMFBCore"],
            path: "Sources/SMFBKit"
        ),
        .testTarget(
            name: "SMFBKitTests",
            dependencies: ["SMFBKit"],
            path: "Tests/SMFBKitTests"
        ),
    ]
)
