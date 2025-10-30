//
//  AppColors.swift
//  Axon
//
//  Design System Colors - Mineral-Inspired Dark Theme
//

import SwiftUI

struct AppColors {

    // MARK: - Substrate (Background & Surfaces)

    /// Primary background - Deep charcoal (#161a1b)
    static let substratePrimary = Color(hex: "161a1b")

    /// Secondary surface - Lighter charcoal (#1e2324)
    static let substrateSecondary = Color(hex: "1e2324")

    /// Tertiary surface - Mid-tone (#262b2d)
    static let substrateTertiary = Color(hex: "262b2d")

    /// Elevated surface - Lighter still (#2e3436)
    static let substrateElevated = Color(hex: "2e3436")

    // MARK: - Signal Colors (Semantic)

    /// Mercury - Cool tones for info/AI content (#3f6f7a)
    static let signalMercury = Color(hex: "3f6f7a")
    static let signalMercuryLight = Color(hex: "5a8a96")
    static let signalMercuryDark = Color(hex: "2a4a52")

    /// Lichen - Green for success/user content (#5f7f5f)
    static let signalLichen = Color(hex: "5f7f5f")
    static let signalLichenLight = Color(hex: "7a9a7a")
    static let signalLichenDark = Color(hex: "4a644a")

    /// Copper - Warm for alerts/warnings (#b2763a)
    static let signalCopper = Color(hex: "b2763a")
    static let signalCopperLight = Color(hex: "cc9055")
    static let signalCopperDark = Color(hex: "8a5c2e")

    /// Hematite - Neutral for debugging (#6b5a5a)
    static let signalHematite = Color(hex: "6b5a5a")
    static let signalHematiteLight = Color(hex: "867575")
    static let signalHematiteDark = Color(hex: "503f3f")

    // MARK: - Text Colors

    /// Primary text - High contrast white
    static let textPrimary = Color.white.opacity(0.95)

    /// Secondary text - Medium contrast
    static let textSecondary = Color.white.opacity(0.65)

    /// Tertiary text - Low contrast
    static let textTertiary = Color.white.opacity(0.45)

    /// Disabled text
    static let textDisabled = Color.white.opacity(0.25)

    // MARK: - Accent Colors

    /// Primary accent (Mercury for AI interactions)
    static let accentPrimary = signalMercury

    /// Success accent (Lichen for confirmations)
    static let accentSuccess = signalLichen

    /// Warning accent (Copper for cautions)
    static let accentWarning = signalCopper

    /// Error accent (Deep red)
    static let accentError = Color(hex: "d32f2f")

    // MARK: - Glass Morphism

    /// Glass overlay with blur
    static let glassOverlay = Color.white.opacity(0.05)

    /// Glass border
    static let glassBorder = Color.white.opacity(0.1)

    // MARK: - Dividers & Borders

    /// Standard divider
    static let divider = Color.white.opacity(0.08)

    /// Strong divider
    static let dividerStrong = Color.white.opacity(0.12)

    // MARK: - Shadows

    /// Standard shadow color
    static let shadow = Color.black.opacity(0.3)

    /// Strong shadow for elevated elements
    static let shadowStrong = Color.black.opacity(0.5)
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
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
