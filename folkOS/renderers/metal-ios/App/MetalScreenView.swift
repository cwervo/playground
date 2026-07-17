// MetalScreenView.swift — SwiftUI wrapper for the Metal output pane.

import SwiftUI
import MetalKit

struct MetalScreenView: UIViewRepresentable {
    var folkFrame: FolkFrame?

    final class Coordinator {
        var renderer: FolkRenderer?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.clearColor = MTLClearColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
        if let renderer = FolkRenderer(mtkView: view) {
            view.delegate = renderer
            context.coordinator.renderer = renderer
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.frame = folkFrame
        uiView.setNeedsDisplay()
    }
}
