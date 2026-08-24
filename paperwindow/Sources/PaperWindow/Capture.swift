import AppKit
import ScreenCaptureKit

/// Grabs the pixels of a single window.
///
/// ScreenCaptureKit is used where it exists (macOS 14+, where the older API is
/// deprecated); everything else falls back to CGWindowListCreateImage. Both need
/// the Screen Recording permission.
enum Capture {

    /// Screen Recording permission, asking for it once if we have never been asked.
    static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        _ = CGRequestScreenCaptureAccess()
        return CGPreflightScreenCaptureAccess()
    }

    /// Capture `windowID`, calling back on the main queue. Never blocks the caller.
    static func image(of windowID: CGWindowID, completion: @escaping (CGImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image: CGImage?
            if #available(macOS 14.0, *) {
                image = modernCapture(windowID) ?? legacyCapture(windowID)
            } else {
                image = legacyCapture(windowID)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }

    // MARK: - ScreenCaptureKit

    /// Somewhere to park the result of an async capture without mutating a
    /// captured local from concurrent code.
    private final class ImageBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CGImage?
        func set(_ image: CGImage?) { lock.lock(); value = image; lock.unlock() }
        func get() -> CGImage? { lock.lock(); defer { lock.unlock() }; return value }
    }

    @available(macOS 14.0, *)
    private static func modernCapture(_ windowID: CGWindowID) -> CGImage? {
        // We are already on a background queue, so waiting here is safe; if the
        // capture does hang, the timeout drops us onto the CoreGraphics path.
        let box = ImageBox()
        let done = DispatchSemaphore(value: 0)

        Task.detached(priority: .userInitiated) {
            defer { done.signal() }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else { return }
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                let scale = CGFloat(filter.pointPixelScale)
                config.width = max(1, Int((filter.contentRect.width * scale).rounded()))
                config.height = max(1, Int((filter.contentRect.height * scale).rounded()))
                config.showsCursor = false
                box.set(try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config))
            } catch {
                box.set(nil)
            }
        }

        _ = done.wait(timeout: .now() + 5)
        return box.get()
    }

    // MARK: - CoreGraphics

    private static func legacyCapture(_ windowID: CGWindowID) -> CGImage? {
        // Deprecated on macOS 14+, still the only option below it.
        CGWindowListCreateImage(.null,
                                .optionIncludingWindow,
                                windowID,
                                [.boundsIgnoreFraming, .bestResolution])
    }
}
