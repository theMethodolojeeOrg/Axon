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
        switch self {
        case .anthropic:
            return [
                AIModel(
                    id: "claude-opus-4-6",
                    name: "Claude Opus 4.6",
                    provider: .anthropic,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Frontier Claude model with 1M token context, adaptive reasoning effort, and the longest task-completion horizon for complex agents and coding"
                ),

                AIModel(
                    id: "claude-sonnet-4-6",
                    name: "Claude Sonnet 4.6",
                    provider: .anthropic,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Most capable Sonnet model with upgraded coding, computer use, long-context reasoning, and agent planning for high-volume workloads"
                ),
                AIModel(
                    id: "claude-opus-4-5-20251022",
                    name: "Claude Opus 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Most capable Claude model for deep reasoning, agents, and long-horizon coding"
                ),
                AIModel(
                    id: "claude-sonnet-4-5-20250929",
                    name: "Claude Sonnet 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Best coding model. Strongest for complex agents and computer use"
                ),
                AIModel(
                    id: "claude-haiku-4-5-20251001",
                    name: "Claude Haiku 4.5",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Fast hybrid reasoning model. Great for coding and quick tasks"
                ),
                AIModel(
                    id: "claude-opus-4-1-20250805",
                    name: "Claude Opus 4.1",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Most powerful for long-running tasks and deep reasoning"
                ),
                AIModel(
                    id: "claude-sonnet-4-20250514",
                    name: "Claude Sonnet 4",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Previous generation Sonnet model"
                ),
                AIModel(
                    id: "claude-opus-4-20250514",
                    name: "Claude Opus 4",
                    provider: .anthropic,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Previous generation Opus model"
                )
            ]
        case .openai:
            return [
                AIModel(
                    id: "gpt-5.4",
                    name: "GPT-5.4",
                    provider: .openai,
                    contextWindow: 1_050_000,
                    modalities: ["text", "image"],
                    description: "Frontier model with 1M token context and advanced reasoning for complex professional and coding workloads"
                ),

                AIModel(
                    id: "gpt-5.4-mini",
                    name: "GPT-5.4 mini",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Strongest mini variant of GPT-5.4 for high-volume coding, computer use, and subagents with lower cost and latency"
                ),

                AIModel(
                    id: "gpt-5.3-codex",
                    name: "GPT-5.3 Codex",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text"],
                    description: "Agentic coding model with tool-use support and higher reasoning effort for long-horizon development workflows"
                ),
                AIModel(
                    id: "gpt-5.2",
                    name: "GPT-5.2",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Latest frontier model with stronger reasoning and long-context performance"
                ),
                AIModel(
                    id: "gpt-5.1",
                    name: "GPT-5.1",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Upgraded GPT-5 with improved conversational abilities and customization"
                ),
                AIModel(
                    id: "gpt-5.1-chat-latest",
                    name: "GPT-5.1 Chat Latest",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Latest conversational variant with multimodal support"
                ),
                AIModel(
                    id: "gpt-5-2025-08-07",
                    name: "GPT-5",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Flagship model for coding, reasoning, and agentic tasks"
                ),
                AIModel(
                    id: "gpt-5-mini-2025-08-07",
                    name: "GPT-5 Mini",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Fast and cost-efficient with strong performance"
                ),
                AIModel(
                    id: "gpt-5-nano-2025-08-07",
                    name: "GPT-5 Nano",
                    provider: .openai,
                    contextWindow: 400_000,
                    modalities: ["text", "image"],
                    description: "Smallest, fastest, cheapest. Great for classification and extraction"
                ),
                AIModel(
                    id: "o3",
                    name: "o3",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Most powerful reasoning model for coding, math, science, and vision"
                ),
                AIModel(
                    id: "o4-mini",
                    name: "o4-mini",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Fast, cost-efficient reasoning model with multimodal support"
                ),
                AIModel(
                    id: "o3-mini",
                    name: "o3-mini",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Specialized reasoning for STEM tasks with configurable effort levels"
                ),
                AIModel(
                    id: "gpt-4.1",
                    name: "GPT-4.1",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Enhanced coding and instruction following with 1M context"
                ),
                AIModel(
                    id: "gpt-4.1-mini",
                    name: "GPT-4.1 Mini",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Mid-tier with 1M context. Fast and cost-effective"
                ),
                AIModel(
                    id: "gpt-4.1-nano",
                    name: "GPT-4.1 Nano",
                    provider: .openai,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image"],
                    description: "Lightest 4.1 variant with 1M context for simple tasks"
                ),
                AIModel(
                    id: "o1",
                    name: "o1",
                    provider: .openai,
                    contextWindow: 200_000,
                    modalities: ["text", "image"],
                    description: "Advanced reasoning with vision API and function calling"
                ),
                AIModel(
                    id: "o1-mini",
                    name: "o1-mini",
                    provider: .openai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Faster reasoning focused on coding, math, and science"
                ),
                AIModel(
                    id: "gpt-4o",
                    name: "GPT-4o",
                    provider: .openai,
                    contextWindow: 128_000,
                    modalities: ["text", "image", "audio"],
                    description: "Multimodal flagship with text, audio, image, and video"
                ),
                AIModel(
                    id: "gpt-4o-mini",
                    name: "GPT-4o Mini",
                    provider: .openai,
                    contextWindow: 128_000,
                    modalities: ["text", "image", "audio"],
                    description: "Cost-efficient multimodal model with vision support"
                )
            ]
        case .gemini:
            return [
                AIModel(
                    id: "gemini-3.1-pro-preview",
                    name: "Gemini 3.1 Pro Preview",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image", "video", "audio", "pdf"],
                    description: "Most powerful agentic and coding model with advanced reasoning"
                ),
                AIModel(
                    id: "gemini-3-flash-preview",
                    name: "Gemini 3 Flash Preview",
                    provider: .gemini,
                    contextWindow: 1_048_576,
                    modalities: ["text", "image", "video", "audio", "pdf"],
                    description: "Most intelligent model built for speed, combining frontier intelligence with superior search and grounding"
                ),
                AIModel(
                    id: "gemini-3.1-flash-lite-preview",
                    name: "Gemini 3.1 Flash Lite Preview",
                    provider: .gemini,
                    contextWindow: 200_000,
                    modalities: ["text", "image", "video", "audio", "pdf"],
                    description: "Most intelligent model built for speed, combining frontier intelligence with superior search and grounding"
                ),
                AIModel(
                    id: "gemini-2.5-flash-lite-preview-06-17",
                    name: "Gemini 2.5 Flash Lite Preview",
                    provider: .gemini,
                    contextWindow: 1_048_576,
                    modalities: ["text", "image", "video", "audio"],
                    description: "Ultra-low latency, cost-efficient lightweight reasoning model"
                ),
                AIModel(
                    id: "gemini-2.5-pro",
                    name: "Gemini 2.5 Pro",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image", "video", "audio", "pdf"],
                    description: "Most capable Gemini model"
                ),
                AIModel(
                    id: "gemini-2.5-flash",
                    name: "Gemini 2.5 Flash",
                    provider: .gemini,
                    contextWindow: 1_000_000,
                    modalities: ["text", "image", "video", "audio"],
                    description: "Fast, efficient model"
                )
            ]
        case .xai:
            return [
                AIModel(
                    id: "grok-4-fast-reasoning",
                    name: "Grok 4 Fast Reasoning",
                    provider: .xai,
                    contextWindow: 2_000_000,
                    modalities: ["text", "image"],
                    description: "Cost-efficient reasoning model with 2M context. 98% cheaper than previous models"
                ),
                AIModel(
                    id: "grok-4-fast-non-reasoning",
                    name: "Grok 4 Fast Non-Reasoning",
                    provider: .xai,
                    contextWindow: 2_000_000,
                    modalities: ["text", "image"],
                    description: "Ultra-fast non-reasoning model with 2M context window"
                ),
                AIModel(
                    id: "grok-code-fast-1",
                    name: "Grok Code Fast 1",
                    provider: .xai,
                    contextWindow: 256_000,
                    modalities: ["text"],
                    description: "Specialized coding model with high throughput for large codebases"
                ),
                AIModel(
                    id: "grok-4-0709",
                    name: "Grok 4 (0709)",
                    provider: .xai,
                    contextWindow: 256_000,
                    modalities: ["text", "image"],
                    description: "Flagship model with advanced reasoning and function calling"
                ),
                AIModel(
                    id: "grok-3-mini",
                    name: "Grok 3 Mini",
                    provider: .xai,
                    contextWindow: 131_072,
                    modalities: ["text"],
                    description: "Lightweight, cost-efficient model for simple tasks"
                ),
                AIModel(
                    id: "grok-3",
                    name: "Grok 3",
                    provider: .xai,
                    contextWindow: 131_072,
                    modalities: ["text", "image"],
                    description: "Previous generation flagship model"
                )
            ]
        case .perplexity:
            return [
                AIModel(
                    id: "sonar-reasoning-pro",
                    name: "Sonar Reasoning Pro",
                    provider: .perplexity,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Best for complex queries. Advanced reasoning + real-time web search"
                ),
                AIModel(
                    id: "sonar-reasoning",
                    name: "Sonar Reasoning",
                    provider: .perplexity,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Lighter reasoning model with web search. Good balance of speed/intelligence"
                ),
                AIModel(
                    id: "sonar-pro",
                    name: "Sonar Pro",
                    provider: .perplexity,
                    contextWindow: 200_000,
                    modalities: ["text"],
                    description: "High-capacity standard search model (no reasoning tokens)"
                ),
                AIModel(
                    id: "sonar",
                    name: "Sonar",
                    provider: .perplexity,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Cheapest standard search model. Good for simple lookups"
                )
            ]
        case .deepseek:
            return [
                AIModel(
                    id: "deepseek-reasoner",
                    name: "DeepSeek Reasoner (R1)",
                    provider: .deepseek,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Flagship reasoning model with Chain-of-Thought. Best for math/code"
                ),
                AIModel(
                    id: "deepseek-chat",
                    name: "DeepSeek Chat (V3)",
                    provider: .deepseek,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Standard frontier model. Extremely cost-effective and fast"
                )
            ]
        case .zai:
            return [
                AIModel(
                    id: "glm-5",
                    name: "GLM-5",
                    provider: .zai,
                    contextWindow: 200_000,
                    modalities: ["text"],
                    description: "Next-generation flagship GLM with 200K context, MoE architecture, and state-of-the-art open-weight performance on coding and long-horizon agentic tasks"
                ),

                AIModel(
                    id: "glm-5-turbo",
                    name: "GLM-5 Turbo",
                    provider: .zai,
                    contextWindow: 200_000,
                    modalities: ["text"],
                    description: "Optimized GLM-5 variant for API use with lower cost and latency while retaining strong reasoning, coding, and agent capabilities"
                ),
                AIModel(
                    id: "glm-4.6",
                    name: "GLM-4.6",
                    provider: .zai,
                    contextWindow: 200_000,
                    modalities: ["text"],
                    description: "Flagship model. Best reasoning, coding, and agentic capability"
                ),
                AIModel(
                    id: "glm-4.6v",
                    name: "GLM-4.6V",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Flagship vision. Native multimodal with thinking support"
                ),
                AIModel(
                    id: "glm-4.6v-flash",
                    name: "GLM-4.6V Flash",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Fast vision. Lower latency and cost"
                ),
                AIModel(
                    id: "glm-4.5",
                    name: "GLM-4.5",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Previous flagship. Strong generalist"
                ),
                AIModel(
                    id: "glm-4.5-air",
                    name: "GLM-4.5 Air",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Balanced Air tier. Speed/performance mix"
                ),
                AIModel(
                    id: "glm-4.5v",
                    name: "GLM-4.5V",
                    provider: .zai,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Multimodal variant of GLM-4.5"
                )
            ]
        case .minimax:
            return [
                AIModel(
                    id: "MiniMax-M2",
                    name: "MiniMax M2",
                    provider: .minimax,
                    contextWindow: 1_000_000,
                    modalities: ["text"],
                    description: "Flagship agentic model. 1M context, 92% cheaper than Claude Sonnet"
                ),
                AIModel(
                    id: "MiniMax-M2-Stable",
                    name: "MiniMax M2 Stable",
                    provider: .minimax,
                    contextWindow: 1_000_000,
                    modalities: ["text"],
                    description: "Stable version with higher rate limits"
                )
            ]
        case .mistral:
            return [
                AIModel(
                    id: "mistral-large-latest",
                    name: "Mistral Large",
                    provider: .mistral,
                    contextWindow: 128_000,
                    modalities: ["text"],
                    description: "Flagship reasoning model. Top-tier performance"
                ),
                AIModel(
                    id: "pixtral-large-2411",
                    name: "Pixtral Large",
                    provider: .mistral,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Flagship vision. Multimodal version of Mistral Large"
                ),
                AIModel(
                    id: "pixtral-12b-2409",
                    name: "Pixtral 12B",
                    provider: .mistral,
                    contextWindow: 128_000,
                    modalities: ["text", "image"],
                    description: "Edge vision. Efficient multimodal model"
                ),
                AIModel(
                    id: "codestral-latest",
                    name: "Codestral",
                    provider: .mistral,
                    contextWindow: 32_000,
                    modalities: ["text"],
                    description: "Coding optimized. Best for FIM and code generation"
                )
            ]
        case .appleFoundation:
            return [
                AIModel(
                    id: "apple-foundation-default",
                    name: "Apple Intelligence",
                    provider: .appleFoundation,
                    contextWindow: 4_096,
                    modalities: ["text"],
                    description: "On-device ~3B model. Private, offline, free. Requires iOS 26+"
                )
            ]
        case .localMLX:
            // Built-in models from LocalMLXModel enum
            // User-added models are appended dynamically via SettingsViewModel
            return [
                // Default bundled model (first in list)
                AIModel(
                    id: "lmstudio-community/gemma-3-270m-it-MLX-8bit",
                    name: "Gemma3 270M",
                    provider: .localMLX,
                    contextWindow: 8_192,
                    modalities: ["text"],
                    description: "Google's ultra-compact model. Fastest option. Bundled in app - ready instantly. Private, offline, free."
                ),
                // Downloadable models
                AIModel(
                    id: "mlx-community/Qwen3-VL-2B-Instruct-4bit",
                    name: "Qwen3 VL 2B",
                    provider: .localMLX,
                    contextWindow: 8_192,
                    modalities: ["text", "vision"],
                    description: "Vision-language model. Bundled in app - ready instantly. Private, offline, free."
                ),
                AIModel(
                    id: "mlx-community/SmolLM2-1.7B-Instruct-4bit",
                    name: "SmolLM2 1.7B",
                    provider: .localMLX,
                    contextWindow: 8_192,
                    modalities: ["text"],
                    description: "HuggingFace's efficient small model. ~1GB download. Private, offline, free."
                ),
                AIModel(
                    id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
                    name: "Llama 3.2 1B",
                    provider: .localMLX,
                    contextWindow: 8_192,
                    modalities: ["text"],
                    description: "Meta's compact model. ~0.7GB download. Private, offline, free."
                ),
                AIModel(
                    id: "mlx-community/Qwen3-1.7B-4bit",
                    name: "Qwen3 1.7B",
                    provider: .localMLX,
                    contextWindow: 32_768,
                    modalities: ["text"],
                    description: "Alibaba's multilingual model. ~1GB download. Private, offline, free."
                ),
                AIModel(
                    id: "mlx-community/Phi-4-mini-instruct-4bit",
                    name: "Phi-4 Mini",
                    provider: .localMLX,
                    contextWindow: 16_384,
                    modalities: ["text"],
                    description: "Microsoft's capable small model. ~2GB download. Private, offline, free."
                )
            ]
        }
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
        // Check built-in models first
        for provider in AIProvider.allCases {
            if let model = provider.availableModels.first(where: { $0.id == modelId }) {
                return model.contextWindow
            }
        }

        // Check custom models if settings provided
        if let settings = settings {
            for customProvider in settings.customProviders {
                if let model = customProvider.models.first(where: { $0.modelCode == modelId }) {
                    return model.contextWindow
                }
            }
        }

        // Default to 128K if not found
        return 128_000
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
