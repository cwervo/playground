// SurfaceView.swift
// SwiftUI wrapper around the Metal-backed Surface. Text instructions and
// program labels are composited over the Metal layer as SwiftUI views.

import SwiftUI
import MetalKit

struct MetalSurface: UIViewRepresentable {
    @ObservedObject var engine: FolkEngine

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.preferredFramesPerSecond = 30
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm

        if let renderer = SurfaceRenderer(pixelFormat: view.colorPixelFormat) {
            view.device = renderer.device
            let engineRef = engine
            renderer.onFrame = { [weak engineRef, weak renderer] size in
                guard let engineRef, let renderer else { return }
                engineRef.tick(surfaceSize: size)
                renderer.instructions = engineRef.frame.instructions
            }
            view.delegate = renderer
            context.coordinator.renderer = renderer
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: SurfaceRenderer?
    }
}

struct SurfaceView: View {
    @ObservedObject var engine: FolkEngine

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalSurface(engine: engine)
                .ignoresSafeArea()

            // Text instructions, placed at their surface coordinates.
            ForEach(Array(textInstructions.enumerated()), id: \.offset) { pair in
                let item = pair.element
                Text(item.text)
                    .font(.system(size: CGFloat(item.size), design: .monospaced))
                    .foregroundColor(Color(red: Double(item.color.r),
                                           green: Double(item.color.g),
                                           blue: Double(item.color.b))
                        .opacity(Double(item.color.a)))
                    .position(x: CGFloat(item.position.x), y: CGFloat(item.position.y))
            }
            .ignoresSafeArea()

            // Program labels, stacked in the top-left like Folk page labels.
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(engine.frame.labels.enumerated()), id: \.offset) { pair in
                    let label = pair.element
                    (Text(label.program + " ").bold() + Text(label.text))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.45), in: Capsule())
                }
            }
            .padding(12)
            .allowsHitTesting(false)
        }
    }

    private var textInstructions: [(text: String, position: SIMD2<Float>, size: Float, color: RGBA)] {
        engine.frame.instructions.compactMap { instruction in
            if case .text(let t, let p, let s, let c) = instruction {
                return (t, p, s, c)
            }
            return nil
        }
    }
}
