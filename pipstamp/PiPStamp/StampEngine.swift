import Combine
import Foundation
import UIKit

/// Drives the whole loop: compose stamp → render frame → push to PiP,
/// on a timer (>= 60 s) and whenever the keyboard reports new context.
final class StampEngine: ObservableObject {
    enum RefreshReason: String {
        case timer, keyboard, manual, settings, launch
    }

    @Published var settings: StampSettings {
        didSet {
            // Assigning here does not re-enter didSet, so clamp and carry on.
            let clamped = settings.clamped()
            if clamped != settings { settings = clamped }
            guard clamped != oldValue else { return }
            store.settings = clamped
            DarwinNotifier.post(.settingsChanged)
            pip.canStartAutomatically = clamped.startPiPAutomatically
            updateKeepAlive()
            refresh(reason: .settings)
        }
    }

    @Published private(set) var markdown = ""
    @Published private(set) var frame: CGImage?
    @Published private(set) var seq: Int
    @Published private(set) var context: StampContext?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastReason: RefreshReason = .launch
    @Published private(set) var nextRefresh: Date?
    @Published private(set) var moduleCount: Int?

    let pip = PiPController()

    private let store = SharedStore.shared
    private let keepAlive = SilentAudioKeeper()
    private var timer: Timer?
    private var observations: [DarwinNotifier.Observation] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        settings = store.settings
        seq = store.seq
        context = store.context

        pip.canStartAutomatically = settings.startPiPAutomatically

        observations.append(DarwinNotifier.observe(.contextChanged) { [weak self] in
            guard let self else { return }
            self.context = self.store.context
            self.refresh(reason: .keyboard)
        })

        let center = NotificationCenter.default
        center.publisher(for: UIApplication.significantTimeChangeNotification)
            .sink { [weak self] _ in self?.refresh(reason: .timer) }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.refresh(reason: .manual) }
            .store(in: &cancellables)

        pip.$isActive
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateKeepAlive() }
            .store(in: &cancellables)

        // SwiftUI only watches this object; relay the PiP controller's changes.
        pip.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        refresh(reason: .launch)
    }

    // MARK: Refresh

    func refresh(reason: RefreshReason) {
        let now = Date()
        seq += 1
        let stamp = makeStamp(seq: seq, now: now)
        markdown = StampFormatter.markdown(for: stamp, settings: settings)
        moduleCount = QRRenderer.moduleCount(for: markdown, correction: settings.errorCorrection)
        frame = FrameRenderer.render(markdown: markdown,
                                     caption: caption(for: stamp),
                                     correction: settings.errorCorrection)
        if let frame { pip.show(frame) }

        lastRefresh = now
        lastReason = reason
        store.seq = seq
        store.lastMarkdown = markdown
        store.lastRefresh = now
        DarwinNotifier.post(.stampRefreshed)
        schedule(from: now)
    }

    private func schedule(from now: Date) {
        timer?.invalidate()
        let interval = TimeInterval(settings.refreshSeconds)
        nextRefresh = now.addingTimeInterval(interval)
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh(reason: .timer)
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func updateKeepAlive() {
        if pip.isActive && settings.keepAliveWithSilentAudio {
            keepAlive.start()
        } else {
            keepAlive.stop()
        }
    }

    // MARK: Composition

    private func makeStamp(seq: Int, now: Date) -> Stamp {
        var app = "unknown"
        var note: String?
        var context = self.context

        if UIApplication.shared.applicationState == .active {
            app = Bundle.main.bundleIdentifier ?? "PiPStamp"
            note = "foreground"
            context = StampContext(source: .app, capturedAt: now)
        } else if let c = context, let name = c.appName {
            app = name
            note = "\(c.source.rawValue), \(StampFormatter.ageDescription(c.age(at: now)))"
        } else if let c = context {
            note = "\(c.source.rawValue), \(StampFormatter.ageDescription(c.age(at: now)))"
        }

        return Stamp(seq: seq,
                     date: now,
                     app: app,
                     appNote: note,
                     context: context,
                     deviceName: UIDevice.current.name,
                     refreshSeconds: settings.refreshSeconds)
    }

    private static let captionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func caption(for stamp: Stamp) -> String {
        "\(Self.captionFormatter.string(from: stamp.date)) · #\(stamp.seq) · \(stamp.app)"
    }
}
