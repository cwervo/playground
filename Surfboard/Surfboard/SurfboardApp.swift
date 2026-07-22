//
//  SurfboardApp.swift
//  Surfboard
//
//  Entry point. Registers the bundled IBM Plex fonts (if present) and hosts
//  the three-panel interface. Uses only SwiftUI + CoreText from Apple's SDK.
//

import SwiftUI
import CoreText

@main
struct SurfboardApp: App {

    @StateObject private var store = ClipStore()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}

/// Registers any `.ttf`/`.otf` files bundled under Resources/Fonts so the
/// custom font helpers in `Theme` resolve. This is a no-op (and the UI falls
/// back to system fonts) if no font files are shipped.
enum FontRegistrar {
    static func registerBundledFonts() {
        let extensions = ["ttf", "otf"]
        for ext in extensions {
            let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            for url in urls {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                // Duplicate registration errors are expected on hot-reload and
                // are safe to ignore.
            }
        }
    }
}
