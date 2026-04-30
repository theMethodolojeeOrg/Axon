//
//  APIKeyInputSheet.swift
//  Axon
//
//  Sheet for entering API keys for built-in providers
//

import SwiftUI

struct APIKeyInputSheet: View {
    let provider: APIProvider
    @Binding var keyValue: String
    var isSaving: Bool = false
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppSurfaces.color(.contentBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter your \(provider.displayName) API key")
                                .font(AppTypography.headlineSmall())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Your API key will be encrypted and stored securely.")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        // Key Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            SecureInputField(
                                placeholder: "Paste your API key",
                                text: $keyValue,
                                isDisabled: isSaving,
                                hint: "Expected format: \(provider.apiKeyPlaceholder)"
                            )
                        }

                        // Saving indicator
                        if isSaving {
                            savingIndicator
                        }

                        // Get Key Link
                        if let url = provider.infoURL {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "link")
                                    Text("Get API key from \(provider.displayName)")
                                        .font(AppTypography.bodyMedium())
                                }
                                .foregroundColor(AppColors.signalMercury)
                            }
                            .disabled(isSaving)
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(provider.displayName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(AppColors.textSecondary)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                    } else {
                        Button("Save") {
                            onSave()
                        }
                        .disabled(keyValue.isEmpty)
                        .foregroundColor(keyValue.isEmpty ? AppColors.textDisabled : AppColors.signalMercury)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var savingIndicator: some View {
        let syncProvider = SettingsViewModel.shared.settings.deviceModeConfig.cloudSyncProvider
        let destination: String = {
            switch syncProvider {
            case .iCloud: return "iCloud Keychain"
            case .firestore: return "Custom Server"
            case .none: return "device"
            }
        }()

        return HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
            Text("Saving key to \(destination)...")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppColors.signalMercury.opacity(0.1))
        .cornerRadius(8)
    }
}
