import UIKit

/// A compact keyboard with a "stamp bar" on top:
/// capture the host field's context, insert the Markdown stamp, tag the
/// host app, and show the live QR code inside the keyboard itself.
final class KeyboardViewController: UIInputViewController {
    private let store = SharedStore.shared
    private var settings = StampSettings()

    private let stampBar = UIStackView()
    private let chipScroll = UIScrollView()
    private let chipRow = UIStackView()
    private let qrPanel = UIImageView()
    private let statusLabel = UILabel()
    private let keysStack = UIStackView()
    private var heightConstraint: NSLayoutConstraint?

    private var shifted = false
    private var letterButtons: [UIButton] = []
    private var selectedLabel: String?
    private var captureWorkItem: DispatchWorkItem?
    private var refreshObservation: DarwinNotifier.Observation?
    private var settingsObservation: DarwinNotifier.Observation?

    private let rows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        settings = store.settings
        buildUI()
        refreshObservation = DarwinNotifier.observe(.stampRefreshed) { [weak self] in
            self?.renderQRPanel()
        }
        settingsObservation = DarwinNotifier.observe(.settingsChanged) { [weak self] in
            guard let self else { return }
            self.settings = self.store.settings
            self.rebuildChips()
            self.applyPanelVisibility()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        settings = store.settings
        rebuildChips()
        applyPanelVisibility()
        updateStatus()
        renderQRPanel()
        if settings.autoCaptureWhileTyping { scheduleCapture(delay: 0.3) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if settings.autoCaptureWhileTyping { scheduleCapture(delay: 1.5) }
    }

    // MARK: UI

    private func buildUI() {
        view.backgroundColor = UIColor.secondarySystemBackground

        let root = UIStackView()
        root.axis = .vertical
        root.spacing = 6
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
        ])

        stampBar.axis = .horizontal
        stampBar.spacing = 6
        stampBar.distribution = .fillEqually
        stampBar.addArrangedSubview(makeActionButton("Capture", symbol: "record.circle", action: #selector(captureTapped)))
        stampBar.addArrangedSubview(makeActionButton("Insert", symbol: "text.insert", action: #selector(insertTapped)))
        stampBar.addArrangedSubview(makeActionButton("QR", symbol: "qrcode", action: #selector(toggleQRTapped)))
        root.addArrangedSubview(stampBar)
        stampBar.heightAnchor.constraint(equalToConstant: 36).isActive = true

        chipRow.axis = .horizontal
        chipRow.spacing = 6
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        chipScroll.showsHorizontalScrollIndicator = false
        chipScroll.addSubview(chipRow)
        NSLayoutConstraint.activate([
            chipRow.leadingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.leadingAnchor),
            chipRow.trailingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.trailingAnchor),
            chipRow.topAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.topAnchor),
            chipRow.bottomAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.bottomAnchor),
            chipRow.heightAnchor.constraint(equalTo: chipScroll.frameLayoutGuide.heightAnchor),
        ])
        chipScroll.heightAnchor.constraint(equalToConstant: 28).isActive = true
        root.addArrangedSubview(chipScroll)

        qrPanel.contentMode = .scaleAspectFit
        qrPanel.backgroundColor = .white
        qrPanel.layer.cornerRadius = 8
        qrPanel.layer.magnificationFilter = .nearest
        qrPanel.clipsToBounds = true
        qrPanel.heightAnchor.constraint(equalToConstant: 150).isActive = true
        root.addArrangedSubview(qrPanel)

        statusLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 1
        root.addArrangedSubview(statusLabel)

        keysStack.axis = .vertical
        keysStack.spacing = 6
        keysStack.distribution = .fillEqually
        for (index, row) in rows.enumerated() {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 5
            rowStack.distribution = .fillEqually
            if index == 2 {
                rowStack.addArrangedSubview(makeKey("⇧", action: #selector(shiftTapped)))
            }
            for letter in row {
                let key = makeKey(letter, action: #selector(letterTapped(_:)))
                letterButtons.append(key)
                rowStack.addArrangedSubview(key)
            }
            if index == 2 {
                rowStack.addArrangedSubview(makeKey("⌫", action: #selector(deleteTapped)))
            }
            let wrapper = UIStackView(arrangedSubviews: [rowStack])
            wrapper.alignment = .fill
            if index == 1 {
                wrapper.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
                wrapper.isLayoutMarginsRelativeArrangement = true
            }
            keysStack.addArrangedSubview(wrapper)
        }

        let bottom = UIStackView()
        bottom.axis = .horizontal
        bottom.spacing = 5
        if needsInputModeSwitchKey {
            let globe = makeKey("🌐", action: nil)
            globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
            globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
            bottom.addArrangedSubview(globe)
        }
        let space = makeKey("space", action: #selector(spaceTapped))
        bottom.addArrangedSubview(space)
        let ret = makeKey("return", action: #selector(returnTapped))
        ret.widthAnchor.constraint(equalToConstant: 80).isActive = true
        bottom.addArrangedSubview(ret)
        keysStack.addArrangedSubview(bottom)
        root.addArrangedSubview(keysStack)
    }

    private func makeActionButton(_ title: String, symbol: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 4
        config.buttonSize = .small
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeKey(_ title: String, action: Selector?) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18)
        button.backgroundColor = .systemBackground
        button.setTitleColor(.label, for: .normal)
        button.layer.cornerRadius = 6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.25
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 0
        if let action { button.addTarget(self, action: action, for: .touchUpInside) }
        return button
    }

    private func rebuildChips() {
        chipRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for label in settings.hostLabels {
            var config = label == selectedLabel
                ? UIButton.Configuration.filled()
                : UIButton.Configuration.tinted()
            config.title = label
            config.buttonSize = .mini
            config.cornerStyle = .capsule
            let chip = UIButton(configuration: config)
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            chipRow.addArrangedSubview(chip)
        }
        chipScroll.isHidden = settings.hostLabels.isEmpty
    }

    private func applyPanelVisibility() {
        qrPanel.isHidden = !settings.showQRInKeyboard
        applyHeight()
    }

    private func applyHeight() {
        let height: CGFloat = settings.showQRInKeyboard ? 470 : 314
        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: height)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    private func updateStatus() {
        if !hasFullAccess {
            statusLabel.text = "Allow Full Access to send captures to PiPStamp"
            statusLabel.textColor = .systemOrange
            return
        }
        statusLabel.textColor = .secondaryLabel
        let seq = store.seq
        if let last = store.lastRefresh {
            let age = StampFormatter.ageDescription(Date().timeIntervalSince(last))
            statusLabel.text = "stamp #\(seq) · \(age) · every \(settings.refreshSeconds)s"
        } else {
            statusLabel.text = "open PiPStamp once to start the stamp loop"
        }
    }

    // MARK: Context capture

    private func scheduleCapture(delay: TimeInterval) {
        captureWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.capture(source: .keyboard) }
        captureWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func currentContext(source: StampContext.Source) -> StampContext {
        let proxy = textDocumentProxy
        let docID = String(proxy.documentIdentifier.uuidString.prefix(8))
        return StampContext(source: source,
                            capturedAt: Date(),
                            hostBundleID: HostApp.bundleIdentifier(for: self),
                            hostLabel: selectedLabel,
                            documentID: docID,
                            keyboardType: Self.describe(proxy.keyboardType),
                            returnKeyType: Self.describe(proxy.returnKeyType),
                            textBefore: proxy.documentContextBeforeInput,
                            textAfter: proxy.documentContextAfterInput,
                            selectedText: proxy.selectedText)
    }

    @discardableResult
    private func capture(source: StampContext.Source) -> StampContext {
        let context = currentContext(source: source)
        if hasFullAccess {
            store.context = context
            DarwinNotifier.post(.contextChanged)
        }
        renderQRPanel(with: context)
        updateStatus()
        return context
    }

    /// The keyboard renders its own QR so it stays right even when the app
    /// has not caught up yet, or Full Access is off.
    private func renderQRPanel(with context: StampContext? = nil) {
        guard settings.showQRInKeyboard else { return }
        let ctx = context ?? currentContext(source: .keyboard)
        let stamp = Stamp(seq: store.seq,
                          date: Date(),
                          app: ctx.appName ?? "unknown",
                          appNote: "keyboard",
                          context: ctx,
                          deviceName: UIDevice.current.model,
                          refreshSeconds: settings.refreshSeconds)
        let markdown = StampFormatter.markdown(for: stamp, settings: settings)
        if let cg = QRRenderer.image(for: markdown,
                                     correction: settings.errorCorrection,
                                     pixelSize: 300) {
            qrPanel.image = UIImage(cgImage: cg)
        }
    }

    private func stampMarkdown() -> String {
        let ctx = capture(source: .keyboard)
        let stamp = Stamp(seq: store.seq,
                          date: Date(),
                          app: ctx.appName ?? "unknown",
                          appNote: "keyboard",
                          context: ctx,
                          deviceName: UIDevice.current.model,
                          refreshSeconds: settings.refreshSeconds)
        return StampFormatter.markdown(for: stamp, settings: settings)
    }

    // MARK: Actions

    @objc private func captureTapped() { capture(source: .keyboard) }

    @objc private func insertTapped() {
        textDocumentProxy.insertText(stampMarkdown() + "\n")
    }

    @objc private func toggleQRTapped() {
        settings.showQRInKeyboard.toggle()
        if hasFullAccess {
            store.settings = settings
            DarwinNotifier.post(.settingsChanged)
        }
        applyPanelVisibility()
        renderQRPanel()
    }

    @objc private func chipTapped(_ sender: UIButton) {
        let title = sender.configuration?.title
        selectedLabel = (selectedLabel == title) ? nil : title
        rebuildChips()
        capture(source: .manual)
    }

    @objc private func letterTapped(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        textDocumentProxy.insertText(shifted ? title.uppercased() : title.lowercased())
        if shifted { shifted = false; applyShift() }
    }

    @objc private func shiftTapped() {
        shifted.toggle()
        applyShift()
    }

    private func applyShift() {
        for button in letterButtons {
            let title = button.title(for: .normal) ?? ""
            button.setTitle(shifted ? title.uppercased() : title.lowercased(), for: .normal)
        }
    }

    @objc private func deleteTapped() { textDocumentProxy.deleteBackward() }
    @objc private func spaceTapped() { textDocumentProxy.insertText(" ") }
    @objc private func returnTapped() { textDocumentProxy.insertText("\n") }

    // MARK: Describing proxy enums

    private static func describe(_ type: UIKeyboardType?) -> String? {
        guard let type else { return nil }
        switch type {
        case .default: return "default"
        case .asciiCapable: return "ascii"
        case .numbersAndPunctuation: return "numbersAndPunctuation"
        case .URL: return "url"
        case .numberPad: return "numberPad"
        case .phonePad: return "phonePad"
        case .namePhonePad: return "namePhonePad"
        case .emailAddress: return "email"
        case .decimalPad: return "decimalPad"
        case .twitter: return "twitter"
        case .webSearch: return "webSearch"
        case .asciiCapableNumberPad: return "asciiNumberPad"
        @unknown default: return "other"
        }
    }

    private static func describe(_ type: UIReturnKeyType?) -> String? {
        guard let type else { return nil }
        switch type {
        case .default: return "default"
        case .go: return "go"
        case .google: return "google"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .search: return "search"
        case .send: return "send"
        case .yahoo: return "yahoo"
        case .done: return "done"
        case .emergencyCall: return "emergencyCall"
        case .continue: return "continue"
        @unknown default: return "other"
        }
    }
}
