//
//  APIKeysSettingsView.swift
//  Axon
//
//  API Keys configuration with secure storage
//

import SwiftUI

struct APIKeysSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedProvider: APIProvider? = nil
    @State private var selectedCustomProvider: CustomProviderConfig? = nil
    @State private var editingKeyValue = ""
    @State private var isSavingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Info banner
            SettingsInfoBanner(
                icon: "lock.shield.fill",
                text: "API keys are encrypted and stored securely in your device's Keychain."
            )

            // AI Provider Keys Section
            SettingsSection(title: "AI Provider Keys") {
                VStack(spacing: 12) {
                    ForEach(APIProvider.allCases.filter { $0 != APIProvider.elevenlabs }) { provider in
                        APIKeyRow(
                            provider: provider,
                            isConfigured: viewModel.isAPIKeyConfigured(provider),
                            onEdit: {
                                editingKeyValue = viewModel.getAPIKey(provider) ?? ""
                                selectedProvider = provider
                            },
                            onClear: {
                                Task {
                                    await viewModel.clearAPIKey(provider)
                                }
                            },
                            onGetKey: {
                                if let url = provider.infoURL {
                                    AppURLRouter.open(url)
                                }
                            }
                        )
                    }
                }
            }

            // ElevenLabs Section
            SettingsSection(title: "Text-to-Speech") {
                APIKeyRow(
                    provider: .elevenlabs,
                    isConfigured: viewModel.isAPIKeyConfigured(.elevenlabs),
                    onEdit: {
                        editingKeyValue = viewModel.getAPIKey(.elevenlabs) ?? ""
                        selectedProvider = .elevenlabs
                    },
                    onClear: {
                        Task {
                            await viewModel.clearAPIKey(.elevenlabs)
                        }
                    },
                    onGetKey: {
                        if let url = APIProvider.elevenlabs.infoURL {
                            AppURLRouter.open(url)
                        }
                    }
                )
            }

            // Custom Provider Keys Section
            if !viewModel.settings.customProviders.isEmpty {
                SettingsSection(title: "Custom Provider Keys") {
                    VStack(spacing: 12) {
                        ForEach(viewModel.settings.customProviders) { provider in
                            CustomProviderAPIKeyRow(
                                provider: provider,
                                isConfigured: viewModel.isCustomProviderConfigured(provider.id),
                                onEdit: {
                                    editingKeyValue = viewModel.getCustomProviderAPIKey(providerId: provider.id) ?? ""
                                    selectedCustomProvider = provider
                                },
                                onClear: {
                                    Task {
                                        await viewModel.clearCustomProviderAPIKey(providerId: provider.id, providerName: provider.providerName)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedProvider) { provider in
            APIKeyInputSheet(
                provider: provider,
                keyValue: $editingKeyValue,
                isSaving: isSavingKey,
                onSave: {
                    isSavingKey = true
                    Task {
                        await viewModel.saveAPIKey(editingKeyValue, for: provider)
                        isSavingKey = false
                        selectedProvider = nil
                    }
                },
                onCancel: {
                    selectedProvider = nil
                }
            )
        }
        .sheet(item: $selectedCustomProvider) { customProvider in
            CustomProviderAPIKeyInputSheet(
                provider: customProvider,
                keyValue: $editingKeyValue,
                onSave: {
                    Task {
                        await viewModel.saveCustomProviderAPIKey(editingKeyValue, providerId: customProvider.id, providerName: customProvider.providerName)
                        selectedCustomProvider = nil
                    }
                },
                onCancel: {
                    selectedCustomProvider = nil
                }
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        APIKeysSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppSurfaces.color(.contentBackground))
}
