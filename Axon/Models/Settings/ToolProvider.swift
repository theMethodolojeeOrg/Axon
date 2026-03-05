//
//  ToolProvider.swift
//  Axon
//
//  Tool provider categories
//

import Foundation

// MARK: - Tool Provider

/// Tool provider categories
enum ToolProvider: String, Codable, CaseIterable, Sendable {
    case gemini = "gemini"
    case openai = "openai"
    case `internal` = "internal"

    var displayName: String {
        switch self {
        case .gemini: return "Google (Gemini)"
        case .openai: return "OpenAI"
        case .internal: return "Built-in"
        }
    }

    var icon: String {
        switch self {
        case .gemini: return "globe"
        case .openai: return "cpu"
        case .internal: return "gear"
        }
    }

    var description: String {
        switch self {
        case .gemini: return "Tools powered by Gemini's native capabilities"
        case .openai: return "Tools powered by OpenAI"
        case .internal: return "Built-in Axon tools"
        }
    }

    /// Whether tools from this provider require a specific API key
    var requiredApiKey: String? {
        switch self {
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .internal: return nil
        }
    }
}
