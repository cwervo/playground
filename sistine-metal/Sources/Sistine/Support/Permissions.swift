import Foundation
import AVFoundation
import ApplicationServices

enum Permissions {
    /// Camera access is a TCC prompt; it is attributed to the *bundle*, which is
    /// why Scripts/make-app.sh exists. A bare SwiftPM binary asks on behalf of
    /// whatever launched it, and the grant does not survive.
    static func requestCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Posting to the HID event tap requires Accessibility. There is no API to
    /// grant it — `prompt: true` opens the right pane in System Settings and the
    /// user has to toggle it, then relaunch.
    @discardableResult
    static func requestAccessibility(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }
}
