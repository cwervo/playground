import AppKit

/// Drives the whole show: pick a window, capture it, put a paper double on
/// screen, and put everything back when esc is pressed.
final class AppController: NSObject, NSApplicationDelegate, PickerViewDelegate, PaperViewDelegate {

    private let options: Options

    private var pickerWindow: OverlayWindow?
    private var paperWindow: OverlayWindow?
    private var paperView: PaperView?
    private var mover: AXWindowMover?
    private var liveTimer: Timer?
    private var target: WindowInfo?
    private var keyMonitor: Any?
    private var signalSources: [DispatchSourceSignal] = []

    init(options: Options) {
        self.options = options
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        // Belt and braces: the view handles esc, this catches it if focus has
        // wandered somewhere odd inside our own app.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.tearDownAndQuit()
                return nil
            }
            return event
        }

        installSignalHandlers()

        if let id = options.windowID {
            guard let info = WindowList.window(withID: id) else {
                fail("no on-screen window with id \(id). Try --list.")
                return
            }
            begin(with: info)
        } else if let name = options.appName {
            guard let info = WindowList.firstWindow(ofApp: name) else {
                fail("no on-screen window belonging to an app matching \"\(name)\". Try --list.")
                return
            }
            begin(with: info)
        } else {
            showPicker()
        }
    }

    /// Ctrl-C must not leave someone's window parked off screen, so handle the
    /// usual terminating signals on the main queue where AX calls are safe.
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in self?.tearDownAndQuit() }
            source.resume()
            signalSources.append(source)
        }
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data(("paperwindow: " + message + "\n").utf8))
        NSApp.terminate(nil)
    }

    // MARK: - Picking

    private func showPicker() {
        let frame = Coords.screensUnion
        let window = OverlayWindow(frame: frame)
        let view = PickerView(frame: CGRect(origin: .zero, size: frame.size),
                              originInScreen: frame.origin)
        view.delegate = self
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        pickerWindow = window
    }

    func pickerView(_ view: PickerView, didPick window: WindowInfo) {
        dismissPicker()
        begin(with: window)
    }

    func pickerViewDidCancel(_ view: PickerView) {
        tearDownAndQuit()
    }

    private func dismissPicker() {
        pickerWindow?.orderOut(nil)
        pickerWindow = nil
    }

    // MARK: - Paper mode

    private func begin(with info: WindowInfo) {
        target = info
        Capture.image(of: info.id) { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.fail("could not capture that window. Grant Screen Recording in System Settings › Privacy & Security.")
                return
            }
            self.present(image: image, for: info)
        }
    }

    private func present(image: CGImage, for info: WindowInfo) {
        let overlayFrame = Coords.screensUnion
        // The window's rest rectangle, expressed in the overlay view's own space.
        let restInScreen = Coords.nsRect(fromCG: info.bounds)
        let restInView = restInScreen.offsetBy(dx: -overlayFrame.origin.x, dy: -overlayFrame.origin.y)

        let window = OverlayWindow(frame: overlayFrame)
        guard let view = PaperView(frame: CGRect(origin: .zero, size: overlayFrame.size),
                                   image: image,
                                   restRect: restInView,
                                   options: options) else {
            fail("could not set up Metal rendering on this machine.")
            return
        }
        view.paperDelegate = self
        view.autoresizingMask = [.width, .height]

        let container = NSView(frame: CGRect(origin: .zero, size: overlayFrame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(view)

        let hud = HUDView(text: "drag the corners  ·  space to flap  ·  g gravity  ·  r reset  ·  esc to put it back")
        hud.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hud.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -48)
        ])
        hud.fadeOut(after: 4)

        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        paperWindow = window
        paperView = view

        // Get the real window out from under the paper, if we are allowed to.
        if options.hideOriginal {
            mover = AXWindowMover(pid: info.pid, bounds: info.bounds)
            if let mover = mover {
                mover.hide()
            } else if !AXWindowMover.isTrusted {
                FileHandle.standardError.write(Data("""
                paperwindow: no Accessibility permission, so the real window stays put \
                and may peek out from under the sheet. Grant it in System Settings › \
                Privacy & Security › Accessibility, or pass --keep-original to silence this.

                """.utf8))
            }
        }

        if options.live { startLiveCapture(of: info) }
    }

    // MARK: - Live capture

    private func startLiveCapture(of info: WindowInfo) {
        var inFlight = false
        let timer = Timer(timeInterval: 1.0 / options.liveFPS, repeats: true) { [weak self] _ in
            guard let self, let view = self.paperView, !inFlight else { return }
            inFlight = true
            Capture.image(of: info.id) { image in
                inFlight = false
                if let image { view.updateTexture(image) }
            }
        }
        // .common so the re-captures keep going while a drag is in progress.
        RunLoop.main.add(timer, forMode: .common)
        liveTimer = timer
    }

    // MARK: - Teardown

    func paperViewDidRequestExit(_ view: PaperView) {
        tearDownAndQuit()
    }

    private func tearDownAndQuit() {
        liveTimer?.invalidate()
        liveTimer = nil
        mover?.restore()
        mover = nil
        paperWindow?.orderOut(nil)
        paperWindow = nil
        paperView = nil
        dismissPicker()
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave someone's window parked off screen.
        mover?.restore()
    }
}
