//
//  UnifiedModelRegistry.swift
//  Axon
//
//  Unified registry for all AI models, providers, and TTS voices.
//  Loads configuration from JSON files in Resources/DefaultModels/.
//

import Foundation
import Combine
import os.log

// MARK: - Model Registry Category

/// Category of model/provider in the registry
enum ModelRegistryCategory: String, Codable, CaseIterable, Sendable {
    case chat           // Chat/completion models (Anthropic, OpenAI, etc.)
    case tts            // Text-to-speech providers
    case local          // Local MLX models
    case foundation     // Apple Foundation models
}

// MARK: - TTS Provider Configuration

/// Configuration for a TTS provider loaded from JSON
struct TTSProviderConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let type: ModelRegistryCategory
    let description: String
    let icon: String
    let requiresAPIKey: Bool
    let apiKeyProvider: String?
    let isOnDevice: Bool
    let isEnabled: Bool?
    let disabledReason: String?
    let voices: [TTSVoiceConfig]
    let voicesNote: String?
    let models: [TTSModelConfig]?
    let outputFormats: [TTSOutputFormatConfig]?
    let settings: TTSProviderSettings?

    enum CodingKeys: String, CodingKey {
        case id, displayName, type, description, icon, requiresAPIKey
        case apiKeyProvider, isOnDevice, isEnabled, disabledReason
        case voices, voicesNote, models, outputFormats, settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        type = try container.decodeIfPresent(ModelRegistryCategory.self, forKey: .type) ?? .tts
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decode(String.self, forKey: .icon)
        requiresAPIKey = try container.decode(Bool.self, forKey: .requiresAPIKey)
        apiKeyProvider = try container.decodeIfPresent(String.self, forKey: .apiKeyProvider)
        isOnDevice = try container.decode(Bool.self, forKey: .isOnDevice)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        disabledReason = try container.decodeIfPresent(String.self, forKey: .disabledReason)
        voices = try container.decode([TTSVoiceConfig].self, forKey: .voices)
        voicesNote = try container.decodeIfPresent(String.self, forKey: .voicesNote)
        models = try container.decodeIfPresent([TTSModelConfig].self, forKey: .models)
        outputFormats = try container.decodeIfPresent([TTSOutputFormatConfig].self, forKey: .outputFormats)
        settings = try container.decodeIfPresent(TTSProviderSettings.self, forKey: .settings)
    }
}

/// Configuration for a TTS voice loaded from JSON
struct TTSVoiceConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let gender: String
    let accent: String?
    let locale: String
    let description: String
    let toneDescription: String?

    // Provider-specific attributes
    let isBuiltIn: Bool?
    let downloadURL: String?
    let sampleAudioURL: String?
    let qualityTiers: [String]?

    /// Computed gender enum for type-safe filtering
    var genderType: VoiceGender? {
        VoiceGender(rawValue: gender)
    }
}

/// Configuration for a TTS model loaded from JSON
struct TTSModelConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let supportsInstructions: Bool?
    let isDefault: Bool
    let sizeBytes: Int64?
}

/// Configuration for TTS output format
struct TTSOutputFormatConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
}

/// Settings for a TTS provider
struct TTSProviderSettings: Codable, Equatable, Sendable {
    let speedRange: RangeConfig?
    let rateRange: RangeConfig?
    let stabilityRange: RangeConfig?
    let similarityBoostRange: RangeConfig?
    let styleRange: RangeConfig?
    let supportsVoiceInstructions: Bool?
    let supportsVoiceDirection: Bool?
    let supportsSpeakerBoost: Bool?
}

/// Range configuration for numeric settings
struct RangeConfig: Codable, Equatable, Sendable {
    let min: Double
    let max: Double
    let `default`: Double
}

// MARK: - MLX Provider Configuration

/// Configuration for local MLX models loaded from JSON
struct MLXProviderConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let type: ModelRegistryCategory
    let description: String
    let icon: String
    let requiresAPIKey: Bool
    let isOnDevice: Bool
    let platformRequirements: PlatformRequirements?
    let models: [MLXModelConfig]

    enum CodingKeys: String, CodingKey {
        case id, displayName, type, description, icon
        case requiresAPIKey, isOnDevice, platformRequirements, models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        type = try container.decodeIfPresent(ModelRegistryCategory.self, forKey: .type) ?? .local
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decode(String.self, forKey: .icon)
        requiresAPIKey = try container.decode(Bool.self, forKey: .requiresAPIKey)
        isOnDevice = try container.decode(Bool.self, forKey: .isOnDevice)
        platformRequirements = try container.decodeIfPresent(PlatformRequirements.self, forKey: .platformRequirements)
        models = try container.decode([MLXModelConfig].self, forKey: .models)
    }
}

/// Configuration for a local MLX model
struct MLXModelConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let contextWindow: Int
    let modalities: [String]
    let description: String
    let sizeBytes: Int64?
    let isBuiltIn: Bool
    let downloadURL: String?
    let huggingFaceRepoId: String

    /// Convert to AIModel for backward compatibility
    func toAIModel() -> AIModel {
        AIModel(
            id: id,
            name: displayName,
            provider: .localMLX,
            contextWindow: contextWindow,
            modalities: modalities,
            description: description
        )
    }
}

/// Platform requirements for local models
struct PlatformRequirements: Codable, Equatable, Sendable {
    let minimumOS: String?
    let requiresAppleSilicon: Bool?
    let requiresPhysicalDevice: Bool?
}

// MARK: - Foundation Provider Configuration

/// Configuration for Apple Foundation models loaded from JSON
struct FoundationProviderConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let type: ModelRegistryCategory
    let description: String
    let icon: String
    let requiresAPIKey: Bool
    let isOnDevice: Bool
    let platformRequirements: PlatformRequirements?
    let models: [FoundationModelConfig]

    enum CodingKeys: String, CodingKey {
        case id, displayName, type, description, icon
        case requiresAPIKey, isOnDevice, platformRequirements, models
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        type = try container.decodeIfPresent(ModelRegistryCategory.self, forKey: .type) ?? .foundation
        description = try container.decode(String.self, forKey: .description)
        icon = try container.decode(String.self, forKey: .icon)
        requiresAPIKey = try container.decode(Bool.self, forKey: .requiresAPIKey)
        isOnDevice = try container.decode(Bool.self, forKey: .isOnDevice)
        platformRequirements = try container.decodeIfPresent(PlatformRequirements.self, forKey: .platformRequirements)
        models = try container.decode([FoundationModelConfig].self, forKey: .models)
    }
}

/// Configuration for a Foundation model
struct FoundationModelConfig: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let contextWindow: Int
    let modalities: [String]
    let description: String
    let status: String?

    /// Convert to AIModel for backward compatibility
    func toAIModel() -> AIModel {
        AIModel(
            id: id,
            name: displayName,
            provider: .appleFoundation,
            contextWindow: contextWindow,
            modalities: modalities,
            description: description
        )
    }
}

// MARK: - Validation Warnings

enum RegistryValidationWarning: Equatable, Sendable {
    case voiceMissingInEnum(provider: String, voiceId: String)
    case voiceMissingInJSON(provider: String, voiceId: String)
    case modelMissingInEnum(provider: String, modelId: String)
    case modelMissingInJSON(provider: String, modelId: String)
    case fileNotFound(filename: String)
    case parseError(filename: String, error: String)

    var description: String {
        switch self {
        case .voiceMissingInEnum(let provider, let voiceId):
            return "Voice '\(voiceId)' in \(provider).json not found in Swift enum"
        case .voiceMissingInJSON(let provider, let voiceId):
            return "Voice '\(voiceId)' in Swift enum not found in \(provider).json"
        case .modelMissingInEnum(let provider, let modelId):
            return "Model '\(modelId)' in \(provider).json not found in Swift enum"
        case .modelMissingInJSON(let provider, let modelId):
            return "Model '\(modelId)' in Swift enum not found in \(provider).json"
        case .fileNotFound(let filename):
            return "Configuration file not found: \(filename)"
        case .parseError(let filename, let error):
            return "Failed to parse \(filename): \(error)"
        }
    }
}

// MARK: - Unified Model Registry Service

@MainActor
final class UnifiedModelRegistry: ObservableObject {
    static let shared = UnifiedModelRegistry()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "UnifiedModelRegistry")

    // MARK: - Published State

    /// Chat providers loaded from JSON (Anthropic, OpenAI, etc.)
    @Published private(set) var chatProviders: [ProviderConfig] = []

    /// TTS providers loaded from JSON
    @Published private(set) var ttsProviders: [TTSProviderConfig] = []

    /// MLX local models provider
    @Published private(set) var mlxProvider: MLXProviderConfig?

    /// Apple Intelligence provider
    @Published private(set) var foundationProvider: FoundationProviderConfig?

    /// Whether the registry has finished loading
    @Published private(set) var isLoaded: Bool = false

    /// Validation warnings found during load
    @Published private(set) var validationWarnings: [RegistryValidationWarning] = []

    // MARK: - Initialization

    private init() {
        loadAllConfigurations()
    }

    // MARK: - Loading

    /// Load all configurations from JSON files
    func loadAllConfigurations() {
        logger.info("Loading unified model registry...")

        validationWarnings.removeAll()

        loadChatProviders()
        loadTTSProviders()
        loadMLXProvider()
        loadFoundationProvider()
        validateEnumSync()

        isLoaded = true

        let totalModels = chatProviders.flatMap(\.models).count
            + (mlxProvider?.models.count ?? 0)
            + (foundationProvider?.models.count ?? 0)
        let totalVoices = ttsProviders.flatMap(\.voices).count

        logger.info("Unified model registry loaded: \(self.chatProviders.count) chat providers, \(totalModels) models, \(self.ttsProviders.count) TTS providers, \(totalVoices) voices")

        if !validationWarnings.isEmpty {
            logger.warning("Registry has \(self.validationWarnings.count) validation warnings")
        }
    }

    /// Reload all configurations
    func reload() {
        isLoaded = false
        loadAllConfigurations()
    }

    private func loadChatProviders() {
        let chatProviderFiles = ["anthropic", "openai", "gemini", "xai", "perplexity",
                                  "deepseek", "zai", "minimax", "mistral"]

        chatProviders = chatProviderFiles.compactMap { filename in
            guard let url = Bundle.main.url(forResource: filename,
                                            withExtension: "json",
                                            subdirectory: "DefaultModels") else {
                validationWarnings.append(.fileNotFound(filename: "\(filename).json"))
                logger.warning("Chat provider file not found: \(filename).json")
                return nil
            }
            return loadProviderConfig(from: url, filename: filename)
        }
    }

    private func loadTTSProviders() {
        let ttsProviderFiles = ["apple-tts", "kokoro", "openai-tts",
                                 "gemini-tts", "elevenlabs", "mlx-audio"]

        ttsProviders = ttsProviderFiles.compactMap { filename in
            guard let url = Bundle.main.url(forResource: filename,
                                            withExtension: "json",
                                            subdirectory: "DefaultModels/tts") else {
                validationWarnings.append(.fileNotFound(filename: "tts/\(filename).json"))
                logger.warning("TTS provider file not found: tts/\(filename).json")
                return nil
            }
            return loadTTSProviderConfig(from: url, filename: filename)
        }
    }

    private func loadMLXProvider() {
        guard let url = Bundle.main.url(forResource: "mlx-local",
                                        withExtension: "json",
                                        subdirectory: "DefaultModels") else {
            validationWarnings.append(.fileNotFound(filename: "mlx-local.json"))
            logger.warning("MLX provider file not found")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            mlxProvider = try JSONDecoder().decode(MLXProviderConfig.self, from: data)
            logger.info("Loaded MLX provider with \(self.mlxProvider?.models.count ?? 0) models")
        } catch {
            validationWarnings.append(.parseError(filename: "mlx-local.json", error: error.localizedDescription))
            logger.error("Failed to parse mlx-local.json: \(error.localizedDescription)")
        }
    }

    private func loadFoundationProvider() {
        guard let url = Bundle.main.url(forResource: "apple-intelligence",
                                        withExtension: "json",
                                        subdirectory: "DefaultModels") else {
            validationWarnings.append(.fileNotFound(filename: "apple-intelligence.json"))
            logger.warning("Apple Intelligence file not found")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            foundationProvider = try JSONDecoder().decode(FoundationProviderConfig.self, from: data)
            logger.info("Loaded Apple Intelligence provider")
        } catch {
            validationWarnings.append(.parseError(filename: "apple-intelligence.json", error: error.localizedDescription))
            logger.error("Failed to parse apple-intelligence.json: \(error.localizedDescription)")
        }
    }

    private func loadProviderConfig(from url: URL, filename: String) -> ProviderConfig? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ProviderConfig.self, from: data)
        } catch {
            validationWarnings.append(.parseError(filename: "\(filename).json", error: error.localizedDescription))
            logger.error("Failed to parse \(filename).json: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadTTSProviderConfig(from url: URL, filename: String) -> TTSProviderConfig? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TTSProviderConfig.self, from: data)
        } catch {
            validationWarnings.append(.parseError(filename: "tts/\(filename).json", error: error.localizedDescription))
            logger.error("Failed to parse tts/\(filename).json: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Chat Model Queries

    /// Get all chat models for a specific provider
    func chatModels(for provider: AIProvider) -> [AIModel] {
        guard let providerConfig = chatProviders.first(where: { $0.id == provider.rawValue }) else {
            return []
        }
        return providerConfig.models.map { $0.toAIModel(provider: provider) }
    }

    /// Get all chat models across all providers
    func allChatModels() -> [AIModel] {
        chatProviders.flatMap { providerConfig -> [AIModel] in
            guard let provider = providerConfig.aiProvider else { return [] }
            return providerConfig.models.map { $0.toAIModel(provider: provider) }
        }
    }

    /// Get chat models filtered by category
    func chatModels(category: ModelCategory) -> [AIModel] {
        chatProviders.flatMap { providerConfig -> [AIModel] in
            guard let provider = providerConfig.aiProvider else { return [] }
            return providerConfig.models
                .filter { $0.category == category }
                .map { $0.toAIModel(provider: provider) }
        }
    }

    /// Get models that support live/real-time audio for a specific provider
    func liveAudioModels(for provider: AIProvider) -> [AIModel] {
        guard let providerConfig = chatProviders.first(where: { $0.id == provider.rawValue }) else {
            return []
        }
        return providerConfig.models
            .filter { $0.supportsLiveAudio == true }
            .map { $0.toAIModel(provider: provider) }
    }

    /// Get all models that support live/real-time audio across all providers
    func allLiveAudioModels() -> [AIModel] {
        chatProviders.flatMap { providerConfig -> [AIModel] in
            guard let provider = providerConfig.aiProvider else { return [] }
            return providerConfig.models
                .filter { $0.supportsLiveAudio == true }
                .map { $0.toAIModel(provider: provider) }
        }
    }

    /// Get pricing for a chat model by ID
    func pricing(for modelId: String) -> ModelPricing? {
        for provider in chatProviders {
            if let model = provider.models.first(where: { $0.id == modelId }) {
                return model.pricing.toModelPricing()
            }
        }
        return nil
    }

    /// Get model configuration by ID
    func modelConfig(for modelId: String) -> ModelConfig? {
        for provider in chatProviders {
            if let model = provider.models.first(where: { $0.id == modelId }) {
                return model
            }
        }
        return nil
    }

    // MARK: - TTS Voice Queries

    /// Get TTS provider configuration by ID
    func ttsProvider(_ providerId: String) -> TTSProviderConfig? {
        ttsProviders.first(where: { $0.id == providerId })
    }

    /// Get TTS provider configuration by TTSProvider enum
    func ttsProvider(_ provider: TTSProvider) -> TTSProviderConfig? {
        ttsProviders.first(where: { $0.id == provider.rawValue })
    }

    /// Get all TTS providers
    func allTTSProviders() -> [TTSProviderConfig] {
        ttsProviders
    }

    /// Get enabled TTS providers only
    func enabledTTSProviders() -> [TTSProviderConfig] {
        ttsProviders.filter { $0.isEnabled != false }
    }

    /// Get all voices for a TTS provider
    func voices(for provider: TTSProvider) -> [TTSVoiceConfig] {
        ttsProvider(provider)?.voices ?? []
    }

    /// Get voices filtered by gender
    func voices(for provider: TTSProvider, gender: VoiceGender) -> [TTSVoiceConfig] {
        voices(for: provider).filter { $0.genderType == gender }
    }

    /// Get a specific voice by provider ID and voice ID
    func voice(providerId: String, voiceId: String) -> TTSVoiceConfig? {
        ttsProvider(providerId)?.voices.first(where: { $0.id == voiceId })
    }

    /// Get a specific voice by TTSProvider enum and voice ID
    func voice(provider: TTSProvider, voiceId: String) -> TTSVoiceConfig? {
        ttsProvider(provider)?.voices.first(where: { $0.id == voiceId })
    }

    /// Get TTS models for a provider
    func ttsModels(for provider: TTSProvider) -> [TTSModelConfig] {
        ttsProvider(provider)?.models ?? []
    }

    /// Get default TTS model for a provider
    func defaultTTSModel(for provider: TTSProvider) -> TTSModelConfig? {
        ttsModels(for: provider).first(where: { $0.isDefault })
    }

    /// Get TTS provider settings
    func ttsSettings(for provider: TTSProvider) -> TTSProviderSettings? {
        ttsProvider(provider)?.settings
    }

    // MARK: - MLX Model Queries

    /// Get all MLX models
    func mlxModels() -> [MLXModelConfig] {
        mlxProvider?.models ?? []
    }

    /// Get MLX models as AIModel for backward compatibility
    func mlxModelsAsAIModels() -> [AIModel] {
        mlxModels().map { $0.toAIModel() }
    }

    /// Get built-in MLX models (bundled with app)
    func builtInMLXModels() -> [MLXModelConfig] {
        mlxModels().filter { $0.isBuiltIn }
    }

    /// Get downloadable MLX models
    func downloadableMLXModels() -> [MLXModelConfig] {
        mlxModels().filter { !$0.isBuiltIn }
    }

    /// Get MLX model by ID
    func mlxModel(for modelId: String) -> MLXModelConfig? {
        mlxModels().first(where: { $0.id == modelId })
    }

    // MARK: - Foundation Model Queries

    /// Get all Foundation models
    func foundationModels() -> [FoundationModelConfig] {
        foundationProvider?.models ?? []
    }

    /// Get Foundation models as AIModel for backward compatibility
    func foundationModelsAsAIModels() -> [AIModel] {
        foundationModels().map { $0.toAIModel() }
    }

    // MARK: - Unified Queries

    /// Get all models across all categories
    func allModels(category: ModelRegistryCategory? = nil) -> [AIModel] {
        var models: [AIModel] = []

        if category == nil || category == .chat {
            models.append(contentsOf: allChatModels())
        }

        if category == nil || category == .local {
            models.append(contentsOf: mlxModelsAsAIModels())
        }

        if category == nil || category == .foundation {
            models.append(contentsOf: foundationModelsAsAIModels())
        }

        return models
    }

    /// Find a model by ID across all categories
    func model(for modelId: String) -> AIModel? {
        // Check chat models
        if let model = allChatModels().first(where: { $0.id == modelId }) {
            return model
        }

        // Check MLX models
        if let model = mlxModelsAsAIModels().first(where: { $0.id == modelId }) {
            return model
        }

        // Check foundation models
        if let model = foundationModelsAsAIModels().first(where: { $0.id == modelId }) {
            return model
        }

        return nil
    }

    /// Get the provider for a model ID
    func provider(for modelId: String) -> AIProvider? {
        for provider in chatProviders {
            if provider.models.contains(where: { $0.id == modelId }) {
                return provider.aiProvider
            }
        }

        if mlxModels().contains(where: { $0.id == modelId }) {
            return .localMLX
        }

        if foundationModels().contains(where: { $0.id == modelId }) {
            return .appleFoundation
        }

        return nil
    }

    // MARK: - Model Selection by Tier

    /// Result of a tier-based model selection
    struct ModelSelectionResult: Sendable {
        let provider: AIProvider
        let modelId: String
        let modelConfig: ModelConfig
        let selectedTier: ModelTier
        let wasExactMatch: Bool
    }

    /// Get all models that qualify for a selection tier, sorted by priority
    /// - Parameter tier: The selection tier to query
    /// - Returns: Array of (provider, modelConfig) tuples sorted by selection priority
    func modelsForTier(_ tier: ModelTier) -> [(AIProvider, ModelConfig)] {
        var results: [(AIProvider, ModelConfig, Int)] = []

        for providerConfig in chatProviders {
            guard let provider = providerConfig.aiProvider else { continue }

            for model in providerConfig.models {
                if model.effectiveSelectionTiers.contains(tier) {
                    results.append((provider, model, model.effectivePriority))
                }
            }
        }

        // Sort by priority (lower = higher priority)
        return results
            .sorted { $0.2 < $1.2 }
            .map { ($0.0, $0.1) }
    }

    /// Select the best model for a tier from configured providers
    /// - Parameters:
    ///   - tier: The desired selection tier
    ///   - isProviderConfigured: Closure to check if a provider has valid API key
    /// - Returns: ModelSelectionResult if a suitable model is found
    func selectModel(
        for tier: ModelTier,
        isProviderConfigured: (AIProvider) -> Bool
    ) -> ModelSelectionResult? {
        // Try the requested tier first
        for (provider, model) in modelsForTier(tier) {
            if isProviderConfigured(provider) {
                return ModelSelectionResult(
                    provider: provider,
                    modelId: model.id,
                    modelConfig: model,
                    selectedTier: tier,
                    wasExactMatch: true
                )
            }
        }

        // Try fallback tiers
        for fallbackTier in tier.fallbackOrder.dropFirst() {
            for (provider, model) in modelsForTier(fallbackTier) {
                if isProviderConfigured(provider) {
                    return ModelSelectionResult(
                        provider: provider,
                        modelId: model.id,
                        modelConfig: model,
                        selectedTier: fallbackTier,
                        wasExactMatch: false
                    )
                }
            }
        }

        return nil
    }

    /// Select the best model for a tier, preferring a specific provider if configured
    /// - Parameters:
    ///   - tier: The desired selection tier
    ///   - preferredProvider: Provider to prefer if configured
    ///   - isProviderConfigured: Closure to check if a provider has valid API key
    /// - Returns: ModelSelectionResult if a suitable model is found
    func selectModel(
        for tier: ModelTier,
        preferring preferredProvider: AIProvider?,
        isProviderConfigured: (AIProvider) -> Bool
    ) -> ModelSelectionResult? {
        // If we have a preferred provider, check it first
        if let preferred = preferredProvider, isProviderConfigured(preferred) {
            let providerModels = modelsForTier(tier).filter { $0.0 == preferred }
            if let (provider, model) = providerModels.first {
                return ModelSelectionResult(
                    provider: provider,
                    modelId: model.id,
                    modelConfig: model,
                    selectedTier: tier,
                    wasExactMatch: true
                )
            }
        }

        // Fall back to any configured provider
        return selectModel(for: tier, isProviderConfigured: isProviderConfigured)
    }

    /// Get recommended models for each tier (for UI display)
    func recommendedModelsPerTier(
        isProviderConfigured: (AIProvider) -> Bool
    ) -> [ModelTier: ModelSelectionResult] {
        var results: [ModelTier: ModelSelectionResult] = [:]

        for tier in ModelTier.allCases {
            if let result = selectModel(for: tier, isProviderConfigured: isProviderConfigured) {
                results[tier] = result
            }
        }

        return results
    }

    // MARK: - Validation

    /// Validate that Swift enums are in sync with JSON definitions
    func validateEnumSync() {
        // Validate Kokoro voices
        if let kokoroProvider = ttsProvider(.kokoro) {
            let jsonVoiceIds = Set(kokoroProvider.voices.map { $0.id })
            let enumVoiceIds = Set(KokoroTTSVoice.allCases.map { $0.rawValue })

            let missingInEnum = jsonVoiceIds.subtracting(enumVoiceIds)
            let missingInJSON = enumVoiceIds.subtracting(jsonVoiceIds)

            for voiceId in missingInEnum {
                validationWarnings.append(.voiceMissingInEnum(provider: "kokoro", voiceId: voiceId))
            }
            for voiceId in missingInJSON {
                validationWarnings.append(.voiceMissingInJSON(provider: "kokoro", voiceId: voiceId))
            }
        }

        // Validate Apple TTS voices
        if let appleProvider = ttsProvider(.apple) {
            let jsonVoiceIds = Set(appleProvider.voices.map { $0.id })
            let enumVoiceIds = Set(AppleTTSVoice.allCases.map { $0.rawValue })

            let missingInEnum = jsonVoiceIds.subtracting(enumVoiceIds)
            let missingInJSON = enumVoiceIds.subtracting(jsonVoiceIds)

            for voiceId in missingInEnum {
                validationWarnings.append(.voiceMissingInEnum(provider: "apple", voiceId: voiceId))
            }
            for voiceId in missingInJSON {
                validationWarnings.append(.voiceMissingInJSON(provider: "apple", voiceId: voiceId))
            }
        }

        // Validate OpenAI TTS voices
        if let openaiProvider = ttsProvider(.openai) {
            let jsonVoiceIds = Set(openaiProvider.voices.map { $0.id })
            let enumVoiceIds = Set(OpenAITTSVoice.allCases.map { $0.rawValue })

            let missingInEnum = jsonVoiceIds.subtracting(enumVoiceIds)
            let missingInJSON = enumVoiceIds.subtracting(jsonVoiceIds)

            for voiceId in missingInEnum {
                validationWarnings.append(.voiceMissingInEnum(provider: "openai", voiceId: voiceId))
            }
            for voiceId in missingInJSON {
                validationWarnings.append(.voiceMissingInJSON(provider: "openai", voiceId: voiceId))
            }
        }

        // Validate Gemini TTS voices
        if let geminiProvider = ttsProvider(.gemini) {
            let jsonVoiceIds = Set(geminiProvider.voices.map { $0.id })
            let enumVoiceIds = Set(GeminiTTSVoice.allCases.map { $0.rawValue })

            let missingInEnum = jsonVoiceIds.subtracting(enumVoiceIds)
            let missingInJSON = enumVoiceIds.subtracting(jsonVoiceIds)

            for voiceId in missingInEnum {
                validationWarnings.append(.voiceMissingInEnum(provider: "gemini", voiceId: voiceId))
            }
            for voiceId in missingInJSON {
                validationWarnings.append(.voiceMissingInJSON(provider: "gemini", voiceId: voiceId))
            }
        }

        // Log validation results
        if !validationWarnings.isEmpty {
            logger.warning("Registry validation found \(self.validationWarnings.count) warnings")
            for warning in validationWarnings {
                logger.warning("\(warning.description)")
            }
        } else {
            logger.info("Registry validation passed - all enums in sync with JSON")
        }
    }
}

// MARK: - Bridge Extensions for Backward Compatibility

extension AIProvider {
    /// Models from the unified registry (preferred over hardcoded availableModels)
    /// Falls back to hardcoded values if registry not loaded
    var registryModels: [AIModel] {
        let registry = UnifiedModelRegistry.shared
        guard registry.isLoaded else {
            return availableModels // Fallback to hardcoded
        }

        switch self {
        case .localMLX:
            return registry.mlxModelsAsAIModels()
        case .appleFoundation:
            return registry.foundationModelsAsAIModels()
        default:
            return registry.chatModels(for: self)
        }
    }
}

// Note: registryConfig bridge properties are defined in each enum's source file:
// - KokoroTTSVoice: KokoroTTSService.swift
// - AppleTTSVoice: AppleTTSService.swift
// - OpenAITTSVoice: TTSSettings.swift
// - GeminiTTSVoice: TTSSettings.swift
