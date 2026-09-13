import SwiftUI
import UIKit

/// Hosts the PiP source layer inside SwiftUI. The layer must be on screen
/// for iOS to allow PiP to start from it.
struct SampleBufferView: UIViewRepresentable {
    let layer: CALayer

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.hostedLayer = layer
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {}

    final class LayerHostView: UIView {
        var hostedLayer: CALayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let hostedLayer { layer.addSublayer(hostedLayer) }
                setNeedsLayout()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hostedLayer?.frame = bounds
            CATransaction.commit()
        }
    }
}
