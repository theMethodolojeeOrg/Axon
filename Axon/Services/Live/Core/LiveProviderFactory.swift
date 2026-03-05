import Foundation
import AVFoundation

/// Factory for creating Live providers based on model and provider capabilities
@MainActor
final class LiveProviderFactory {
    static let shared = LiveProviderFactory()

    private init() {}

    // MARK: - Provider Creation

    /// Create the appropriate Live provider for a given AI provider and model
    /// - Parameters:
    ///   - provider: The AI provider (e.g., .gemini, .anthropic)
    ///   - modelId: The model identifier
    ///   - config: The session configuration
    /// - Returns: A configured LiveProviderProtocol instance
    func createProvider(
        for provider: AIProvider,
        modelId: String,
        config: LiveSessionConfig
    ) throws -> LiveProviderProtocol {
        let capabilities = detectCapabilities(for: provider, modelId: modelId)

        // If execution mode is explicitly set in config, use that
        let effectiveMode = config.executionMode ?? capabilities.executionMode

        switch effectiveMode {
        case .cloudWebSocket:
            return try createWebSocketProvider(for: provider, capabilities: capabilities)

        case .cloudHTTPStreaming:
            return StreamingHTTPLiveProvider(
                provider: provider,
                capabilities: capabilities
            )

        case .onDeviceMLX:
            return OnDeviceMLXProvider(capabilities: capabilities)
        }
    }

    /// Create a WebSocket-based provider (Gemini Live or OpenAI Realtime)
    private func createWebSocketProvider(
        for provider: AIProvider,
        capabilities: LiveProviderCapabilities
    ) throws -> LiveProviderProtocol {
        switch provider {
        case .gemini:
            return GeminiLiveProvider()
        case .openai:
            return OpenAILiveProvider()
        default:
            throw LiveProviderError.providerNotSupported(
                "\(provider.displayName) does not support real-time WebSocket mode"
            )
        }
    }

    // MARK: - Capability Detection

    /// Detect the capabilities for a given provider and model
    /// - Parameters:
    ///   - provider: The AI provider
    ///   - modelId: The model identifier
    /// - Returns: The detected capabilities
    func detectCapabilities(
        for provider: AIProvider,
        modelId: String
    ) -> LiveProviderCapabilities {
        switch provider {
        case .gemini:
            return detectGeminiCapabilities(modelId: modelId)

        case .openai:
            return detectOpenAICapabilities(modelId: modelId)

        case .localMLX:
            return .onDeviceMLX

        case .anthropic, .xai, .perplexity, .deepseek, .zai, .minimax, .mistral:
            // These providers use HTTP streaming with STT/TTS
            return .httpStreaming

        case .appleFoundation:
            // Apple Foundation models could potentially run on-device
            return .onDeviceMLX
        }
    }

    /// Detect capabilities for Gemini models
    private func detectGeminiCapabilities(modelId: String) -> LiveProviderCapabilities {
        // Gemini Live models contain "native-audio" or "live" in their ID
        let isLiveModel = modelId.lowercased().contains("native-audio") ||
                          modelId.lowercased().contains("live") ||
                          modelId.lowercased().contains("realtime")

        if isLiveModel {
            return .geminiLive
        } else {
            // Standard Gemini models use HTTP streaming
            return .httpStreaming
        }
    }

    /// Detect capabilities for OpenAI models
    private func detectOpenAICapabilities(modelId: String) -> LiveProviderCapabilities {
        // OpenAI Realtime models contain "realtime" in their ID
        let isRealtimeModel = modelId.lowercased().contains("realtime")

        if isRealtimeModel {
            return .openAIRealtime
        } else {
            // Standard OpenAI models (GPT-4, GPT-4o, etc.) use HTTP streaming
            return .httpStreaming
        }
    }

    // MARK: - Provider Support Checks

    /// Check if a provider supports Live mode at all
    func supportsLiveMode(provider: AIProvider) -> Bool {
        switch provider {
        case .appleFoundation:
            // Apple Foundation models may not be ready for Live mode yet
            return false
        default:
            return true
        }
    }

    /// Check if a provider supports native real-time (WebSocket) mode
    func supportsNativeRealtime(provider: AIProvider, modelId: String) -> Bool {
        let capabilities = detectCapabilities(for: provider, modelId: modelId)
        return capabilities.executionMode == .cloudWebSocket
    }

    /// Get the recommended execution mode for a provider
    func recommendedExecutionMode(
        for provider: AIProvider,
        modelId: String
    ) -> ExecutionMode {
        let capabilities = detectCapabilities(for: provider, modelId: modelId)
        return capabilities.executionMode
    }

    // MARK: - Available Providers

    /// Get all providers that support Live mode
    var liveEnabledProviders: [AIProvider] {
        AIProvider.allCases.filter { supportsLiveMode(provider: $0) }
    }

    /// Get providers that support native real-time (lowest latency)
    var nativeRealtimeProviders: [AIProvider] {
        [.gemini, .openai]
    }

    /// Get providers that require HTTP streaming fallback
    var httpStreamingProviders: [AIProvider] {
        [.anthropic, .xai, .perplexity, .deepseek, .zai, .minimax, .mistral]
    }

    /// Get providers that run on-device
    var onDeviceProviders: [AIProvider] {
        [.localMLX]
    }
}

// MARK: - Provider Type Extension

extension AIProvider {
    /// Check if this provider supports native real-time Live mode
    var supportsNativeRealtimeLive: Bool {
        switch self {
        case .gemini, .openai:
            return true
        default:
            return false
        }
    }

    /// Check if this provider requires STT/TTS for Live mode
    var requiresSTTTTSForLive: Bool {
        switch self {
        case .gemini, .openai:
            return false // These have native audio
        case .localMLX:
            return true // On-device needs STT/TTS
        default:
            return true // HTTP streaming providers need STT/TTS
        }
    }

    /// Get the Live mode execution type for this provider
    func liveExecutionMode(modelId: String) -> ExecutionMode {
        LiveProviderFactory.shared.detectCapabilities(for: self, modelId: modelId).executionMode
    }
}
