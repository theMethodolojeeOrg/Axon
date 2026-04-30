//
//  ModelTuningView.swift
//  Axon
//
//  Per-model generation parameter overrides.
//  Organized by provider with expandable accordions for each model.
//

import SwiftUI

// MARK: - Model Tuning View

struct ModelTuningView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var searchQuery = ""
    @State private var expandedProviders: Set<String> = []
    @State private var showingModelDetail: ModelOverrideContext?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                ModelTuningHeader()

                // Search
                ModelTuningSearchBar(text: $searchQuery, placeholder: "Search models...")

                // Stats
                ModelTuningStatsBanner(
                    totalModels: allModels.count,
                    overriddenCount: viewModel.settings.modelOverrides.values.filter { $0.enabled }.count
                )

                // Provider accordions
                providerAccordions

                // Global defaults link
                ModelTuningGlobalDefaultsLink(viewModel: viewModel)
            }
            .padding()
        }
        .background(AppSurfaces.color(.contentBackground))
        .navigationTitle("Model Tuning")
        .sheet(item: $showingModelDetail) { context in
            ModelOverrideSheet(
                context: context,
                viewModel: viewModel
            )
            #if os(iOS)
            // Encourage a usable default size on iPhone/iPad.
            .presentationDetents([.medium, .large])
            #endif
        }
    }

    // MARK: - Provider Accordions

    private var providerAccordions: some View {
        VStack(spacing: 12) {
            ForEach(filteredProviders, id: \.self) { provider in
                ModelTuningProviderAccordion(
                    provider: provider,
                    models: modelsForProvider(provider),
                    overrides: viewModel.settings.modelOverrides,
                    isExpanded: expandedProviders.contains(provider.rawValue),
                    onToggleExpand: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedProviders.contains(provider.rawValue) {
                                expandedProviders.remove(provider.rawValue)
                            } else {
                                expandedProviders.insert(provider.rawValue)
                            }
                        }
                    },
                    onSelectModel: { model in
                        showingModelDetail = ModelOverrideContext(
                            modelId: model.id,
                            modelName: model.name,
                            provider: provider
                        )
                    },
                    onToggleOverride: { modelId, enabled in
                        toggleOverride(modelId: modelId, enabled: enabled)
                    }
                )
            }
        }
    }

    // MARK: - Data

    private var allModels: [AIModel] {
        // Use registry for all chat models
        let registry = UnifiedModelRegistry.shared
        return AIProvider.allCases.flatMap { provider in
            let registryModels = registry.chatModels(for: provider)
            return registryModels.isEmpty ? provider.availableModels : registryModels
        }
    }

    private var filteredProviders: [AIProvider] {
        let providers = AIProvider.allCases.filter { provider in
            !modelsForProvider(provider).isEmpty
        }

        if searchQuery.isEmpty {
            return providers
        }

        return providers.filter { provider in
            !modelsForProvider(provider).isEmpty
        }
    }

    private func modelsForProvider(_ provider: AIProvider) -> [AIModel] {
        // Use registry first, fall back to hardcoded enum
        let registryModels = UnifiedModelRegistry.shared.chatModels(for: provider)
        let models = registryModels.isEmpty ? provider.availableModels : registryModels

        if searchQuery.isEmpty {
            return models
        }

        let query = searchQuery.lowercased()
        return models.filter { model in
            model.name.lowercased().contains(query) ||
            model.id.lowercased().contains(query)
        }
    }

    private func toggleOverride(modelId: String, enabled: Bool) {
        if enabled {
            // Create override if it doesn't exist
            if viewModel.settings.modelOverrides[modelId] == nil {
                viewModel.settings.modelOverrides[modelId] = ModelOverride(modelId: modelId)
            }
            viewModel.settings.modelOverrides[modelId]?.enabled = true
        } else {
            viewModel.settings.modelOverrides[modelId]?.enabled = false
        }
    }
}

// MARK: - Model Override Context

struct ModelOverrideContext: Identifiable {
    let modelId: String
    let modelName: String
    let provider: AIProvider

    var id: String { modelId }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ModelTuningView(viewModel: SettingsViewModel.shared)
    }
}
