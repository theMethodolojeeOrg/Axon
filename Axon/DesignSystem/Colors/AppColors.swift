//
//  AppColors.swift
//  Axon
//
//  Design System Colors - Mineral-Inspired Theme (Light + Dark)
//

import SwiftUI

struct AppColors {

    // MARK: - Palette

    private struct Palette {
        // Substrate
        let substratePrimary: Color
        let substrateSecondary: Color
        let substrateTertiary: Color
        let substrateElevated: Color

        // Signals
        let signalMercury: Color
        let signalMercuryLight: Color
        let signalMercuryDark: Color

        let signalLichen: Color
        let signalLichenLight: Color
        let signalLichenDark: Color

        let signalCopper: Color
        let signalCopperLight: Color
        let signalCopperDark: Color

        let signalHematite: Color
        let signalHematiteLight: Color
        let signalHematiteDark: Color

        let signalSaturn: Color
        let signalSaturnLight: Color
        let signalSaturnDark: Color

        // Text
        let textPrimary: Color
        let textSecondary: Color
        let textTertiary: Color
        let textDisabled: Color

        // Accents
        let accentPrimary: Color
        let accentSuccess: Color
        let accentWarning: Color
        let accentError: Color

        // Glass
        let glassOverlay: Color
        let glassBorder: Color

        // Dividers
        let divider: Color
        let dividerStrong: Color

        // Shadows
        let shadow: Color
        let shadowStrong: Color
    }

    // Existing mineral signal colors work well in both schemes
    private static let sharedSignals = (
        mercury: Color(hex: "3f6f7a"),
        mercuryLight: Color(hex: "5a8a96"),
        mercuryDark: Color(hex: "2a4a52"),
        lichen: Color(hex: "5f7f5f"),
        lichenLight: Color(hex: "7a9a7a"),
        lichenDark: Color(hex: "4a644a"),
        copper: Color(hex: "b2763a"),
        copperLight: Color(hex: "cc9055"),
        copperDark: Color(hex: "8a5c2e"),
        hematite: Color(hex: "6b5a5a"),
        hematiteLight: Color(hex: "867575"),
        hematiteDark: Color(hex: "503f3f"),
        // Saturn: A dusty gold/ochre evoking the planet's bands and alchemical lead.
        // Represents temporal cycles, the passage of turns, and ringed majesty.
        saturn: Color(hex: "9a8a5a"),
        saturnLight: Color(hex: "b5a575"),
        saturnDark: Color(hex: "7a6a45")
    )

    private static let dark = Palette(
        // Substrate (existing)
        substratePrimary: Color(hex: "161a1b"),
        substrateSecondary: Color(hex: "1e2324"),
        substrateTertiary: Color(hex: "262b2d"),
        substrateElevated: Color(hex: "2e3436"),

        // Signals
        signalMercury: sharedSignals.mercury,
        signalMercuryLight: sharedSignals.mercuryLight,
        signalMercuryDark: sharedSignals.mercuryDark,

        signalLichen: sharedSignals.lichen,
        signalLichenLight: sharedSignals.lichenLight,
        signalLichenDark: sharedSignals.lichenDark,

        signalCopper: sharedSignals.copper,
        signalCopperLight: sharedSignals.copperLight,
        signalCopperDark: sharedSignals.copperDark,

        signalHematite: sharedSignals.hematite,
        signalHematiteLight: sharedSignals.hematiteLight,
        signalHematiteDark: sharedSignals.hematiteDark,

        signalSaturn: sharedSignals.saturn,
        signalSaturnLight: sharedSignals.saturnLight,
        signalSaturnDark: sharedSignals.saturnDark,

        // Text (existing)
        textPrimary: Color.white.opacity(0.95),
        textSecondary: Color.white.opacity(0.65),
        textTertiary: Color.white.opacity(0.45),
        textDisabled: Color.white.opacity(0.25),

        // Accents
        accentPrimary: sharedSignals.mercury,
        accentSuccess: sharedSignals.lichen,
        accentWarning: sharedSignals.copper,
        accentError: Color(hex: "d32f2f"),

        // Glass
        glassOverlay: Color.white.opacity(0.05),
        glassBorder: Color.white.opacity(0.1),

        // Dividers
        divider: Color.white.opacity(0.08),
        dividerStrong: Color.white.opacity(0.12),

        // Shadows
        shadow: Color.black.opacity(0.3),
        shadowStrong: Color.black.opacity(0.5)
    )

    private static let light = Palette(
        // Substrate (new)
        // A neutral, slightly cool light scheme that preserves the "mineral" feel.
        substratePrimary: Color(hex: "F6F7F8"),
        substrateSecondary: Color(hex: "FFFFFF"),
        substrateTertiary: Color(hex: "EEF1F3"),
        substrateElevated: Color(hex: "FFFFFF"),

        // Signals
        signalMercury: sharedSignals.mercury,
        signalMercuryLight: sharedSignals.mercuryLight,
        signalMercuryDark: sharedSignals.mercuryDark,

        signalLichen: sharedSignals.lichen,
        signalLichenLight: sharedSignals.lichenLight,
        signalLichenDark: sharedSignals.lichenDark,

        signalCopper: sharedSignals.copper,
        signalCopperLight: sharedSignals.copperLight,
        signalCopperDark: sharedSignals.copperDark,

        signalHematite: sharedSignals.hematite,
        signalHematiteLight: sharedSignals.hematiteLight,
        signalHematiteDark: sharedSignals.hematiteDark,

        signalSaturn: sharedSignals.saturn,
        signalSaturnLight: sharedSignals.saturnLight,
        signalSaturnDark: sharedSignals.saturnDark,

        // Text
        textPrimary: Color(hex: "111315").opacity(0.95),
        textSecondary: Color(hex: "111315").opacity(0.65),
        textTertiary: Color(hex: "111315").opacity(0.45),
        textDisabled: Color(hex: "111315").opacity(0.25),

        // Accents
        accentPrimary: sharedSignals.mercury,
        accentSuccess: sharedSignals.lichen,
        accentWarning: sharedSignals.copper,
        accentError: Color(hex: "d32f2f"),

        // Glass
        glassOverlay: Color.black.opacity(0.04),
        glassBorder: Color.black.opacity(0.08),

        // Dividers
        divider: Color.black.opacity(0.07),
        dividerStrong: Color.black.opacity(0.12),

        // Shadows
        shadow: Color.black.opacity(0.12),
        shadowStrong: Color.black.opacity(0.22)
    )

    private static func palette(for scheme: ColorScheme) -> Palette {
        scheme == .dark ? dark : light
    }

    // MARK: - Dynamic Color Helpers

    #if os(iOS)
    private static func dynamicColor(light: Color, dark: Color) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            }
        )
    }
    #elseif os(macOS)
    private static func dynamicColor(light: Color, dark: Color) -> Color {
        Color(
            NSColor(name: nil) { appearance in
                let best = appearance.bestMatch(from: [.darkAqua, .aqua])
                if best == .darkAqua {
                    return NSColor(dark)
                }
                return NSColor(light)
            }
        )
    }
    #else
    private static func dynamicColor(light: Color, dark: Color) -> Color {
        // Fallback: prefer light
        light
    }
    #endif

    // MARK: - Raw Palette: Substrate
    //
    // These remain public for compatibility and for rare cases where a raw
    // mineral palette value is needed. New UI should prefer semantic surface
    // roles from AppSurfaces.swift.

    static let substratePrimary = dynamicColor(light: light.substratePrimary, dark: dark.substratePrimary)
    static let substrateSecondary = dynamicColor(light: light.substrateSecondary, dark: dark.substrateSecondary)
    static let substrateTertiary = dynamicColor(light: light.substrateTertiary, dark: dark.substrateTertiary)
    static let substrateElevated = dynamicColor(light: light.substrateElevated, dark: dark.substrateElevated)

    // MARK: - Signal Colors (Semantic)

    static let signalMercury = sharedSignals.mercury
    static let signalMercuryLight = sharedSignals.mercuryLight
    static let signalMercuryDark = sharedSignals.mercuryDark

    static let signalLichen = sharedSignals.lichen
    static let signalLichenLight = sharedSignals.lichenLight
    static let signalLichenDark = sharedSignals.lichenDark

    static let signalCopper = sharedSignals.copper
    static let signalCopperLight = sharedSignals.copperLight
    static let signalCopperDark = sharedSignals.copperDark

    static let signalHematite = sharedSignals.hematite
    static let signalHematiteLight = sharedSignals.hematiteLight
    static let signalHematiteDark = sharedSignals.hematiteDark

    static let signalSaturn = sharedSignals.saturn
    static let signalSaturnLight = sharedSignals.saturnLight
    static let signalSaturnDark = sharedSignals.saturnDark

    // MARK: - Text Colors

    static let textPrimary = dynamicColor(light: light.textPrimary, dark: dark.textPrimary)
    static let textSecondary = dynamicColor(light: light.textSecondary, dark: dark.textSecondary)
    static let textTertiary = dynamicColor(light: light.textTertiary, dark: dark.textTertiary)
    static let textDisabled = dynamicColor(light: light.textDisabled, dark: dark.textDisabled)

    // MARK: - Accent Colors

    static let accentPrimary = signalMercury
    static let accentSuccess = signalLichen
    static let accentWarning = signalCopper
    static let accentError = Color(hex: "d32f2f")

    // MARK: - Glass Morphism

    static let glassOverlay = dynamicColor(light: light.glassOverlay, dark: dark.glassOverlay)
    static let glassBorder = dynamicColor(light: light.glassBorder, dark: dark.glassBorder)

    // MARK: - Dividers & Borders

    static let divider = dynamicColor(light: light.divider, dark: dark.divider)
    static let dividerStrong = dynamicColor(light: light.dividerStrong, dark: dark.dividerStrong)

    // MARK: - Shadows

    static let shadow = dynamicColor(light: light.shadow, dark: dark.shadow)
    static let shadowStrong = dynamicColor(light: light.shadowStrong, dark: dark.shadowStrong)
}

// MARK: - Color Extension for Hex Support

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
