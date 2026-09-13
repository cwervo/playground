import SwiftUI

@main
struct PiPStampApp: App {
    @StateObject private var engine = StampEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
        }
    }
}
