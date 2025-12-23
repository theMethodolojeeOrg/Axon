//
//  ProvidersSettingsView.swift
//  Axon
//
//  Category view for provider-related settings: API Keys, Models, and Custom Providers
//

import SwiftUI

struct ProvidersSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var configService = ModelConfigurationService.shared

    // MARK: - Dynamic Subtitles

    private var apiKeysSubtitle: String {
        let configuredCount = APIProvider.allCases.filter { viewModel.isAPIKeyConfigured($0) }.count
        let total = APIProvider.allCases.count
        if configuredCount == 0 {
            return "No keys configured"
        } else if configuredCount == total {
            return "All \(total) providers configured"
        } else {
            return "\(configuredCount) of \(total) configured"
        }
    }

    private var modelsSubtitle: String {
        if let catalog = configService.activeCatalog {
            let modelCount = catalog.providers.reduce(0) { $0 + $1.models.count }
            return "\(modelCount) models available"
        }
        return "Manage model definitions"
    }

    private var customProvidersSubtitle: String {
        let count = viewModel.settings.customProviders.count
        if count == 0 {
            return "No custom providers"
        } else if count == 1 {
            return "1 custom provider"
        } else {
            return "\(count) custom providers"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // API Keys
            NavigationLink {
                SettingsSubviewContainer {
                    APIKeysSettingsView(viewModel: viewModel)
                }
            } label: {
                SettingsCategoryRow(
                    icon: "key.fill",
                    iconColor: AppColors.signalMercury,
                    title: "API Keys",
                    subtitle: apiKeysSubtitle
                )
            }
            .buttonStyle(.plain)

            // Models
            NavigationLink {
                SettingsSubviewContainer {
                    ModelSyncSettingsView(viewModel: viewModel)
                }
            } label: {
                SettingsCategoryRow(
                    icon: "cpu",
                    iconColor: AppColors.signalLichen,
                    title: "Models",
                    subtitle: modelsSubtitle
                )
            }
            .buttonStyle(.plain)

            // Custom Providers
            NavigationLink {
                SettingsSubviewContainer {
                    CustomProvidersSettingsView(viewModel: viewModel)
                }
            } label: {
                SettingsCategoryRow(
                    icon: "slider.horizontal.3",
                    iconColor: AppColors.signalCopper,
                    title: "Custom Providers",
                    subtitle: customProvidersSubtitle
                )
            }
            .buttonStyle(.plain)

            // Realtime Voice
            NavigationLink {
                SettingsSubviewContainer {
                    LiveVoiceSettingsView(viewModel: viewModel)
                }
            } label: {
                SettingsCategoryRow(
                    icon: "waveform.circle.fill",
                    iconColor: AppColors.signalMercury,
                    title: "Realtime Voice",
                    subtitle: "Configure live session providers and voices"
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Providers")
    }
}

#Preview {
    NavigationStack {
        ProvidersSettingsView(viewModel: SettingsViewModel.shared)
    }
}
