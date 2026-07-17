// ContentView.swift
// The whole app: the Surface fills the screen; the draggable input box
// floats above it.

import SwiftUI

struct ContentView: View {
    @StateObject private var engine = FolkEngine()

    var body: some View {
        ZStack {
            SurfaceView(engine: engine)
                .ignoresSafeArea()
            InputBox(engine: engine)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
}

#Preview {
    ContentView()
}
