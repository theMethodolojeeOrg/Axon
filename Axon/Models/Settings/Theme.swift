//
//  Theme.swift
//  Axon
//
//  App theme settings
//

import Foundation

// MARK: - Theme

enum Theme: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark = "dark"
    case light = "light"
    case auto = "auto"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .auto: return "Auto (System)"
        }
    }
}
