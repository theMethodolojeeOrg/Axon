//
//  ProviderKitModelCatalogAdapter.swift
//  Axon
//
//  Bridges Axon's app-local model types to AxonProviderKit's catalog.
//

import Foundation
import AxonProviderKitCore

enum ProviderKitModelCatalogAdapter {
    typealias PKProvider = AxonProviderKitCore.AIProvider
    typealias PKModel = AxonProviderKitCore.AIModel
    typealias PKMetadata = AxonProviderKitCore.AIModelMetadata
    typealias PKPricing = AxonProviderKitCore.AIModelPricing
    typealias PKTier = AxonProviderKitCore.AIModelSelectionTier

    static let appleFoundationModelId = "apple-foundation-default"

    private static let providerOrder: [AIProvider] = [
        .anthropic,
        .openai,
        .gemini,
        .xai,
        .perplexity,
        .deepseek,
        .zai,
        .minimax,
        .mistral,
        .appleFoundation,
        .localMLX
    ]

    private static let policy = AIProviderAccessPolicy.allowing([
        .anthropic,
        .openai,
        .gemini,
        .xai,
        .perplexity,
        .deepseek,
        .zai,
        .minimax,
        .mistral,
        .appleIntelligence,
        .mlx
    ])

    static func bootstrapMLXCatalog() {
        if MLXModelConfigLoader.shared.config.models.isEmpty {
            MLXModelConfigLoader.shared.loadFromBundle()
        }
        if MLXModelRegistry.shared.registeredModels.isEmpty {
            let bundledIds = Set(
                MLXModelConfigLoader.shared.config.models
                    .filter { $0.bundled == true }
                    .map(\.id)
            )
            MLXModelRegistry.shared.syncFromDownloadedIds(bundledIds)
        }
    }

    static func providerKitProvider(for provider: AIProvider) -> PKProvider? {
        switch provider {
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .gemini: return .gemini
        case .xai: return .xai
        case .perplexity: return .perplexity
        case .deepseek: return .deepseek
        case .zai: return .zai
        case .minimax: return .minimax
        case .mistral: return .mistral
        case .appleFoundation: return .appleIntelligence
        case .localMLX: return .mlx
        }
    }

    static func axonProvider(for provider: PKProvider) -> AIProvider? {
        switch provider {
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .gemini: return .gemini
        case .xai: return .xai
        case .perplexity: return .perplexity
        case .deepseek: return .deepseek
        case .zai: return .zai
        case .minimax: return .minimax
        case .mistral: return .mistral
        case .appleIntelligence: return .appleFoundation
        case .mlx: return .localMLX
        case .venice, .openAICompatible, .aiEdge:
            return nil
        }
    }

    static func providerKitModelId(for axonModelId: String, provider: AIProvider? = nil) -> String {
        if axonModelId == appleFoundationModelId || provider == .appleFoundation && axonModelId == "default" {
            return "default"
        }
        return axonModelId
    }

    static func axonModelId(for provider: AIProvider, modelId: String) -> String {
        provider == .appleFoundation && modelId == "default" ? appleFoundationModelId : modelId
    }

    static func models(for provider: AIProvider) -> [AIModel] {
        bootstrapMLXCatalogIfNeeded(for: provider)
        guard let pkProvider = providerKitProvider(for: provider) else { return [] }

        return AIModelCatalog.models(for: pkProvider, policy: policy)
            .compactMap { model in axonModel(from: model, provider: provider) }
    }

    static func chatModels(for provider: AIProvider) -> [AIModel] {
        guard provider != .localMLX && provider != .appleFoundation else { return [] }
        return models(for: provider)
    }

    static func allChatModels() -> [AIModel] {
        providerOrder
            .filter { $0 != .localMLX && $0 != .appleFoundation }
            .flatMap { models(for: $0) }
    }

    static func allModels() -> [AIModel] {
        providerOrder.flatMap { models(for: $0) }
    }

    static func liveAudioModels(for provider: AIProvider) -> [AIModel] {
        metadata(for: provider)
            .filter(\.capabilities.supportsLiveAudio)
            .compactMap { axonModel(from: $0.model, provider: provider) }
    }

    static func allLiveAudioModels() -> [AIModel] {
        providerOrder.flatMap { liveAudioModels(for: $0) }
    }

    static func model(for modelId: String) -> AIModel? {
        for provider in providerOrder {
            if let model = model(for: modelId, provider: provider) {
                return model
            }
        }
        return nil
    }

    static func model(for modelId: String, provider: AIProvider) -> AIModel? {
        let providerKitId = providerKitModelId(for: modelId, provider: provider)
        return models(for: provider).first { providerKitModelId(for: $0.id, provider: provider) == providerKitId }
    }

    static func provider(for modelId: String) -> AIProvider? {
        providerOrder.first { model(for: modelId, provider: $0) != nil }
    }

    static func contextWindow(for modelId: String, settings: AppSettings? = nil) -> Int {
        if let model = model(for: modelId) {
            return model.contextWindow
        }

        if let settings {
            for customProvider in settings.customProviders {
                if let model = customProvider.models.first(where: { $0.modelCode == modelId || $0.id.uuidString == modelId }) {
                    return model.contextWindow
                }
            }
        }

        return 128_000
    }

    static func pricing(
        for modelId: String,
        usedContextTokens: Int? = nil,
        inputIsAudio: Bool = false
    ) -> ModelPricing? {
        guard let provider = provider(for: modelId),
              let metadata = metadata(for: provider, modelId: modelId) else {
            return nil
        }
        return modelPricing(
            from: metadata.pricing.resolved(
                usedContextTokens: usedContextTokens,
                inputIsAudio: inputIsAudio
            )
        )
    }

    static func modelConfig(for modelId: String) -> ModelConfig? {
        guard let provider = provider(for: modelId),
              let metadata = metadata(for: provider, modelId: modelId) else {
            return nil
        }
        return modelConfig(from: metadata, provider: provider)
    }

    static func modelsForTier(_ tier: ModelTier) -> [(AIProvider, ModelConfig)] {
        let pkTier = providerKitTier(for: tier)
        return AIModelCatalog.modelsForTier(pkTier, policy: policy)
            .compactMap { pkProvider, metadata in
                guard let provider = axonProvider(for: pkProvider) else { return nil }
                return (provider, modelConfig(from: metadata, provider: provider))
            }
    }

    static func selectModel(
        for tier: ModelTier,
        preferring preferredProvider: AIProvider? = nil,
        isProviderConfigured: (AIProvider) -> Bool
    ) -> UnifiedModelRegistry.ModelSelectionResult? {
        if let preferredProvider, isProviderConfigured(preferredProvider) {
            let preferredModels = modelsForTier(tier).filter { $0.0 == preferredProvider }
            if let (provider, modelConfig) = preferredModels.first {
                return UnifiedModelRegistry.ModelSelectionResult(
                    provider: provider,
                    modelId: modelConfig.id,
                    modelConfig: modelConfig,
                    selectedTier: tier,
                    wasExactMatch: true
                )
            }
        }

        let pkTier = providerKitTier(for: tier)
        guard let selection = AIModelCatalog.selectModel(
            for: pkTier,
            policy: policy,
            isProviderConfigured: { pkProvider in
                guard let provider = axonProvider(for: pkProvider) else { return false }
                return isProviderConfigured(provider)
            }
        ),
              let provider = axonProvider(for: selection.provider) else {
            return nil
        }

        return UnifiedModelRegistry.ModelSelectionResult(
            provider: provider,
            modelId: axonModelId(for: provider, modelId: selection.modelId),
            modelConfig: modelConfig(from: selection.metadata, provider: provider),
            selectedTier: axonTier(for: selection.selectedTier),
            wasExactMatch: selection.wasExactMatch
        )
    }

    static func catalogSnapshot() -> ModelCatalog {
        bootstrapMLXCatalog()
        let providers = providerOrder.compactMap { provider -> ProviderConfig? in
            let modelConfigs = metadata(for: provider)
                .map { modelConfig(from: $0, provider: provider) }
            guard !modelConfigs.isEmpty else { return nil }
            return ProviderConfig(
                id: provider.rawValue,
                displayName: provider.displayName,
                models: modelConfigs
            )
        }

        return ModelCatalog(
            version: "providerkit",
            lastUpdated: Date(),
            providers: providers
        )
    }

    private static func metadata(for provider: AIProvider) -> [PKMetadata] {
        bootstrapMLXCatalogIfNeeded(for: provider)
        guard let pkProvider = providerKitProvider(for: provider) else { return [] }
        return AIModelCatalog.models(for: pkProvider, policy: policy).map {
            AIModelCatalog.metadata(for: $0)
        }
    }

    private static func metadata(for provider: AIProvider, modelId: String) -> PKMetadata? {
        bootstrapMLXCatalogIfNeeded(for: provider)
        guard let pkProvider = providerKitProvider(for: provider) else { return nil }
        let providerKitId = providerKitModelId(for: modelId, provider: provider)
        return AIModelCatalog.metadata(for: pkProvider, model: providerKitId, policy: policy)
    }

    private static func axonModel(from model: PKModel, provider: AIProvider) -> AIModel {
        AIModel(
            id: axonModelId(for: provider, modelId: model.id),
            name: model.name,
            provider: provider,
            contextWindow: model.contextWindow,
            modalities: model.modalities,
            description: model.description
        )
    }

    private static func modelConfig(from metadata: PKMetadata, provider: AIProvider) -> ModelConfig {
        let model = metadata.model
        let pricing = metadata.pricing
        return ModelConfig(
            id: axonModelId(for: provider, modelId: model.id),
            displayName: model.name,
            category: modelCategory(from: metadata.category),
            contextWindow: model.contextWindow,
            modalities: model.modalities,
            pricing: modelPricingConfig(from: pricing),
            status: modelStatus(from: metadata.status),
            capabilitiesSummary: model.description,
            sourceUrls: metadata.sourceURLs.map(\.absoluteString),
            selectionTiers: metadata.selectionTiers.map(axonTier(for:)),
            selectionPriority: metadata.selectionPriority,
            supportsLiveAudio: metadata.supportsLiveAudio
        )
    }

    private static func modelPricing(from pricing: PKPricing) -> ModelPricing? {
        switch pricing.availability {
        case .known:
            guard let input = pricing.inputPerMillion,
                  let output = pricing.outputPerMillion else {
                return nil
            }
            return ModelPricing(
                inputPerMTokUSD: input,
                outputPerMTokUSD: output,
                cachedInputPerMTokUSD: pricing.cachedInputPerMillion,
                notes: pricing.notes
            )
        case .free:
            return ModelPricing(
                inputPerMTokUSD: 0,
                outputPerMTokUSD: 0,
                cachedInputPerMTokUSD: 0,
                notes: pricing.notes
            )
        case .unknown:
            return nil
        }
    }

    private static func modelPricingConfig(from pricing: PKPricing) -> ModelPricingConfig {
        ModelPricingConfig(
            inputPerMillion: pricing.inputPerMillion ?? 0,
            outputPerMillion: pricing.outputPerMillion ?? 0,
            cachedInputPerMillion: pricing.cachedInputPerMillion,
            tier: pricingTier(from: pricing),
            audioInputPerMillion: pricing.audioInputPerMillion,
            audioOutputPerMillion: pricing.audioOutputPerMillion
        )
    }

    private static func modelCategory(from category: AIModelCategory) -> ModelCategory {
        switch category {
        case .frontier: return .frontier
        case .reasoning: return .reasoning
        case .fast: return .fast
        case .legacy: return .legacy
        case .local: return .local
        case .foundation: return .foundation
        }
    }

    private static func modelStatus(from status: AIModelStatus) -> ModelStatus {
        switch status {
        case .stable: return .stable
        case .preview: return .preview
        case .deprecated: return .deprecated
        }
    }

    private static func pricingTier(from pricing: PKPricing) -> PricingTier {
        switch pricing.availability {
        case .unknown:
            return .unknown
        case .free:
            return .free
        case .known:
            switch pricing.pricingTier {
            case .free: return .free
            case .standard: return .standard
            case .priority: return .priority
            case .batch: return .batch
            case .flex: return .flex
            case .unknown: return .unknown
            }
        }
    }

    private nonisolated static func providerKitTier(for tier: ModelTier) -> PKTier {
        switch tier {
        case .fast: return .fast
        case .cheap: return .cheap
        case .balanced: return .balanced
        case .capable: return .capable
        case .flagship: return .flagship
        }
    }

    private nonisolated static func axonTier(for tier: PKTier) -> ModelTier {
        switch tier {
        case .fast: return .fast
        case .cheap: return .cheap
        case .balanced: return .balanced
        case .capable: return .capable
        case .flagship: return .flagship
        }
    }

    private static func bootstrapMLXCatalogIfNeeded(for provider: AIProvider) {
        if provider == .localMLX {
            bootstrapMLXCatalog()
        }
    }
}
