//
//  CustomProviderAPIKeyInputSheet.swift
//  Axon
//
//  Sheet for entering API keys for custom providers
//

import SwiftUI

struct CustomProviderAPIKeyInputSheet: View {
    let provider: CustomProviderConfig
    @Binding var keyValue: String
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
                            Text("Enter your \(provider.providerName) API key")
                                .font(AppTypography.headlineSmall())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Your API key will be encrypted and stored securely.")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        // Provider Info Card
                        HStack {
                            Image(systemName: "server.rack")
                                .foregroundColor(AppColors.signalMercury)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Endpoint")
                                    .font(AppTypography.labelSmall(.medium))
                                    .foregroundColor(AppColors.textSecondary)
                                Text(provider.apiEndpoint)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(2)
                            }
                        }
                        .padding()
                        .background(AppSurfaces.color(.cardBackground))
                        .cornerRadius(8)

                        // Key Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            SecureInputField(
                                placeholder: "Paste your API key",
                                text: $keyValue
                            )
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(provider.providerName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(keyValue.isEmpty)
                    .foregroundColor(keyValue.isEmpty ? AppColors.textDisabled : AppColors.signalMercury)
                }
            }
        }
    }
}
