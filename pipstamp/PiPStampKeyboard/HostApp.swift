import UIKit

/// Resolves the bundle identifier of the app hosting the keyboard.
///
/// iOS has no public API for this. The only known route reads a private
/// property, which is not App Store safe, so it is compiled out unless the
/// `PIPSTAMP_PRIVATE_HOST_ID` flag is set (see project.yml). Without it the
/// user tags the host app with the label chips in the keyboard instead.
enum HostApp {
    static func bundleIdentifier(for controller: UIInputViewController) -> String? {
        #if PIPSTAMP_PRIVATE_HOST_ID
        let selector = NSSelectorFromString("_hostBundleID")
        for candidate in [controller.parent as NSObject?, controller as NSObject] {
            if let object = candidate, object.responds(to: selector),
               let value = object.perform(selector)?.takeUnretainedValue() as? String {
                return value
            }
        }
        return nil
        #else
        return nil
        #endif
    }
}
