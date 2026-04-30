//
//  CustomProvidersSettingsView.swift
//  Axon
//
//  Custom provider configuration view for OpenAI-compatible endpoints
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CustomProvidersSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingProviderSheet = false
    @State private var editingProvider: CustomProviderConfig?
    @State private var showingDeleteAlert = false
    @State private var providerToDelete: CustomProviderConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - Info Banner

            InfoBanner(
                icon: "info.circle.fill",
                title: "Custom Providers",
                message: "Add OpenAI-compatible endpoints like Deepseek, local LLMs, or other providers. Configure API keys in the API Keys tab after adding a provider."
            )

            // MARK: - Provider List

            GeneralSettingsSection(title: "Configured Providers") {
                if viewModel.settings.customProviders.isEmpty {
                    EmptyStateView(
                        icon: "server.rack",
                        title: "No Custom Providers",
                        message: "Add a custom provider to get started"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(viewModel.settings.customProviders.enumerated()), id: \.element.id) { index, provider in
                            CustomProviderCard(
                                provider: provider,
                                providerIndex: index + 1,
                                onEdit: {
                                    editingProvider = provider
                                    showingProviderSheet = true
                                },
                                onDelete: {
                                    providerToDelete = provider
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
            }

            // MARK: - Add Provider Button

            Button(action: {
                editingProvider = nil
                showingProviderSheet = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)

                    Text("Add Custom Provider")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppSurfaces.color(.cardBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.signalMercury.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showingProviderSheet) {
            CustomProviderEditSheet(
                viewModel: viewModel,
                existingProvider: editingProvider,
                onDismiss: {
                    showingProviderSheet = false
                    editingProvider = nil
                }
            )
        }
        .alert("Delete Provider", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let provider = providerToDelete {
                    Task {
                        await viewModel.deleteCustomProvider(id: provider.id)
                    }
                }
            }
        } message: {
            if let provider = providerToDelete {
                Text("Are you sure you want to delete '\(provider.providerName)'? This action cannot be undone and will also remove the associated API key.")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CustomProvidersSettingsView(viewModel: SettingsViewModel())
        .background(AppSurfaces.color(.contentBackground))
}
