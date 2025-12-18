//
//  AppColors.swift
//  AxonLiveActivity
//
//  Shared color definitions for Live Activity widgets.
//  This is a simplified version for the widget extension target.
//

import SwiftUI

struct AppColors {
    // Signal Colors (Lichen - for progress bars)
    static let signalLichen = Color(hex: "5f7f5f")
    static let signalLichenLight = Color(hex: "7a9a7a")
    static let signalLichenDark = Color(hex: "4a644a")
    
    // Mercury (primary accent)
    static let signalMercury = Color(hex: "3f6f7a")
    static let signalMercuryLight = Color(hex: "5a8a96")
    static let signalMercuryDark = Color(hex: "2a4a52")
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
