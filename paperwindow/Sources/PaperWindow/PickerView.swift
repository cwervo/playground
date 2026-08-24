import AppKit

protocol PickerViewDelegate: AnyObject {
    func pickerView(_ view: PickerView, didPick window: WindowInfo)
    func pickerViewDidCancel(_ view: PickerView)
}

/// Full screen dimmer that highlights whatever window is under the cursor and
/// reports the one you click.
final class PickerView: NSView {

    weak var delegate: PickerViewDelegate?

    private var hovered: WindowInfo?
    /// Origin of this view in AppKit screen coordinates, so we can turn view
    /// points back into global points.
    private let originInScreen: CGPoint

    init(frame: CGRect, originInScreen: CGPoint) {
        self.originInScreen = originInScreen
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + originInScreen.x, y: local.y + originInScreen.y)
    }

    private func viewRect(for info: WindowInfo) -> CGRect {
        let ns = Coords.nsRect(fromCG: info.bounds)
        return ns.offsetBy(dx: -originInScreen.x, dy: -originInScreen.y)
    }

    override func mouseMoved(with event: NSEvent) {
        let found = WindowList.window(underNSPoint: screenPoint(event))
        if found?.id != hovered?.id {
            hovered = found
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let window = hovered ?? WindowList.window(underNSPoint: screenPoint(event)) {
            delegate?.pickerView(self, didPick: window)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {                 // esc
            delegate?.pickerViewDidCancel(self)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.18).setFill()
        bounds.fill()

        guard let hovered else {
            drawHint("Move over a window, then click to turn it into paper  ·  esc to quit",
                     centeredIn: bounds)
            return
        }

        let rect = viewRect(for: hovered)

        // Punch the dim back out over the candidate so it reads as selected.
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor(white: 0, alpha: 1).setFill()
        rect.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        let border = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        border.lineWidth = 2.5
        NSColor.systemYellow.setStroke()
        border.stroke()

        for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
            let dot = NSBezierPath(ovalIn: CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10))
            NSColor.systemYellow.setFill()
            dot.fill()
        }

        drawHint(hovered.label,
                 centeredIn: CGRect(x: rect.minX, y: rect.maxY + 10, width: rect.width, height: 28))
    }

    private func drawHint(_ text: String, centeredIn rect: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
            .shadow: {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
                shadow.shadowBlurRadius = 4
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                return shadow
            }()
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let box = CGRect(x: rect.minX,
                         y: rect.midY - size.height / 2,
                         width: rect.width,
                         height: size.height)
        string.draw(in: box)
    }
}
