//
//  ConversationRuntimeOverrideManager.swift
//  Axon
//
//  Manages conversation-scoped and turn-lease runtime overrides for
//  provider/model/sampling self-reconfiguration.
//

import Foundation

struct TurnLeaseRuntimeOverride: Codable, Equatable, Sendable {
    var provider: String?
    var model: String?
    var samplingOverride: ConversationSamplingOverride?
    var remainingTurns: Int
    var createdAt: Date
    var updatedAt: Date

    var hasAnyMutation: Bool {
        provider != nil || model != nil || (samplingOverride?.hasAnyValue == true)
    }
}

struct ResolvedRuntimeOverrides: Equatable, Sendable {
    let provider: String
    let model: String
    let providerDisplayName: String
    let modelParams: ModelGenerationSettings
    let activeTurnLease: TurnLeaseRuntimeOverride?
}

@MainActor
final class ConversationRuntimeOverrideManager {
    static let shared = ConversationRuntimeOverrideManager()

    private init() {}

    private func conversationOverridesKey(for conversationId: String) -> String {
        "conversation_overrides_\(conversationId)"
    }

    private func turnLeaseKey(for conversationId: String) -> String {
        "conversation_runtime_turn_lease_\(conversationId)"
    }

    func resolve(
        conversationId: String,
        baseProvider: String,
        baseModel: String,
        baseProviderDisplayName: String,
        baseModelParams: ModelGenerationSettings
    ) -> ResolvedRuntimeOverrides {
        var provider = normalizeProvider(baseProvider)
        var model = baseModel
        var providerDisplayName = baseProviderDisplayName
        var params = baseModelParams

        let conversationOverrides = loadConversationOverrides(conversationId: conversationId)
        if let sampling = conversationOverrides?.samplingOverride {
            applySamplingOverride(sampling, to: &params)
        }

        var activeLease: TurnLeaseRuntimeOverride?
        if let lease = loadTurnLease(conversationId: conversationId), lease.remainingTurns > 0 {
            // Defensive validation: ignore malformed lease states rather than failing send.
            if let leaseProvider = lease.provider {
                let normalizedLeaseProvider = normalizeProvider(leaseProvider)
                if parseProvider(normalizedLeaseProvider) != nil {
                    provider = normalizedLeaseProvider
                    providerDisplayName = displayName(for: normalizedLeaseProvider) ?? providerDisplayName
                }
            }

            if let leaseModel = lease.model {
                model = leaseModel
            }

            if let sampling = lease.samplingOverride {
                applySamplingOverride(sampling, to: &params)
            }

            activeLease = lease
        }

        return ResolvedRuntimeOverrides(
            provider: provider,
            model: model,
            providerDisplayName: providerDisplayName,
            modelParams: params,
            activeTurnLease: activeLease
        )
    }

    func loadConversationOverrides(conversationId: String) -> ConversationOverrides? {
        let key = conversationOverridesKey(for: conversationId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) else {
            return nil
        }
        return overrides
    }

    func saveConversationOverrides(_ overrides: ConversationOverrides, conversationId: String) {
        let key = conversationOverridesKey(for: conversationId)
        if let data = try? JSONEncoder().encode(overrides) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func setConversationRuntimeOverrides(
        conversationId: String,
        provider: AIProvider?,
        model: String?,
        samplingOverride: ConversationSamplingOverride?
    ) {
        var overrides = loadConversationOverrides(conversationId: conversationId) ?? ConversationOverrides()

        if let provider {
            overrides.builtInProvider = provider.rawValue
            overrides.customProviderId = nil
            overrides.providerDisplayName = provider.displayName
        }

        if let model {
            overrides.builtInModel = model
            overrides.customModelId = nil
            if let providerRaw = overrides.builtInProvider,
               let resolvedProvider = AIProvider(rawValue: providerRaw),
               let resolvedModel = UnifiedModelRegistry.shared.model(for: model)
                    ?? UnifiedModelRegistry.shared.chatModels(for: resolvedProvider).first(where: { $0.id == model }) {
                overrides.modelDisplayName = resolvedModel.name
            }
        }

        if let samplingOverride {
            overrides.samplingOverride = samplingOverride.hasAnyValue ? samplingOverride : nil
        }

        saveConversationOverrides(overrides, conversationId: conversationId)
    }

    func clearConversationRuntimeOverrides(conversationId: String) {
        guard var overrides = loadConversationOverrides(conversationId: conversationId) else {
            return
        }

        overrides.builtInProvider = nil
        overrides.customProviderId = nil
        overrides.builtInModel = nil
        overrides.customModelId = nil
        overrides.providerDisplayName = nil
        overrides.modelDisplayName = nil
        overrides.samplingOverride = nil

        saveConversationOverrides(overrides, conversationId: conversationId)
    }

    func setTurnLease(
        conversationId: String,
        turns: Int,
        provider: String?,
        model: String?,
        samplingOverride: ConversationSamplingOverride?
    ) {
        let lease = TurnLeaseRuntimeOverride(
            provider: provider.map(normalizeProvider),
            model: model,
            samplingOverride: samplingOverride?.hasAnyValue == true ? samplingOverride : nil,
            remainingTurns: turns,
            createdAt: Date(),
            updatedAt: Date()
        )

        guard lease.hasAnyMutation else {
            return
        }

        let key = turnLeaseKey(for: conversationId)
        if let data = try? JSONEncoder().encode(lease) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func loadTurnLease(conversationId: String) -> TurnLeaseRuntimeOverride? {
        let key = turnLeaseKey(for: conversationId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let lease = try? JSONDecoder().decode(TurnLeaseRuntimeOverride.self, from: data) else {
            return nil
        }
        return lease
    }

    func clearTurnLease(conversationId: String) {
        UserDefaults.standard.removeObject(forKey: turnLeaseKey(for: conversationId))
    }

    /// Decrement turn lease only after a successful assistant reply.
    func consumeTurnLeaseOnSuccessfulReply(conversationId: String) {
        guard var lease = loadTurnLease(conversationId: conversationId), lease.remainingTurns > 0 else {
            return
        }

        lease.remainingTurns -= 1
        lease.updatedAt = Date()

        if lease.remainingTurns <= 0 {
            clearTurnLease(conversationId: conversationId)
            return
        }

        let key = turnLeaseKey(for: conversationId)
        if let data = try? JSONEncoder().encode(lease) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func normalizeProvider(_ provider: String) -> String {
        provider.lowercased() == "xai" ? "grok" : provider
    }

    func parseProvider(_ providerString: String) -> AIProvider? {
        let normalized = normalizeProvider(providerString).trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return nil
        }

        if let provider = AIProvider(rawValue: normalized) {
            return provider
        }

        switch normalized.lowercased() {
        case "grok", "xai":
            return .xai
        case "claude", "anthropic":
            return .anthropic
        case "gpt", "openai", "chatgpt":
            return .openai
        case "gemini", "google":
            return .gemini
        case "perplexity", "sonar":
            return .perplexity
        case "deepseek":
            return .deepseek
        case "zai", "glm":
            return .zai
        case "minimax":
            return .minimax
        case "mistral":
            return .mistral
        case "apple", "applefoundation", "apple_foundation", "apple-foundation":
            return .appleFoundation
        case "local", "mlx", "localmlx", "local_mlx", "local-mlx":
            return .localMLX
        default:
            return nil
        }
    }

    func displayName(for providerString: String) -> String? {
        parseProvider(providerString)?.displayName
    }

    func applySamplingOverride(_ override: ConversationSamplingOverride, to settings: inout ModelGenerationSettings) {
        if let temperature = override.temperature {
            settings.temperature = temperature
            settings.temperatureEnabled = true
        }
        if let topP = override.topP {
            settings.topP = topP
            settings.topPEnabled = true
        }
        if let topK = override.topK {
            settings.topK = topK
            settings.topKEnabled = true
        }
    }
}
