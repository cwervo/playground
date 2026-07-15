import SwiftUI
import AVFoundation

/// Live camera preview layer wrapped for SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// The 80 pt full-width red binarization bar + the scanline oscilloscope.
struct RedBarOverlay: View {
    let scanline: ScanlineResult
    @Binding var centerY: CGFloat
    static let barHeight: CGFloat = 80

    var body: some View {
        GeometryReader { geo in
            let y = centerY * geo.size.height
            ZStack {
                // The bar itself: translucent red, hairline read-axis.
                Rectangle()
                    .fill(Color.red.opacity(0.18))
                    .overlay(Rectangle().stroke(Color.red.opacity(0.7), lineWidth: 1))
                    .overlay(Rectangle().fill(Color.red).frame(height: 1))
                    .frame(width: geo.size.width, height: Self.barHeight)
                    .position(x: geo.size.width / 2, y: y)

                // Oscilloscope of the red-laser L* signal, just below the bar.
                waveform(size: geo.size, barY: y)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture().onChanged { v in
                    let f = v.location.y / geo.size.height
                    centerY = min(max(f, 0.12), 0.88)
                }
            )
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func waveform(size: CGSize, barY: CGFloat) -> some View {
        let h: CGFloat = 44
        let top = min(barY + Self.barHeight / 2 + 8, size.height - h - 8)
        Canvas { ctx, _ in
            let s = scanline.signal
            guard s.count > 1 else { return }
            let dx = size.width / CGFloat(s.count - 1)
            // Binarized runs as dark ticks behind the trace.
            var binPath = Path()
            for (i, dark) in scanline.binary.enumerated() where dark {
                let x = CGFloat(i) * dx
                binPath.addRect(CGRect(x: x, y: top, width: max(dx, 1), height: h))
            }
            ctx.fill(binPath, with: .color(.black.opacity(0.45)))
            // The analog trace.
            var path = Path()
            path.move(to: CGPoint(x: 0, y: top + h * CGFloat(1 - s[0])))
            for i in 1..<s.count {
                path.addLine(to: CGPoint(x: CGFloat(i) * dx, y: top + h * CGFloat(1 - s[i])))
            }
            ctx.stroke(path, with: .color(.green), lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }
}

/// Outlines for detected paper / sticky-note quads.
struct QuadOverlay: View {
    let quads: [PaperQuad]

    var body: some View {
        GeometryReader { geo in
            ForEach(quads) { quad in
                let pts = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
                    .map { p in
                        // Vision: normalized, origin bottom-left → view coords.
                        CGPoint(x: p.x * geo.size.width, y: (1 - p.y) * geo.size.height)
                    }
                Path { path in
                    path.move(to: pts[0])
                    for p in pts.dropFirst() { path.addLine(to: p) }
                    path.closeSubpath()
                }
                .stroke(color(for: quad.kind), lineWidth: 2)

                Text(quad.label)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color(for: quad.kind).opacity(0.85), in: Capsule())
                    .foregroundStyle(.black)
                    .position(x: (pts[0].x + pts[1].x) / 2, y: min(pts[0].y, pts[1].y) - 14)
            }
        }
        .allowsHitTesting(false)
    }

    private func color(for kind: PaperQuad.Kind) -> Color {
        switch kind {
        case .paper: return .white
        case .sticky: return .yellow
        case .other: return .gray
        }
    }
}
