import AppKit

/// The little instruction card that fades away once you have got the idea.
final class HUDView: NSView {

    private let label = NSTextField(labelWithString: "")

    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        layer?.cornerRadius = 10

        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.stringValue = text
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Mouse events belong to the paper underneath, not to this card.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func fadeOut(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.8
                self.animator().alphaValue = 0
            }
        }
    }
}
