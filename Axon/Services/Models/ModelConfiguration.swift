//
//  ModelConfiguration.swift
//  Axon
//
//  JSON-based model configuration types for dynamic model management
//

import Foundation

// MARK: - Root Configuration

/// Root configuration containing all providers and their models
struct ModelCatalog: Codable, Equatable, Sendable {
    let version: String
    let lastUpdated: Date
    let providers: [ProviderConfig]

    enum CodingKeys: String, CodingKey {
        case version, lastUpdated, providers
    }

    init(version: String, lastUpdated: Date, providers: [ProviderConfig]) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.providers = providers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        providers = try container.decode([ProviderConfig].self, forKey: .providers)

        // Handle ISO8601 date string
        let dateString = try container.decode(String.self, forKey: .lastUpdated)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            lastUpdated = date
        } else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                lastUpdated = date
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .lastUpdated,
                    in: container,
                    debugDescription: "Invalid date format: \(dateString)"
                )
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(providers, forKey: .providers)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        try container.encode(formatter.string(from: lastUpdated), forKey: .lastUpdated)
    }
}

// MARK: - Provider Configuration

/// Configuration for a single AI provider
struct ProviderConfig: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let models: [ModelConfig]

    /// Maps to our existing AIProvider enum
    var aiProvider: AIProvider? {
        AIProvider(rawValue: id)
    }
}

// MARK: - Model Configuration

/// Configuration for a single AI model
struct ModelConfig: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let category: ModelCategory
    let contextWindow: Int
    let modalities: [String]
    let pricing: ModelPricingConfig
    let status: ModelStatus
    let capabilitiesSummary: String
    let sourceUrls: [String]?

    /// Selection tiers this model is appropriate for (e.g., ["fast", "cheap"])
    /// Used by automatic model selection to pick appropriate models for tasks
    let selectionTiers: [ModelTier]?

    /// Priority within its selection tiers (lower = higher priority, default = 100)
    /// Used to order models when multiple qualify for a tier
    let selectionPriority: Int?

    /// Whether this model supports live/real-time audio conversations
    /// Used to filter models in Live Voice settings
    let supportsLiveAudio: Bool?

    /// Convert to the existing AIModel type for compatibility
    func toAIModel(provider: AIProvider) -> AIModel {
        AIModel(
            id: id,
            name: displayName,
            provider: provider,
            contextWindow: contextWindow,
            modalities: modalities,
            description: capabilitiesSummary
        )
    }

    /// Computed selection tiers based on explicit value or category fallback
    var effectiveSelectionTiers: [ModelTier] {
        if let explicit = selectionTiers, !explicit.isEmpty {
            return explicit
        }
        // Fallback: infer from category
        return category.defaultSelectionTiers
    }

    /// Computed priority (default 100 if not specified)
    var effectivePriority: Int {
        selectionPriority ?? 100
    }
}

// MARK: - Model Category

enum ModelCategory: String, Codable, Sendable {
    case frontier   // Most capable, expensive models
    case reasoning  // Chain-of-thought / extended thinking models
    case fast       // Quick, cost-effective models
    case legacy     // Older generation models

    /// Default selection tiers based on category (used when selectionTiers not explicitly set)
    var defaultSelectionTiers: [ModelTier] {
        switch self {
        case .frontier:
            return [.flagship, .capable, .balanced]
        case .reasoning:
            return [.capable, .flagship]
        case .fast:
            return [.fast, .cheap, .balanced]
        case .legacy:
            return [.balanced]  // Legacy models are fallbacks
        }
    }
}

// MARK: - Model Tier Extensions

extension ModelTier {
    /// Fallback order when this tier isn't available
    var fallbackOrder: [ModelTier] {
        switch self {
        case .fast: return [.fast, .cheap, .balanced, .capable, .flagship]
        case .cheap: return [.cheap, .fast, .balanced, .capable, .flagship]
        case .balanced: return [.balanced, .capable, .cheap, .fast, .flagship]
        case .capable: return [.capable, .balanced, .flagship, .cheap, .fast]
        case .flagship: return [.flagship, .capable, .balanced, .cheap, .fast]
        }
    }
}

// MARK: - Model Status

enum ModelStatus: String, Codable, Sendable {
    case stable     // Generally available
    case preview    // Beta / preview
    case deprecated // Being phased out
}

// MARK: - Pricing Configuration

struct ModelPricingConfig: Codable, Equatable, Sendable {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cachedInputPerMillion: Double?
    let tier: PricingTier?

    // Audio-specific pricing (for live audio models)
    let audioInputPerMillion: Double?
    let audioOutputPerMillion: Double?

    /// Convert to existing ModelPricing type for CostService compatibility
    func toModelPricing() -> ModelPricing {
        ModelPricing(
            inputPerMTokUSD: inputPerMillion,
            outputPerMTokUSD: outputPerMillion,
            cachedInputPerMTokUSD: cachedInputPerMillion,
            notes: tier?.rawValue
        )
    }
}

enum PricingTier: String, Codable, Sendable {
    case free
    case standard
    case priority
    case batch
    case flex
}

// MARK: - Configuration Metadata

/// Metadata about a configuration file
struct ConfigurationMetadata: Codable, Equatable, Sendable {
    let version: String
    let lastUpdated: Date
    let source: ConfigurationSource
    let providerCount: Int
    let modelCount: Int
}

enum ConfigurationSource: String, Codable, Sendable {
    case bundled     // Shipped with app
    case userActive  // User's active configuration
    case userDraft   // User's draft configuration (pending approval)
    case synced      // Updated via Perplexity sync
}

// MARK: - Validation

extension ModelCatalog {
    /// Validates the catalog structure and returns any issues found
    func validate() -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []

        // Check for duplicate provider IDs
        let providerIds = providers.map { $0.id }
        let duplicateProviders = Dictionary(grouping: providerIds, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
        for id in duplicateProviders {
            issues.append(.duplicateProviderId(id))
        }

        // Check each provider
        for provider in providers {
            // Check for duplicate model IDs within provider
            let modelIds = provider.models.map { $0.id }
            let duplicateModels = Dictionary(grouping: modelIds, by: { $0 })
                .filter { $0.value.count > 1 }
                .keys
            for id in duplicateModels {
                issues.append(.duplicateModelId(provider: provider.id, modelId: id))
            }

            // Check each model
            for model in provider.models {
                // Validate pricing
                if model.pricing.inputPerMillion < 0 {
                    issues.append(.invalidPricing(modelId: model.id, field: "inputPerMillion"))
                }
                if model.pricing.outputPerMillion < 0 {
                    issues.append(.invalidPricing(modelId: model.id, field: "outputPerMillion"))
                }
                if let cached = model.pricing.cachedInputPerMillion, cached < 0 {
                    issues.append(.invalidPricing(modelId: model.id, field: "cachedInputPerMillion"))
                }

                // Validate context window
                if model.contextWindow <= 0 {
                    issues.append(.invalidContextWindow(modelId: model.id))
                }
            }
        }

        return issues
    }
}

enum ConfigurationIssue: Equatable, Sendable {
    case duplicateProviderId(String)
    case duplicateModelId(provider: String, modelId: String)
    case invalidPricing(modelId: String, field: String)
    case invalidContextWindow(modelId: String)
    case parseError(String)

    var description: String {
        switch self {
        case .duplicateProviderId(let id):
            return "Duplicate provider ID: \(id)"
        case .duplicateModelId(let provider, let modelId):
            return "Duplicate model ID '\(modelId)' in provider '\(provider)'"
        case .invalidPricing(let modelId, let field):
            return "Invalid pricing for model '\(modelId)': \(field) must be non-negative"
        case .invalidContextWindow(let modelId):
            return "Invalid context window for model '\(modelId)': must be positive"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
