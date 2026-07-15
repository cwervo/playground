// swift-tools-version: 5.8

// P2PMotionSim — open this .swiftpm folder with Swift Playgrounds on iPad
// (or Xcode on Mac) and press Run.
//
// Simulator of: Iyer, Najafi, James, Fuller, Gollakota,
// "Wireless steerable vision for live insects and insect-scale robots",
// Science Robotics 5(44), 2020 — University of Washington.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "P2PMotionSim",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "P2PMotionSim",
            targets: ["AppModule"],
            bundleIdentifier: "dev.cwervo.p2pmotionsim",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .camera),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
