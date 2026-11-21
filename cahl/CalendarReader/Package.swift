// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalendarReader",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "CalendarReader",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Swifter", package: "swifter")
            ]
        ),
    ]
)
