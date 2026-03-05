//
//  LiveProviderHelpers.swift
//  Axon
//
//  Helper functions for live provider display and configuration
//

import SwiftUI

/// Helpers for live provider display names and execution modes
enum LiveProviderHelpers {
    
    /// Get display name for a given AI provider
    static func displayName(for provider: AIProvider) -> String {
        switch provider {
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .xai: return "xAI"
        case .perplexity: return "Perplexity"
        case .deepseek: return "DeepSeek"
        case .localMLX: return "MLX"
        default: return provider.displayName
        }
    }
    
    /// Get label for the currently selected live provider
    static func selectedProviderLabel(
        selectedProvider: String?,
        defaultProvider: AIProvider
    ) -> String {
        guard let provider = selectedProvider else {
            return "Default (\(displayName(for: defaultProvider)))"
        }
        switch provider {
        case "openai": return "OpenAI Realtime"
        case "gemini": return "Gemini Live"
        case "anthropic": return "Anthropic (Claude)"
        case "xai": return "xAI (Grok)"
        case "perplexity": return "Perplexity"
        case "deepseek": return "DeepSeek"
        case "mlx": return "MLX (Offline)"
        default: return provider.capitalized
        }
    }
    
    /// Get the execution mode for a selected live provider
    static func executionMode(
        for selectedProvider: String?,
        defaultProvider: AIProvider,
        defaultModelId: String?,
        settingsViewModel: SettingsViewModel
    ) -> ExecutionMode {
        guard let provider = selectedProvider else {
            // Use default provider's mode
            return LiveProviderFactory.shared.detectCapabilities(
                for: defaultProvider,
                modelId: defaultModelId ?? "gemini-2.5-flash-native-audio-preview-12-2025"
            ).executionMode
        }
        
        switch provider {
        case "openai", "gemini":
            return .cloudWebSocket
        case "anthropic", "xai", "perplexity", "deepseek":
            return .cloudHTTPStreaming
        case "mlx":
            return .onDeviceMLX
        default:
            return .cloudHTTPStreaming
        }
    }
    
    /// Get color for an execution mode badge
    static func executionModeColor(_ mode: ExecutionMode) -> Color {
        switch mode {
        case .cloudWebSocket:
            return AppColors.signalLichen
        case .cloudHTTPStreaming:
            return AppColors.signalMercury
        case .onDeviceMLX:
            return .purple
        }
    }
}

/// Execution mode badge view
struct LiveExecutionModeBadge: View {
    let mode: ExecutionMode
    
    var body: some View {
        Text(mode.displayName)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(LiveProviderHelpers.executionModeColor(mode).opacity(0.2))
            .foregroundColor(LiveProviderHelpers.executionModeColor(mode))
            .cornerRadius(4)
    }
}

#Preview {
    VStack(spacing: 8) {
        LiveExecutionModeBadge(mode: .cloudWebSocket)
        LiveExecutionModeBadge(mode: .cloudHTTPStreaming)
        LiveExecutionModeBadge(mode: .onDeviceMLX)
    }
    .padding()
}
