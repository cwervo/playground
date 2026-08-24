// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaperWindow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PaperWindow",
            path: "Sources/PaperWindow"
        )
    ]
)
