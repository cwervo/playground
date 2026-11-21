// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DNSBookApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DNSBookApp"
        ),
    ]
)
