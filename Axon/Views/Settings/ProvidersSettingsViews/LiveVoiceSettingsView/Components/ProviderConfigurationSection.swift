//
//  ProviderConfigurationSection.swift
//  Axon
//
//  Cloud provider configuration for Live Voice mode
//

import SwiftUI

/// Section for selecting cloud provider and model
struct ProviderConfigurationSection: View {
    @Binding var defaultProvider: AIProvider
    @Binding var defaultModelId: String

    /// Providers that support real-time voice conversations
    private var liveCapableProviders: [AIProvider] {
        [.openai, .anthropic, .gemini]
    }

    var body: some View {
        Section {
            Picker("Provider", selection: $defaultProvider) {
                ForEach(liveCapableProviders, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            Picker("Model", selection: $defaultModelId) {
                ForEach(availableModels(for: defaultProvider), id: \.self) { modelId in
                    Text(modelDisplayName(modelId)).tag(modelId)
                }
            }
        } header: {
            Text("Provider Configuration")
        } footer: {
            Text("Select the cloud provider and model for real-time voice conversations.")
        }
    }

    /// Get available models for a provider from registry, with fallback to hardcoded list
    private func availableModels(for provider: AIProvider) -> [String] {
        // Try registry first - get only models that support live audio
        let liveModels = UnifiedModelRegistry.shared.liveAudioModels(for: provider)

        if !liveModels.isEmpty {
            return liveModels.map { $0.id }
        }

        // Fallback to hardcoded list for backwards compatibility
        // Only include models known to support real-time audio
        switch provider {
        case .openai:
            return ["gpt-4o-realtime-preview", "gpt-4o-mini-realtime-preview"]
        case .anthropic:
            // Anthropic doesn't have real-time audio models yet
            return []
        case .gemini:
            return ["gemini-2.5-flash-native-audio-preview-12-2025"]
        default:
            return []
        }
    }

    /// Get display name for a model ID from registry
    private func modelDisplayName(_ modelId: String) -> String {
        if let model = UnifiedModelRegistry.shared.model(for: modelId) {
            return model.name
        }
        // Fallback to showing the raw ID
        return modelId
    }
}
