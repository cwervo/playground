import UIKit

/// Text field on top, honeycomb in the middle, category strip + backspace
/// along the bottom. Frame-based layout in viewDidLayoutSubviews.
final class KeyboardViewController: UIViewController {

    let data: HexData

    // header
    private let header = UIView()
    private let titleLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)

    // composer
    private let composer = UIView()
    let textView = UITextView()
    private let metaLabel = UILabel()

    // search
    private let searchBox = UIView()
    private let searchField = UITextField()

    // board
    private let boardTitle = UILabel()
    let scrollView = UIScrollView()
    let board = HexBoardView(frame: .zero)

    // bottom
    private let bottomBar = UIView()
    private let categoryBar = CategoryBar(frame: .zero)
    private let backspace = UIButton(type: .system)

    private var currentCategoryId = "ipa.vowels"
    private var searchQuery = ""

    private var allEntries: [HexEntry] = []
    private var entriesByChar: [String: HexEntry] = [:]

    private let defaults = UserDefaults.standard
    private let recentsKey = "hexchar.recents"
    private let favoritesKey = "hexchar.favorites"

    init(data: HexData) {
        self.data = data
        super.init(nibName: nil, bundle: nil)
        for cat in data.categories {
            for entry in cat.chars where entriesByChar[entry.c] == nil {
                entriesByChar[entry.c] = entry
                allEntries.append(entry)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: view setup

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        header.backgroundColor = Theme.accent
        titleLabel.text = "⬡ HexChar"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 19, weight: .semibold)
        copyButton.setTitle("Copy", for: .normal)
        clearButton.setTitle("Clear", for: .normal)
        for button in [copyButton, clearButton] {
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 14)
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
            button.layer.cornerRadius = 14
        }
        copyButton.addTarget(self, action: #selector(copyText), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(clearText), for: .touchUpInside)
        header.addSubview(titleLabel)
        header.addSubview(copyButton)
        header.addSubview(clearButton)

        composer.backgroundColor = Theme.panel
        textView.backgroundColor = .clear
        textView.textColor = Theme.ink
        textView.font = Theme.glyphFont(size: 24)
        textView.inputView = UIView()  // the honeycomb IS the keyboard
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        textView.delegate = self
        metaLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        metaLabel.textColor = Theme.muted
        composer.addSubview(textView)
        composer.addSubview(metaLabel)

        searchBox.backgroundColor = Theme.panel
        searchField.placeholder = "Search — “schwa”, “arrow”, U+2318"
        searchField.font = UIFont.systemFont(ofSize: 15)
        searchField.textColor = Theme.ink
        searchField.clearButtonMode = .whileEditing
        searchField.autocorrectionType = .no
        searchField.autocapitalizationType = .none
        searchField.returnKeyType = .done
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchBox.addSubview(searchField)

        boardTitle.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        boardTitle.textColor = Theme.ink

        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.addSubview(board)
        board.delegate = self

        bottomBar.backgroundColor = Theme.panel
        backspace.setTitle("⌫", for: .normal)
        backspace.setTitleColor(Theme.ink, for: .normal)
        backspace.titleLabel?.font = Theme.glyphFont(size: 20)
        backspace.backgroundColor = Theme.background
        backspace.layer.cornerRadius = 12
        backspace.addTarget(self, action: #selector(deleteBackwardTapped), for: .touchUpInside)
        categoryBar.delegate = self
        bottomBar.addSubview(categoryBar)
        bottomBar.addSubview(backspace)

        for sub in [header, composer, searchBox, boardTitle, scrollView, bottomBar] {
            view.addSubview(sub)
        }

        var items: [CategoryBar.Item] = [
            CategoryBar.Item(id: "recent", icon: "◴", label: "Recent", startsGroup: false),
            CategoryBar.Item(id: "favorites", icon: "♡", label: "Favorites", startsGroup: false),
        ]
        var lastGroup = ""
        for group in data.groups {
            for cat in group.categories {
                items.append(CategoryBar.Item(id: cat.id, icon: cat.icon, label: cat.label,
                                              startsGroup: group.label != lastGroup))
                lastGroup = group.label
            }
        }
        categoryBar.setItems(items)

        let startId = recents().isEmpty ? "ipa.vowels" : "recent"
        categoryBar.select(startId)
        showCategory(startId)
        updateMeta()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let width = view.bounds.width
        var y = safe.top

        header.frame = CGRect(x: 0, y: 0, width: width, height: y + 44)
        titleLabel.frame = CGRect(x: 14, y: y + 8, width: 200, height: 28)
        clearButton.frame = CGRect(x: width - 14 - 62, y: y + 8, width: 62, height: 28)
        copyButton.frame = CGRect(x: clearButton.frame.minX - 6 - 62, y: y + 8,
                                  width: 62, height: 28)
        y = header.frame.maxY

        composer.frame = CGRect(x: 0, y: y, width: width, height: 96)
        textView.frame = CGRect(x: 10, y: 4, width: width - 20, height: 68)
        metaLabel.frame = CGRect(x: 14, y: 74, width: width - 28, height: 18)
        y = composer.frame.maxY + 1

        searchBox.frame = CGRect(x: 0, y: y, width: width, height: 40)
        searchField.frame = CGRect(x: 14, y: 4, width: width - 28, height: 32)
        y = searchBox.frame.maxY + 1

        boardTitle.frame = CGRect(x: 14, y: y + 6, width: width - 28, height: 18)
        y = boardTitle.frame.maxY + 4

        let barHeight: CGFloat = 56 + safe.bottom
        bottomBar.frame = CGRect(x: 0, y: view.bounds.height - barHeight,
                                 width: width, height: barHeight)
        backspace.frame = CGRect(x: width - 6 - 52, y: 6, width: 52, height: 44)
        categoryBar.frame = CGRect(x: 0, y: 0, width: backspace.frame.minX - 6, height: 56)

        scrollView.frame = CGRect(x: 0, y: y, width: width,
                                  height: bottomBar.frame.minY - y)
        relayoutBoard()
    }

    private func relayoutBoard() {
        let inset: CGFloat = 12
        let boardWidth = scrollView.bounds.width - inset * 2
        guard boardWidth > 50 else { return }
        board.setEntries(board.entries, boardWidth: boardWidth)
        board.frame = CGRect(x: inset, y: 8, width: boardWidth,
                             height: max(board.contentHeight, 1))
        scrollView.contentSize = CGSize(width: scrollView.bounds.width,
                                        height: board.frame.maxY + 16)
    }

    // MARK: state

    private func recents() -> [String] {
        defaults.stringArray(forKey: recentsKey) ?? []
    }

    private func favorites() -> [String] {
        defaults.stringArray(forKey: favoritesKey) ?? []
    }

    private func remember(_ ch: String) {
        var list = recents()
        list.removeAll { $0 == ch }
        list.insert(ch, at: 0)
        if list.count > 60 { list.removeLast(list.count - 60) }
        defaults.set(list, forKey: recentsKey)
    }

    private func toggleFavorite(_ ch: String) -> Bool {
        var list = favorites()
        if let index = list.firstIndex(of: ch) {
            list.remove(at: index)
        } else {
            list.insert(ch, at: 0)
        }
        defaults.set(list, forKey: favoritesKey)
        return list.contains(ch)
    }

    private func entry(for ch: String) -> HexEntry {
        entriesByChar[ch] ?? HexEntry(c: ch, n: "Unicode Character",
                                      g: nil, m: nil, d: nil, e: nil)
    }

    func entries(forCategoryId id: String) -> [HexEntry] {
        if id == "recent" { return recents().map(entry(for:)) }
        if id == "favorites" { return favorites().map(entry(for:)) }
        return data.categories.first { $0.id == id }?.chars ?? []
    }

    func showCategory(_ id: String) {
        currentCategoryId = id
        searchQuery = ""
        searchField.text = ""
        let entries = self.entries(forCategoryId: id)
        let label: String
        switch id {
        case "recent": label = "RECENT"
        case "favorites": label = "FAVORITES"
        default:
            let cat = data.categories.first { $0.id == id }
            label = (data.groupLabel(forCategoryId: id) + " · "
                     + (cat?.label ?? "")).uppercased()
        }
        boardTitle.text = label + "   \(entries.count)"
        board.setEntries(entries, boardWidth: max(board.bounds.width, 1))
        relayoutBoard()
        scrollView.setContentOffset(.zero, animated: false)
    }

    private func showSearch(_ query: String) {
        searchQuery = query
        let results = HexSearch.search(query, in: allEntries)
        boardTitle.text = "SEARCH   \(results.count)"
        categoryBar.deselect()
        board.setEntries(results, boardWidth: max(board.bounds.width, 1))
        relayoutBoard()
        scrollView.setContentOffset(.zero, animated: false)
    }

    // MARK: text editing

    private func insert(_ ch: String) {
        textView.insertText(ch)
        remember(ch)
        updateMeta()
    }

    @objc private func deleteBackwardTapped() {
        let text = textView.text ?? ""
        let sel = textView.selectedRange
        guard let result = HexUnicode.deletingBackward(text, location: sel.location,
                                                       length: sel.length) else { return }
        textView.text = result.text
        textView.selectedRange = NSRange(location: result.caret, length: 0)
        updateMeta()
    }

    func updateMeta() {
        let text = textView.text ?? ""
        let count = text.unicodeScalars.count
        if count == 0 {
            metaLabel.text = "empty"
        } else {
            let tail = HexUnicode.codePoints(String(text.suffix(4))).joined(separator: " ")
            metaLabel.text = "\(count) code point\(count == 1 ? "" : "s") · \(tail)"
        }
    }

    @objc private func copyText() {
        let text = textView.text ?? ""
        if !text.isEmpty { UIPasteboard.general.string = text }
    }

    @objc private func clearText() {
        textView.text = ""
        updateMeta()
    }

    @objc private func searchChanged() {
        let query = searchField.text ?? ""
        if query.isEmpty {
            categoryBar.select(currentCategoryId)
            showCategory(currentCategoryId)
        } else {
            showSearch(query)
        }
    }

    // MARK: detail card

    private func showDetail(for entry: HexEntry) {
        var facts = ["Code point  " + HexUnicode.codePoints(entry.c).joined(separator: " ")]
        if let g = entry.g { facts.append("Category  " + g) }
        facts.append("HTML  " + HexUnicode.htmlEntity(entry.c))
        facts.append("Swift  " + HexUnicode.swiftEscape(entry.c))
        facts.append("UTF-8  " + HexUnicode.utf8Hex(entry.c))

        let alert = UIAlertController(title: HexUnicode.displayText(for: entry) + "  " + entry.n,
                                      message: facts.joined(separator: "\n"),
                                      preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Insert", style: .default) { [weak self] _ in
            self?.insert(entry.c)
        })
        alert.addAction(UIAlertAction(title: "Copy character", style: .default) { _ in
            UIPasteboard.general.string = entry.c
        })
        let favTitle = favorites().contains(entry.c) ? "Unfavorite" : "Favorite"
        alert.addAction(UIAlertAction(title: favTitle, style: .default) { [weak self] _ in
            guard let self = self else { return }
            _ = self.toggleFavorite(entry.c)
            if self.currentCategoryId == "favorites" && self.searchQuery.isEmpty {
                self.showCategory("favorites")
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = board
            popover.sourceRect = CGRect(x: board.bounds.midX, y: board.bounds.midY,
                                        width: 1, height: 1)
        }
        present(alert, animated: true)
    }
}

extension KeyboardViewController: HexBoardViewDelegate {
    func hexBoard(_ board: HexBoardView, didTap entry: HexEntry) {
        insert(entry.c)
    }

    func hexBoard(_ board: HexBoardView, didLongPress entry: HexEntry) {
        showDetail(for: entry)
    }
}

extension KeyboardViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateMeta()
    }
}

extension KeyboardViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
