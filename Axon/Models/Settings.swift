//
//  Settings.swift
//  Axon
//
//  Settings data models
//

import Foundation

// MARK: - Main Settings Container

struct AppSettings: Codable, Equatable, Sendable {
    // General
    var theme: Theme = .dark
    var defaultProvider: AIProvider = .anthropic
    var defaultModel: String = "claude-haiku-4-5-20251001"

    // Custom Provider Selection (when using custom providers)
    var selectedCustomProviderId: UUID? = nil
    var selectedCustomModelId: UUID? = nil

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

    // Conversations
    var archiveRetentionDays: Int = 30

    // API Keys (stored separately in Keychain for security)
    // We'll reference them but not store them here

    // Text-to-Speech
    var ttsSettings: TTSSettings = TTSSettings()

    // Custom Providers
    var customProviders: [CustomProviderConfig] = []

    // Local API Server
    var serverEnabled: Bool = false
    var serverPort: Int = 8080
    var serverPassword: String? = nil
    var serverAllowExternal: Bool = false

    // Metadata
    var version: Int = 1
    var lastUpdated: Date = Date()
    var lastSyncedAt: Date?
}

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

// MARK: - AI Providers

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
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
                    id: "claude-sonnet-4-5-20250929",
                    name: "Claude Sonnet 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Best coding model. Strongest for complex agents and computer use"
                ),
                AIModel(
                    id: "claude-haiku-4-5-20251001",
                    name: "Claude Haiku 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Fast hybrid reasoning model. Great for coding and quick tasks"
                ),
                AIModel(
                    id: "claude-opus-4-1-20250805",
                    name: "Claude Opus 4.1",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Most powerful for long-running tasks and deep reasoning"
                ),
                AIModel(
                    id: "claude-sonnet-4-20250514",
                    name: "Claude Sonnet 4",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Previous generation Sonnet model"
                ),
                AIModel(
                    id: "claude-opus-4-20250514",
                    name: "Claude Opus 4",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    description: "Previous generation Opus model"
                )
            ]
        case .openai:
            return [
                AIModel(
                    id: "gpt-5-2025-08-07",
                    name: "GPT-5",
                    provider: .openai,
                    contextWindow: 400_000,
                    description: "Flagship model for coding, reasoning, and agentic tasks"
                ),
                AIModel(
                    id: "gpt-5-mini-2025-08-07",
                    name: "GPT-5 Mini",
                    provider: .openai,
                    contextWindow: 400_000,
                    description: "Fast and cost-efficient with strong performance"
                ),
                AIModel(
                    id: "gpt-5-nano-2025-08-07",
                    name: "GPT-5 Nano",
                    provider: .openai,
                    contextWindow: 400_000,
                    description: "Smallest, fastest, cheapest. Great for classification and extraction"
                ),
                AIModel(
                    id: "o3",
                    name: "o3",
                    provider: .openai,
                    contextWindow: 200_000,
                    description: "Most powerful reasoning model for coding, math, science, and vision"
                ),
                AIModel(
                    id: "o4-mini",
                    name: "o4-mini",
                    provider: .openai,
                    contextWindow: 200_000,
                    description: "Fast, cost-efficient reasoning model with multimodal support"
                ),
                AIModel(
                    id: "o3-mini",
                    name: "o3-mini",
                    provider: .openai,
                    contextWindow: 200_000,
                    description: "Specialized reasoning for STEM tasks with configurable effort levels"
                ),
                AIModel(
                    id: "gpt-4.1",
                    name: "GPT-4.1",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    description: "Enhanced coding and instruction following with 1M context"
                ),
                AIModel(
                    id: "gpt-4.1-mini",
                    name: "GPT-4.1 Mini",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    description: "Mid-tier with 1M context. Fast and cost-effective"
                ),
                AIModel(
                    id: "gpt-4.1-nano",
                    name: "GPT-4.1 Nano",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    description: "Lightest 4.1 variant with 1M context for simple tasks"
                ),
                AIModel(
                    id: "o1",
                    name: "o1",
                    provider: .openai,
                    contextWindow: 200_000,
                    description: "Advanced reasoning with vision API and function calling"
                ),
                AIModel(
                    id: "o1-mini",
                    name: "o1-mini",
                    provider: .openai,
                    contextWindow: 128_000,
                    description: "Faster reasoning focused on coding, math, and science"
                ),
                AIModel(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    provider: .openai,
                    contextWindow: 128_000,
                    description: "Multimodal flagship with text, audio, image, and video"
                ),
                AIModel(
                    id: "gpt-4o-mini",
                    name: "GPT-4o Mini",
                    provider: .openai,
                    contextWindow: 128_000,
                    description: "Cost-efficient multimodal model with vision support"
                )
            ]
        case .gemini:
            return [
                AIModel(
                    id: "gemini-2.5-pro",
                    name: "Gemini 2.5 Pro",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    description: "Most capable Gemini model"
                ),
                AIModel(
                    id: "gemini-2.5-flash",
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

struct AIModel: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let provider: AIProvider
    let contextWindow: Int
    let description: String
}

// MARK: - Unified Provider & Model (for UI)

/// Unified provider that can represent either built-in or custom providers
enum UnifiedProvider: Identifiable, Hashable {
    case builtIn(AIProvider)
    case custom(CustomProviderConfig)

    var id: String {
        switch self {
        case .builtIn(let provider):
            return "builtin_\(provider.rawValue)"
        case .custom(let config):
            return "custom_\(config.id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .builtIn(let provider):
            return provider.displayName
        case .custom(let config):
            return config.providerName
        }
    }

    var isCustom: Bool {
        if case .custom = self {
            return true
        }
        return false
    }

    func availableModels(customProviderIndex: Int? = nil) -> [UnifiedModel] {
        switch self {
        case .builtIn(let provider):
            return provider.availableModels.map { UnifiedModel.builtIn($0) }
        case .custom(let config):
            return config.models.enumerated().map { index, model in
                UnifiedModel.custom(model, providerName: config.providerName, providerIndex: customProviderIndex ?? 1, modelIndex: index + 1)
            }
        }
    }
}

/// Unified model that can represent either built-in or custom models
enum UnifiedModel: Identifiable, Hashable, Sendable {
    case builtIn(AIModel)
    case custom(CustomModelConfig, providerName: String, providerIndex: Int, modelIndex: Int)

    var id: String {
        switch self {
        case .builtIn(let model):
            return "builtin_\(model.id)"
        case .custom(let config, _, _, _):
            return "custom_\(config.id.uuidString)"
        }
    }

    var name: String {
        switch self {
        case .builtIn(let model):
            return model.name
        case .custom(let config, let providerName, _, _):
            return config.displayName(providerName: providerName)
        }
    }

    var description: String {
        switch self {
        case .builtIn(let model):
            return model.description
        case .custom(let config, _, let providerIndex, let modelIndex):
            return config.displayDescription(providerIndex: providerIndex, modelIndex: modelIndex)
        }
    }

    var contextWindow: Int {
        switch self {
        case .builtIn(let model):
            return model.contextWindow
        case .custom(let config, _, _, _):
            return config.contextWindow
        }
    }

    var pricing: CustomModelPricing? {
        switch self {
        case .builtIn:
            return nil  // Built-in models use PricingRegistry
        case .custom(let config, _, _, _):
            return config.pricing
        }
    }

    var modelCode: String {
        switch self {
        case .builtIn(let model):
            return model.id
        case .custom(let config, _, _, _):
            return config.modelCode
        }
    }
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
    var selectedVoiceId: String? = nil
    var selectedVoiceName: String? = nil
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

// MARK: - Custom Provider Configuration

struct CustomProviderConfig: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var providerName: String
    var apiEndpoint: String
    var models: [CustomModelConfig]

    init(id: UUID = UUID(), providerName: String, apiEndpoint: String, models: [CustomModelConfig] = []) {
        self.id = id
        self.providerName = providerName
        self.apiEndpoint = apiEndpoint
        self.models = models
    }
}

struct CustomModelConfig: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: UUID
    var modelCode: String
    var friendlyName: String?
    var contextWindow: Int
    var description: String?
    var pricing: CustomModelPricing?
    var colorHex: String?  // Optional hex color (RRGGBB format, uppercase, no #)

    init(
        id: UUID = UUID(),
        modelCode: String,
        friendlyName: String? = nil,
        contextWindow: Int = 128_000,
        description: String? = nil,
        pricing: CustomModelPricing? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.modelCode = modelCode
        self.friendlyName = friendlyName
        self.contextWindow = contextWindow
        self.description = description
        self.pricing = pricing
        self.colorHex = colorHex
    }

    /// Display name with fallback logic
    func displayName(providerName: String) -> String {
        return friendlyName ?? providerName
    }

    /// Auto-generated description with fallback
    func displayDescription(providerIndex: Int, modelIndex: Int) -> String {
        return description ?? "Custom Provider \(providerIndex), Model \(modelIndex)"
    }
}

struct CustomModelPricing: Codable, Equatable, Hashable, Sendable {
    var inputPerMTok: Double
    var outputPerMTok: Double
    var cachedInputPerMTok: Double?

    init(inputPerMTok: Double, outputPerMTok: Double, cachedInputPerMTok: Double? = nil) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
        self.cachedInputPerMTok = cachedInputPerMTok
    }

    /// Format pricing for display
    func formattedPricing() -> String {
        var parts: [String] = []
        parts.append(String(format: "$%.2f in / $%.2f out per 1M tokens", inputPerMTok, outputPerMTok))
        if let cached = cachedInputPerMTok {
            parts.append(String(format: "cached: $%.2f", cached))
        }
        return parts.joined(separator: " · ")
    }
}
