//
//  AIProvider.swift
//  Axon
//
//  AI providers and models
//

import Foundation
import AxonProviderKitCore

// MARK: - AI Providers

enum AIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"
    case xai = "xai"
    case perplexity = "perplexity"
    case deepseek = "deepseek"
    case zai = "zai"
    case minimax = "minimax"
    case mistral = "mistral"
    case venice = "venice"
    case appleFoundation = "appleFoundation"
    case localMLX = "localMLX"
    case aiEdge = "aiEdge"

    nonisolated var id: String { rawValue }

    /// Map AIProvider to APIProvider for key storage and low-level service calls
    nonisolated var apiProvider: APIProvider? {
        APIProvider(chatProvider: self)
    }

    nonisolated var displayName: String {
        providerKitProvider?.displayName ?? rawValue
    }

    var availableModels: [AIModel] {
        ProviderKitModelCatalogAdapter.models(for: self)
    }

    /// Whether this provider is available on the current device/OS
    nonisolated var isAvailable: Bool {
        providerKitProvider?.isAvailable ?? false
    }

    /// Human-readable reason if provider is unavailable
    nonisolated var unavailableReason: String? {
        providerKitProvider?.unavailabilityReason
    }

    /// ProviderKit counterpart for built-in providers. ProviderKit's generic
    /// OpenAI-compatible provider remains represented by Axon's custom providers.
    nonisolated var providerKitProvider: AxonProviderKitCore.AIProvider? {
        switch self {
        case .anthropic: return .anthropic
        case .openai: return .openai
        case .gemini: return .gemini
        case .xai: return .xai
        case .perplexity: return .perplexity
        case .deepseek: return .deepseek
        case .zai: return .zai
        case .minimax: return .minimax
        case .mistral: return .mistral
        case .venice: return .venice
        case .appleFoundation: return .appleIntelligence
        case .localMLX: return .mlx
        case .aiEdge: return .aiEdge
        }
    }

    nonisolated var isOnDevice: Bool {
        providerKitProvider?.isOnDevice ?? false
    }

    nonisolated var requiresAPIKey: Bool {
        providerKitProvider?.requiresAPIKey ?? false
    }

    nonisolated static var providerKitBackedCases: [AIProvider] {
        AxonProviderKitCore.AIModelCatalog
            .availableProviders(policy: .all)
            .compactMap { provider in
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
                case .venice: return .venice
                case .appleIntelligence: return .appleFoundation
                case .mlx: return .localMLX
                case .aiEdge: return .aiEdge
                case .openAICompatible: return nil
                }
            }
    }

    /// Find context window for a model ID across all providers
    /// Returns default of 128K if not found
    static func contextWindowForModel(_ modelId: String, settings: AppSettings? = nil) -> Int {
        ProviderKitModelCatalogAdapter.contextWindow(for: modelId, settings: settings)
    }
}

// MARK: - AI Model

struct AIModel: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let provider: AIProvider
    let contextWindow: Int
    let modalities: [String]
    let description: String
}

// MARK: - User MLX Model (from Hugging Face)

/// User-added MLX model downloaded from Hugging Face
struct UserMLXModel: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let repoId: String              // e.g., "mlx-community/Qwen3-VL-2B-Instruct-4bit"
    let displayName: String         // e.g., "Qwen3 VL 2B"
    var downloadStatus: DownloadStatus
    var sizeBytes: Int64?
    var contextWindow: Int          // from model config or default
    var modalities: [String]        // ["text"], ["text", "vision"], etc.
    var addedAt: Date

    enum DownloadStatus: String, Codable, Sendable {
        case notDownloaded
        case downloading
        case downloaded
        case failed
    }

    /// Convert to AIModel for unified provider/model selection
    func toAIModel() -> AIModel {
        AIModel(
            id: repoId,
            name: displayName,
            provider: .localMLX,
            contextWindow: contextWindow,
            modalities: modalities,
            description: "User-added model from Hugging Face. \(formatSize(sizeBytes))"
        )
    }

    private func formatSize(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
