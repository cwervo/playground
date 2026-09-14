import SwiftUI
import SMFBKit

// One entry point for all four app targets. Everything platform-specific
// lives in SMFBKit behind `#if os(...)`.
@main
struct SMFBApp: App {
    @StateObject private var sim = Simulation(config: .forCurrentDevice)

    var body: some Scene {
        WindowGroup {
            SMFBRootView(sim: sim)
        }
        #if os(macOS)
        .defaultSize(width: 960, height: 640)
        #endif
    }
}
