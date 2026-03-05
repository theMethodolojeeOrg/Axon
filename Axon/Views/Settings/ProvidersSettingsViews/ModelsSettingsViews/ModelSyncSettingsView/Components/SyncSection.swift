//
//  SyncSection.swift
//  Axon
//
//  Section for syncing model data via Perplexity.
//

import SwiftUI

struct SyncSection: View {
    let configService: ModelConfigurationService
    let syncService: PerplexityModelSyncService
    let isPerplexityConfigured: Bool

    var body: some View {
        UnifiedSettingsSection(title: "Sync Models") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use Perplexity to fetch the latest model information and pricing from provider documentation.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                // Sync progress
                if case .syncing(let provider, let progress) = syncService.syncProgress {
                    SettingsCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(provider ?? "Syncing all providers...")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                                Spacer()
                                Text("\(Int(progress * 100))%")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                            ProgressView(value: progress)
                                .tint(AppColors.signalMercury)
                        }
                    }
                }

                // Error display
                if let error = syncService.lastError {
                    SettingsCard(padding: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.accentError)
                            Text(error.localizedDescription)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.accentError)
                        }
                    }
                }

                // Sync buttons
                HStack(spacing: 12) {
                    Button {
                        Task {
                            try? await syncService.syncAllProviders()
                        }
                    } label: {
                        Label("Sync All Providers", systemImage: "arrow.triangle.2.circlepath")
                            .font(AppTypography.bodyMedium())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.signalMercury)
                    .disabled(configService.isSyncing || !isPerplexityConfigured)

                    Menu {
                        ForEach([AIProvider.anthropic, .openai, .gemini, .xai], id: \.self) { provider in
                            Button {
                                Task {
                                    try? await syncService.syncProvider(provider)
                                }
                            } label: {
                                Label(provider.displayName, systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                    } label: {
                        Label("Sync Provider", systemImage: "chevron.down")
                            .font(AppTypography.bodyMedium())
                    }
                    .buttonStyle(.bordered)
                    .disabled(configService.isSyncing || !isPerplexityConfigured)
                }

                if !isPerplexityConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("Configure your Perplexity API key in the API Keys tab to enable sync.")
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }
}
