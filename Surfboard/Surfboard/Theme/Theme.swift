//
//  Theme.swift
//  Surfboard
//
//  Central place for the app's colours and typography so the whole UI stays
//  consistent. Colours are defined in code (no asset dependency required) and
//  the type helpers fall back gracefully to the system font if the bundled
//  IBM Plex families are not installed.
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Colours

    /// Peach — the dominant surface colour used across the app.
    static let peach       = Color(hex: 0xFFD9B8)
    /// A slightly deeper peach for cards and raised surfaces.
    static let peachDeep   = Color(hex: 0xFFC79A)
    /// The palest peach, used for large backgrounds behind cards.
    static let peachPale   = Color(hex: 0xFFEBDA)

    /// #1010FF — the electric-blue accent used for interactive elements.
    static let accent      = Color(hex: 0x1010FF)

    /// High-contrast ink for text on peach surfaces.
    static let ink         = Color(hex: 0x201408)
    /// Muted ink for secondary text.
    static let inkMuted    = Color(hex: 0x6B5A46)

    /// Warning red for destructive confirmations.
    static let danger      = Color(hex: 0xE01E1E)

    // MARK: - Typography

    /// Names of the bundled font faces. If these aren't present the helpers
    /// below transparently fall back to the system font.
    private enum FaceName {
        static let sansRegular  = "IBMPlexSans"
        static let sansMedium   = "IBMPlexSans-Medium"
        static let sansSemiBold = "IBMPlexSans-SemiBold"
        static let sansBold     = "IBMPlexSans-Bold"
        static let monoRegular  = "IBMPlexMono"
        static let monoMedium   = "IBMPlexMono-Medium"
    }

    /// Title / body face: IBM Plex Sans.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = FaceName.sansBold
        case .semibold:             name = FaceName.sansSemiBold
        case .medium:               name = FaceName.sansMedium
        default:                    name = FaceName.sansRegular
        }
        if fontExists(name) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// Code / instruction face: IBM Plex Mono.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = (weight == .medium || weight == .semibold || weight == .bold)
            ? FaceName.monoMedium
            : FaceName.monoRegular
        if fontExists(name) {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    private static func fontExists(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }
}

// MARK: - Convenience initialisers

extension Color {
    /// Create a colour from a 0xRRGGBB integer literal.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Reusable text styles

extension View {
    /// App title styling (IBM Plex Sans, bold).
    func titleStyle(_ size: CGFloat = 22) -> some View {
        font(Theme.sans(size, weight: .bold)).foregroundStyle(Theme.ink)
    }

    /// Body copy styling (IBM Plex Sans).
    func bodyStyle(_ size: CGFloat = 16) -> some View {
        font(Theme.sans(size)).foregroundStyle(Theme.ink)
    }

    /// Instructional / code styling (IBM Plex Mono).
    func instructionStyle(_ size: CGFloat = 13) -> some View {
        font(Theme.mono(size)).foregroundStyle(Theme.inkMuted)
    }
}
