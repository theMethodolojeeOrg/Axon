//
//  AppTypography.swift
//  Axon
//
//  Design System Typography - IBM Plex Sans-inspired
//

import SwiftUI

struct AppTypography {

    // MARK: - Font Weights

    enum FontWeight {
        case regular
        case medium
        case semibold
        case bold

        var weight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    // MARK: - Display Styles

    /// Display Large - 57pt/64pt line height
    static func displayLarge(_ weight: FontWeight = .bold) -> Font {
        return .system(size: 57, weight: weight.weight, design: .default)
    }

    /// Display Medium - 45pt/52pt line height
    static func displayMedium(_ weight: FontWeight = .bold) -> Font {
        return .system(size: 45, weight: weight.weight, design: .default)
    }

    /// Display Small - 36pt/44pt line height
    static func displaySmall(_ weight: FontWeight = .semibold) -> Font {
        return .system(size: 36, weight: weight.weight, design: .default)
    }

    // MARK: - Headline Styles

    /// Headline Large - 32pt/40pt line height
    static func headlineLarge(_ weight: FontWeight = .semibold) -> Font {
        return .system(size: 32, weight: weight.weight, design: .default)
    }

    /// Headline Medium - 28pt/36pt line height
    static func headlineMedium(_ weight: FontWeight = .semibold) -> Font {
        return .system(size: 28, weight: weight.weight, design: .default)
    }

    /// Headline Small - 24pt/32pt line height
    static func headlineSmall(_ weight: FontWeight = .semibold) -> Font {
        return .system(size: 24, weight: weight.weight, design: .default)
    }

    // MARK: - Title Styles

    /// Title Large - 22pt/28pt line height
    static func titleLarge(_ weight: FontWeight = .semibold) -> Font {
        return .system(size: 22, weight: weight.weight, design: .default)
    }

    /// Title Medium - 16pt/24pt line height
    static func titleMedium(_ weight: FontWeight = .medium) -> Font {
        return .system(size: 16, weight: weight.weight, design: .default)
    }

    /// Title Small - 14pt/20pt line height
    static func titleSmall(_ weight: FontWeight = .medium) -> Font {
        return .system(size: 14, weight: weight.weight, design: .default)
    }

    // MARK: - Body Styles

    /// Body Large - 16pt/24pt line height
    static func bodyLarge(_ weight: FontWeight = .regular) -> Font {
        return .system(size: 16, weight: weight.weight, design: .default)
    }

    /// Body Medium - 14pt/20pt line height
    static func bodyMedium(_ weight: FontWeight = .regular) -> Font {
        return .system(size: 14, weight: weight.weight, design: .default)
    }

    /// Body Small - 12pt/16pt line height
    static func bodySmall(_ weight: FontWeight = .regular) -> Font {
        return .system(size: 12, weight: weight.weight, design: .default)
    }

    // MARK: - Label Styles

    /// Label Large - 14pt/20pt line height
    static func labelLarge(_ weight: FontWeight = .medium) -> Font {
        return .system(size: 14, weight: weight.weight, design: .default)
    }

    /// Label Medium - 12pt/16pt line height
    static func labelMedium(_ weight: FontWeight = .medium) -> Font {
        return .system(size: 12, weight: weight.weight, design: .default)
    }

    /// Label Small - 11pt/16pt line height
    static func labelSmall(_ weight: FontWeight = .medium) -> Font {
        return .system(size: 11, weight: weight.weight, design: .default)
    }

    // MARK: - Monospace (Code)

    /// Monospace for code display - 14pt
    static func code(_ weight: FontWeight = .regular) -> Font {
        return .system(size: 14, weight: weight.weight, design: .monospaced)
    }

    /// Monospace small for inline code - 12pt
    static func codeSmall(_ weight: FontWeight = .regular) -> Font {
        return .system(size: 12, weight: weight.weight, design: .monospaced)
    }
}

// MARK: - Text Style Extension

extension Text {
    func appStyle(_ font: Font, color: Color = AppColors.textPrimary) -> some View {
        self
            .font(font)
            .foregroundColor(color)
    }
}
