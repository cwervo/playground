import UIKit
import CoreText

/// Palette matching the web version, light and dark via dynamic colors.
enum Theme {
    static let accent = UIColor(red: 0x16 / 255.0, green: 0xB0 / 255.0,
                                blue: 0xEA / 255.0, alpha: 1)
    static let accentDeep = UIColor(red: 0x0B / 255.0, green: 0x93 / 255.0,
                                    blue: 0xC8 / 255.0, alpha: 1)

    static let background = dynamic(light: rgb(0xF5, 0xF7, 0xF9), dark: rgb(0x0E, 0x12, 0x16))
    static let panel      = dynamic(light: rgb(0xFF, 0xFF, 0xFF), dark: rgb(0x16, 0x1B, 0x21))
    static let ink        = dynamic(light: rgb(0x13, 0x19, 0x20), dark: rgb(0xE9, 0xEE, 0xF4))
    static let muted      = dynamic(light: rgb(0x77, 0x83, 0x8F), dark: rgb(0x8C, 0x96, 0xA2))
    static let line       = dynamic(light: rgb(0xE2, 0xE7, 0xEC), dark: rgb(0x23, 0x2A, 0x32))
    static let keyFill    = dynamic(light: rgb(0xFF, 0xFF, 0xFF), dark: rgb(0x17, 0x1D, 0x24))
    static let keyLine    = dynamic(light: rgb(0xCD, 0xD5, 0xDD), dark: rgb(0x2E, 0x37, 0x41))

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0, alpha: 1)
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }

    /// Noto Sans when a .ttf/.otf for it is bundled (see ios/Fonts/); the
    /// system font otherwise. CoreText's cascade fills in symbols either way.
    static func glyphFont(size: CGFloat) -> UIFont {
        for name in ["NotoSans-Regular", "NotoSans"] {
            if let font = UIFont(name: name, size: size) { return font }
        }
        return UIFont.systemFont(ofSize: size)
    }

    static func registerBundledFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
