//
//  ModelSyncSettingsView.swift
//  Axon
//
//  Settings view for managing AI model configurations with Perplexity sync
//

import SwiftUI

struct ModelSyncSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var configService = ModelConfigurationService.shared
    @StateObject private var syncService = PerplexityModelSyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ModelSyncHeaderSection(
                configService: configService,
                syncService: syncService
            )

            CurrentConfigSection(configService: configService)

            if configService.hasPendingDraft {
                DraftSection(
                    configService: configService,
                    onActivate: activateDraft,
                    onDiscard: discardDraft
                )
            }

            SyncSection(
                configService: configService,
                syncService: syncService,
                isPerplexityConfigured: isPerplexityConfigured
            )

            ProviderDetailsSection(configService: configService)

            AdvancedSection(onReset: resetToDefaults)
        }
    }

    // MARK: - Helpers

    private var isPerplexityConfigured: Bool {
        APIKeysStorage.shared.isConfigured(.perplexity)
    }

    private func activateDraft() {
        do {
            try configService.activateDraft()
            viewModel.successMessage = "Draft configuration activated"
        } catch {
            viewModel.error = error.localizedDescription
        }
    }

    private func discardDraft() {
        configService.discardDraft()
        viewModel.successMessage = "Draft discarded"
    }

    private func resetToDefaults() {
        do {
            try configService.resetToDefaults()
            viewModel.successMessage = "Reset to bundled defaults"
        } catch {
            viewModel.error = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    ModelSyncSettingsView(viewModel: SettingsViewModel.shared)
}
