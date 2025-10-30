//
//  Settings.swift
//  Axon
//
//  Settings data models
//

import Foundation

// MARK: - Main Settings Container

struct AppSettings: Codable, Equatable {
    // General
    var theme: Theme = .dark
    var defaultProvider: AIProvider = .anthropic
    var defaultModel: String = "claude-sonnet-4-5"
    var showArtifactsByDefault: Bool = true
    var enableKeyboardShortcuts: Bool = true

    // Account
    var firstName: String = ""
    var lastName: String = ""

    // Memory
    var memoryEnabled: Bool = true
    var memoryAutoInject: Bool = true
    var memoryConfidenceThreshold: Double = 0.3  // 0-1.0
    var maxMemoriesPerRequest: Int = 10  // 5-50
    var memoryAnalyticsEnabled: Bool = true

    // API Keys (stored separately in Keychain for security)
    // We'll reference them but not store them here

    // Text-to-Speech
    var ttsSettings: TTSSettings = TTSSettings()

    // Metadata
    var version: Int = 1
    var lastUpdated: Date = Date()
    var lastSyncedAt: Date?
}

// MARK: - Theme

enum Theme: String, Codable, CaseIterable, Identifiable {
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

// MARK: - AI Providers

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (GPT)"
        case .gemini: return "Google Gemini"
        }
    }

    var availableModels: [AIModel] {
        switch self {
        case .anthropic:
            return [
                AIModel(
                    id: "claude-sonnet-4-5",
                    name: "Claude Sonnet 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Recommended. Best balance of speed and intelligence"
                ),
                AIModel(
                    id: "claude-haiku-4-5",
                    name: "Claude Haiku 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Fastest, lightest. Great for quick tasks"
                ),
                AIModel(
                    id: "claude-opus-4",
                    name: "Claude Opus 4",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Most capable. Best for complex reasoning"
                )
            ]
        case .openai:
            return [
                AIModel(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    provider: .openai,
                    contextWindow: 128_000,
                    description: "Most capable OpenAI model"
                ),
                AIModel(
                    id: "gpt-4o-mini",
                    name: "GPT-4o Mini",
                    provider: .openai,
                    contextWindow: 128_000,
                    description: "Fast and efficient"
                ),
                AIModel(
                    id: "gpt-4-turbo",
                    name: "GPT-4 Turbo",
                    provider: .openai,
                    contextWindow: 128_000,
                    description: "Previous generation model"
                )
            ]
        case .gemini:
            return [
                AIModel(
                    id: "gemini-2-5-pro",
                    name: "Gemini 2.5 Pro",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    description: "Most capable Gemini model"
                ),
                AIModel(
                    id: "gemini-2-5-flash",
                    name: "Gemini 2.5 Flash",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    description: "Fast, efficient model"
                )
            ]
        }
    }
}

// MARK: - AI Model

struct AIModel: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let provider: AIProvider
    let contextWindow: Int
    let description: String
}

// MARK: - API Provider

enum APIProvider: String, CaseIterable, Identifiable {
    case neurx = "neurx"
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case elevenlabs = "elevenlabs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .neurx: return "NeurX"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .elevenlabs: return "ElevenLabs"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .neurx: return "nrx_..."
        case .openai: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        case .elevenlabs: return "sk_..."
        }
    }

    var infoURL: URL? {
        switch self {
        case .neurx: return URL(string: "https://neurx.org/api-keys")
        case .openai: return URL(string: "https://platform.openai.com/account/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/account/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .elevenlabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        }
    }

    var description: String {
        switch self {
        case .neurx: return "Admin API key for NeurX backend services"
        case .openai: return "Required for GPT models"
        case .anthropic: return "Required for Claude models"
        case .gemini: return "Required for Gemini models"
        case .elevenlabs: return "Required for text-to-speech"
        }
    }
}

// MARK: - TTS Settings

struct TTSSettings: Codable, Equatable {
    var model: TTSModel = .turboV25
    var outputFormat: TTSOutputFormat = .mp3128
    var voiceSettings: VoiceSettings = VoiceSettings()
}

enum TTSModel: String, Codable, CaseIterable, Identifiable {
    case turboV25 = "eleven_turbo_v2_5"
    case multilingualV2 = "eleven_multilingual_v2"
    case flashV25 = "eleven_flash_v2_5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turboV25: return "Turbo v2.5"
        case .multilingualV2: return "Multilingual v2"
        case .flashV25: return "Flash v2.5"
        }
    }

    var description: String {
        switch self {
        case .turboV25: return "Fastest, most natural"
        case .multilingualV2: return "Supports 29 languages"
        case .flashV25: return "Latest flash model"
        }
    }
}

enum TTSOutputFormat: String, Codable, CaseIterable, Identifiable {
    case mp3128 = "mp3_44100_128"
    case mp364 = "mp3_44100_64"
    case mp332 = "mp3_22050_32"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp3128: return "MP3 128kbps"
        case .mp364: return "MP3 64kbps"
        case .mp332: return "MP3 32kbps"
        }
    }

    var description: String {
        switch self {
        case .mp3128: return "Highest quality"
        case .mp364: return "Balanced"
        case .mp332: return "Smallest size"
        }
    }
}

struct VoiceSettings: Codable, Equatable {
    var stability: Double = 0.5
    var similarityBoost: Double = 0.75
    var style: Double = 0.0
    var useSpeakerBoost: Bool = false
}
