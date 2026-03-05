//
//  ConversationModelResolver.swift
//  Axon
//
//  Shared resolver for determining the effective provider + model for a conversation,
//  including conversation overrides and custom providers.
//

import Foundation

/// Centralized resolver for the effective provider/model used for a conversation.
///
/// This exists to prevent UI (e.g., attachment capability) from drifting out-of-sync
/// with the actual send path in `ConversationService`.
enum ConversationModelResolver {

    /// Resolved provider/model tuple.
    ///
    /// - provider: The provider string used by orchestration (e.g., "anthropic", "openai", "gemini", "openai-compatible").
    /// - modelId: The API identifier used by the provider (e.g., "claude-haiku-4-5-20251001").
    ///           For custom providers this is the modelCode.
    /// - modelDisplayName: Human-readable model name for UI.
    /// - providerName: Human-readable provider name for UI.
    struct ResolvedProviderModel {
        let provider: String
        let modelId: String
        let modelDisplayName: String
        let providerName: String

        var normalizedProvider: String {
            // Fix for Grok: map "xai" to "grok" everywhere.
            provider == "xai" ? "grok" : provider
        }
    }

    /// Resolve effective provider/model for a specific conversation.
    ///
    /// Mirrors the logic previously inside `ConversationService.getProviderAndModel`.
    static func resolve(conversationId: String, settings: AppSettings) -> ResolvedProviderModel {
        // Check for conversation overrides
        let overridesKey = "conversation_overrides_\(conversationId)"
        if let data = UserDefaults.standard.data(forKey: overridesKey),
           let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {

            // Custom provider override
            if let customProviderId = overrides.customProviderId,
               let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
               let customModelId = overrides.customModelId,
               let customModel = customProvider.models.first(where: { $0.id == customModelId }) {

                // For custom providers, modelCode is the API identifier
                let modelId = customModel.modelCode
                let modelDisplayName = overrides.modelDisplayName
                    ?? customModel.friendlyName
                    ?? customProvider.providerName
                let providerDisplay = overrides.providerDisplayName ?? customProvider.providerName

                return ResolvedProviderModel(
                    provider: "openai-compatible",
                    modelId: modelId,
                    modelDisplayName: modelDisplayName,
                    providerName: providerDisplay
                )
            }

            // Built-in provider override
            if let builtInProvider = overrides.builtInProvider,
               let provider = AIProvider(rawValue: builtInProvider),
               let builtInModel = overrides.builtInModel,
               let model = UnifiedModelRegistry.shared.model(for: builtInModel) ?? provider.availableModels.first(where: { $0.id == builtInModel }) {

                let modelDisplayName = overrides.modelDisplayName ?? model.name
                let providerDisplay = overrides.providerDisplayName ?? provider.displayName

                return ResolvedProviderModel(
                    provider: provider.rawValue,
                    modelId: model.id,
                    modelDisplayName: modelDisplayName,
                    providerName: providerDisplay
                )
            }
        }

        // Fallback to global settings (custom)
        if let customProviderId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
           let customModelId = settings.selectedCustomModelId,
           let customModel = customProvider.models.first(where: { $0.id == customModelId }) {

            let modelId = customModel.modelCode
            let modelDisplayName = customModel.friendlyName ?? customProvider.providerName

            return ResolvedProviderModel(
                provider: "openai-compatible",
                modelId: modelId,
                modelDisplayName: modelDisplayName,
                providerName: customProvider.providerName
            )
        }

        // Default: built-in provider
        let provider = settings.defaultProvider
        let model = UnifiedModelRegistry.shared.model(for: settings.defaultModel)
            ?? UnifiedModelRegistry.shared.chatModels(for: provider).first
            ?? provider.availableModels.first(where: { $0.id == settings.defaultModel })
            ?? provider.availableModels.first

        return ResolvedProviderModel(
            provider: provider.rawValue,
            modelId: model?.id ?? "unknown",
            modelDisplayName: model?.name ?? "Unknown",
            providerName: provider.displayName
        )
    }

    /// Convenience for resolving without a conversation id (global settings only).
    static func resolveGlobal(settings: AppSettings) -> ResolvedProviderModel {
        // Use a dummy conversationId to share logic, but skip override lookup.
        // We intentionally replicate only the global branch to avoid accidental override reads.
        if let customProviderId = settings.selectedCustomProviderId,
           let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }),
           let customModelId = settings.selectedCustomModelId,
           let customModel = customProvider.models.first(where: { $0.id == customModelId }) {

            return ResolvedProviderModel(
                provider: "openai-compatible",
                modelId: customModel.modelCode,
                modelDisplayName: customModel.friendlyName ?? customProvider.providerName,
                providerName: customProvider.providerName
            )
        }

        let provider = settings.defaultProvider
        let model = UnifiedModelRegistry.shared.model(for: settings.defaultModel)
            ?? UnifiedModelRegistry.shared.chatModels(for: provider).first
            ?? provider.availableModels.first(where: { $0.id == settings.defaultModel })
            ?? provider.availableModels.first

        return ResolvedProviderModel(
            provider: provider.rawValue,
            modelId: model?.id ?? "unknown",
            modelDisplayName: model?.name ?? "Unknown",
            providerName: provider.displayName
        )
    }
}
