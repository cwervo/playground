import UIKit

protocol HexBoardViewDelegate: AnyObject {
    func hexBoard(_ board: HexBoardView, didTap entry: HexEntry)
    func hexBoard(_ board: HexBoardView, didLongPress entry: HexEntry)
}

/// The honeycomb itself. Every key — hexagon, stroke, glyph — is drawn with
/// CoreGraphics in draw(_:); there are no subviews per key. The view is
/// rendered once per category change (UIKit rasterizes it into the layer's
/// backing store), so scrolling is pure compositing with zero draw calls
/// per frame; the perf gate measures the one-off render.
final class HexBoardView: UIView {

    weak var delegate: HexBoardViewDelegate?

    private(set) var entries: [HexEntry] = []
    private(set) var layout = HexLayout(boardWidth: 320, count: 0)
    private var pressedIndex: Int? = nil
    private var longPressTimer: Timer? = nil
    private var longPressed = false

    /// Time spent inside the last full draw(_:), for the perf gate.
    private(set) var lastDrawMilliseconds: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.background
        isMultipleTouchEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setEntries(_ newEntries: [HexEntry], boardWidth: CGFloat) {
        entries = newEntries
        layout = HexLayout(boardWidth: boardWidth, count: newEntries.count)
        pressedIndex = nil
        setNeedsDisplay()
    }

    var contentHeight: CGFloat { layout.contentHeight + 8 }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), !entries.isEmpty else { return }
        let started = CACurrentMediaTime()

        let hexPath = layout.hexPath(inset: 1)
        let glyphFont = Theme.glyphFont(size: layout.hexWidth * 0.44)
        let labelFont = UIFont.systemFont(ofSize: layout.hexWidth * 0.2, weight: .medium)
        let ink = Theme.ink.resolvedColor(with: traitCollection)
        let fill = Theme.keyFill.resolvedColor(with: traitCollection)
        let stroke = Theme.keyLine.resolvedColor(with: traitCollection)

        for (i, entry) in entries.enumerated() {
            let frame = layout.frames[i]
            if frame.maxY < rect.minY - 1 || frame.minY > rect.maxY + 1 { continue }

            let pressed = i == pressedIndex
            ctx.saveGState()
            ctx.translateBy(x: frame.minX, y: frame.minY)
            ctx.addPath(hexPath)
            ctx.setFillColor((pressed ? Theme.accent : fill).cgColor)
            ctx.setStrokeColor((pressed ? Theme.accentDeep : stroke).cgColor)
            ctx.setLineWidth(1)
            ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()

            let isLabel = entry.d != nil
            let text = HexUnicode.displayText(for: entry)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: isLabel ? labelFont : glyphFont,
                .foregroundColor: pressed ? UIColor.white : ink,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let at = CGPoint(x: frame.midX - size.width / 2,
                             y: frame.midY - size.height / 2)
            (text as NSString).draw(at: at, withAttributes: attrs)
        }

        lastDrawMilliseconds = (CACurrentMediaTime() - started) * 1000
    }

    // MARK: touches — tap inserts, a 450 ms hold opens the detail card.
    // Hand-rolled rather than gesture recognizers so the pressed key can
    // highlight immediately and the hexagon (not its bounding box) decides
    // which key a corner touch belongs to.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        guard let index = layout.hitTest(point) else { return }
        pressedIndex = index
        longPressed = false
        setNeedsDisplay(layout.frames[index].insetBy(dx: -2, dy: -2))
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) {
            [weak self] _ in
            guard let self = self, let idx = self.pressedIndex else { return }
            self.longPressed = true
            self.clearPress()
            self.delegate?.hexBoard(self, didLongPress: self.entries[idx])
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Treat any drag as a scroll intention: cancel the press.
        guard let touch = touches.first, let index = pressedIndex else { return }
        let point = touch.location(in: self)
        if layout.hitTest(point) != index {
            longPressTimer?.invalidate()
            clearPress()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        guard let index = pressedIndex else { return }
        let entry = entries[index]
        clearPress()
        if !longPressed {
            delegate?.hexBoard(self, didTap: entry)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        clearPress()
    }

    private func clearPress() {
        if let index = pressedIndex {
            pressedIndex = nil
            setNeedsDisplay(layout.frames[index].insetBy(dx: -2, dy: -2))
        }
    }
}
