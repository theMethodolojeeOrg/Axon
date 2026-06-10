//
//  AIProvider.swift
//  Axon
//
//  AI providers and models
//

import Foundation

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
    case appleFoundation = "appleFoundation"
    case localMLX = "localMLX"

    var id: String { rawValue }

    /// Map AIProvider to APIProvider for key storage and low-level service calls
    var apiProvider: APIProvider? {
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
        case .appleFoundation, .localMLX:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI (GPT)"
        case .gemini: return "Google Gemini"
        case .xai: return "xAI (Grok)"
        case .perplexity: return "Perplexity (Sonar)"
        case .deepseek: return "DeepSeek"
        case .zai: return "Z.ai (GLM)"
        case .minimax: return "MiniMax"
        case .mistral: return "Mistral AI"
        case .appleFoundation: return "Apple Intelligence"
        case .localMLX: return "On-Device (MLX)"
        }
    }

    var availableModels: [AIModel] {
        ProviderKitModelCatalogAdapter.models(for: self)
    }

    /// Whether this provider is available on the current device/OS
    var isAvailable: Bool {
        switch self {
        case .appleFoundation:
            // Apple Foundation Models require iOS 26+ / macOS 26+
            if #available(iOS 26.0, macOS 26.0, *) {
                return true
            }
            return false
        case .localMLX:
            // MLX models require physical device with Apple Silicon (Metal GPU)
            #if targetEnvironment(simulator)
            return false
            #else
            return true
            #endif
        default:
            // Cloud providers are always available (API key validation happens separately)
            return true
        }
    }

    /// Human-readable reason if provider is unavailable
    var unavailableReason: String? {
        switch self {
        case .appleFoundation:
            if #available(iOS 26.0, macOS 26.0, *) {
                return nil
            }
            return "Requires iOS 26.0+ or macOS 26.0+"
        case .localMLX:
            #if targetEnvironment(simulator)
            return "Requires physical device (MLX uses Metal GPU)"
            #else
            return nil
            #endif
        default:
            return nil
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
