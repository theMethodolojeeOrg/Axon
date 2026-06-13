//
//  APIProvider.swift
//  Axon
//
//  API provider enum for key storage and service calls
//

import Foundation
import AxonProviderKitCore

// MARK: - API Provider

enum APIProvider: String, CaseIterable, Identifiable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case xai = "xai"
    case elevenlabs = "elevenlabs"
    case perplexity = "perplexity"
    case deepseek = "deepseek"
    case zai = "zai"
    case minimax = "minimax"
    case mistral = "mistral"
    case venice = "venice"

    nonisolated var id: String { rawValue }

    nonisolated init?(chatProvider provider: AIProvider) {
        guard provider.requiresAPIKey,
              let providerKitProvider = provider.providerKitProvider,
              providerKitProvider != .openAICompatible else {
            return nil
        }
        self.init(rawValue: providerKitProvider.rawValue)
    }

    nonisolated var displayName: String {
        if let providerKitProvider {
            return providerKitProvider.displayName
        }

        switch self {
        case .elevenlabs: return "ElevenLabs"
        default: return rawValue
        }
    }

    nonisolated var apiKeyPlaceholder: String {
        if let placeholder = providerKitProvider?.apiKeyPlaceholder {
            return placeholder
        }

        switch self {
        case .elevenlabs: return "sk_..."
        default: return "..."
        }
    }

    nonisolated var infoURL: URL? {
        if let providerKitURL = providerKitProvider?.credentialInfoURL {
            return providerKitURL
        }

        switch self {
        case .elevenlabs: return URL(string: "https://elevenlabs.io/app/settings/api-keys")
        default: return nil
        }
    }

    nonisolated var description: String {
        if let providerKitProvider {
            return providerKitProvider.credentialDescription
        }

        switch self {
        case .elevenlabs: return "Required for text-to-speech"
        default: return "Required for \(displayName) models"
        }
    }

    nonisolated var providerKitProvider: AxonProviderKitCore.AIProvider? {
        AxonProviderKitCore.AIProvider(rawValue: rawValue)
    }

    nonisolated static var chatProviders: [APIProvider] {
        AIProvider.providerKitBackedCases.compactMap(APIProvider.init(chatProvider:))
    }

    nonisolated static var ttsProviders: [APIProvider] {
        [.elevenlabs]
    }

    nonisolated static var credentialSettingsProviders: [APIProvider] {
        chatProviders + ttsProviders
    }

    nonisolated static var chatProviderCount: Int {
        chatProviders.count
    }
}

extension AIProvider {
    nonisolated var credentialDescription: String {
        providerKitProvider?.credentialDescription ?? ""
    }

    nonisolated var credentialInfoURL: URL? {
        providerKitProvider?.credentialInfoURL
    }

    nonisolated var apiKeyPlaceholder: String? {
        providerKitProvider?.apiKeyPlaceholder
    }
}

extension APIProvider {
    nonisolated var chatProvider: AIProvider? {
        AIProvider.providerKitBackedCases.first { $0.rawValue == rawValue }
    }
}
