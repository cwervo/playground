import UIKit

protocol CategoryBarDelegate: AnyObject {
    func categoryBar(_ bar: CategoryBar, didSelect id: String)
}

/// Horizontally scrolling category strip along the bottom, like the web
/// version: Recent and Favorites first, then every category, with a thin
/// separator between groups.
final class CategoryBar: UIView {

    struct Item {
        let id: String
        let icon: String
        let label: String
        let startsGroup: Bool
    }

    weak var delegate: CategoryBarDelegate?
    private let scroll = UIScrollView()
    private var buttons: [UIButton] = []
    private var items: [Item] = []
    private(set) var selectedId: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.panel
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setItems(_ newItems: [Item]) {
        items = newItems
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        for (index, item) in items.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.layer.cornerRadius = 12
            button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            style(button, item: item, selected: item.id == selectedId)
            scroll.addSubview(button)
            buttons.append(button)
        }
        setNeedsLayout()
    }

    func select(_ id: String) {
        selectedId = id
        for (index, item) in items.enumerated() {
            style(buttons[index], item: item, selected: item.id == id)
        }
        if let index = items.firstIndex(where: { $0.id == id }) {
            scroll.scrollRectToVisible(buttons[index].frame.insetBy(dx: -24, dy: 0),
                                       animated: true)
        }
    }

    /// No selected category (search mode).
    func deselect() {
        selectedId = ""
        for (index, item) in items.enumerated() {
            style(buttons[index], item: item, selected: false)
        }
    }

    private func style(_ button: UIButton, item: Item, selected: Bool) {
        let icon = NSMutableAttributedString(
            string: item.icon + "\n",
            attributes: [
                .font: Theme.glyphFont(size: 19),
                .foregroundColor: selected ? UIColor.white : Theme.muted,
            ])
        icon.append(NSAttributedString(
            string: item.label,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: selected ? UIColor.white : Theme.muted,
            ]))
        button.setAttributedTitle(icon, for: .normal)
        button.backgroundColor = selected ? Theme.accent : .clear
    }

    @objc private func tapped(_ sender: UIButton) {
        let item = items[sender.tag]
        select(item.id)
        delegate?.categoryBar(self, didSelect: item.id)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        var x: CGFloat = 6
        for (index, item) in items.enumerated() {
            if item.startsGroup && index > 0 { x += 8 }
            let width = max(56, (item.label as NSString).size(
                withAttributes: [.font: UIFont.systemFont(ofSize: 10)]).width + 18)
            buttons[index].frame = CGRect(x: x, y: 4, width: width,
                                          height: bounds.height - 8)
            x += width + 4
        }
        scroll.contentSize = CGSize(width: x + 6, height: bounds.height)
    }
}
