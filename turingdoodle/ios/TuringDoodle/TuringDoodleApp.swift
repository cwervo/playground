import SwiftUI

@main
struct TuringDoodleApp: App {
    var body: some Scene {
        WindowGroup {
            DoodleWebView()
                .ignoresSafeArea()
                .background(Color.black)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
    }
}
