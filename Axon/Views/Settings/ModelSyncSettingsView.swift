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

    @State private var showingDraftPreview = false
    @State private var showingResetConfirmation = false
    @State private var selectedProviderToSync: AIProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Catalog")
                        .font(AppTypography.titleLarge())
                        .foregroundColor(AppColors.textPrimary)

                    Text("Manage AI model definitions and pricing")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                // Status badge
                configStatusBadge
            }

            Divider()
                .background(AppColors.divider)

            // Current Configuration
            currentConfigSection

            // Draft Section (if available)
            if configService.hasPendingDraft {
                draftSection
            }

            // Sync Section
            syncSection

            // Provider Details
            providerDetailsSection

            // Advanced Actions
            advancedSection

            Spacer()
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var configStatusBadge: some View {
        if configService.isSyncing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Syncing...")
                    .font(AppTypography.labelSmall())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.accentWarning.opacity(0.2))
            .cornerRadius(8)
        } else if configService.hasPendingDraft {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.clock")
                Text("Draft Available")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.accentWarning)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.accentWarning.opacity(0.2))
            .cornerRadius(8)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("Up to Date")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.accentSuccess)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.accentSuccess.opacity(0.2))
            .cornerRadius(8)
        }
    }

    // MARK: - Current Config Section

    private var currentConfigSection: some View {
        SettingsSection(title: "Active Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                if let catalog = configService.activeCatalog {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version \(catalog.version)")
                                .font(AppTypography.titleSmall())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Updated \(catalog.lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(catalog.providers.count) Providers")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)

                            let totalModels = catalog.providers.reduce(0) { $0 + $1.models.count }
                            Text("\(totalModels) Models")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .padding()
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(12)
                } else {
                    Text("No configuration loaded")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)
                        .padding()
                }

                if let lastSync = configService.lastSyncDate {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                        Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Draft Section

    private var draftSection: some View {
        SettingsSection(title: "Pending Draft") {
            VStack(alignment: .leading, spacing: 12) {
                if let draft = configService.draftCatalog {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version \(draft.version)")
                                .font(AppTypography.titleSmall())
                                .foregroundColor(AppColors.textPrimary)

                            let totalModels = draft.providers.reduce(0) { $0 + $1.models.count }
                            Text("\(totalModels) models from \(draft.providers.count) providers")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        // Preview button
                        Button {
                            showingDraftPreview = true
                        } label: {
                            Image(systemName: "eye")
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(AppColors.signalMercury)
                    }
                    .padding()
                    .background(AppColors.accentWarning.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.accentWarning.opacity(0.3), lineWidth: 1)
                    )

                    // Validation issues
                    if !configService.draftIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppColors.accentWarning)
                                Text("Validation Issues")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.accentWarning)
                            }

                            ForEach(configService.draftIssues.prefix(3), id: \.description) { issue in
                                Text("• \(issue.description)")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            if configService.draftIssues.count > 3 {
                                Text("... and \(configService.draftIssues.count - 3) more")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                        .padding()
                        .background(AppColors.accentWarning.opacity(0.05))
                        .cornerRadius(8)
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            activateDraft()
                        } label: {
                            Label("Activate Draft", systemImage: "checkmark.circle")
                                .font(AppTypography.bodyMedium())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accentSuccess)

                        Button {
                            discardDraft()
                        } label: {
                            Label("Discard", systemImage: "xmark.circle")
                                .font(AppTypography.bodyMedium())
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.accentError)
                    }
                }
            }
        }
        .sheet(isPresented: $showingDraftPreview) {
            DraftPreviewSheet(catalog: configService.draftCatalog)
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        SettingsSection(title: "Sync Models") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use Perplexity to fetch the latest model information and pricing from provider documentation.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                // Sync progress
                if case .syncing(let provider, let progress) = syncService.syncProgress {
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
                    .padding()
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(8)
                }

                // Error display
                if let error = syncService.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.accentError)
                        Text(error.localizedDescription)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.accentError)
                    }
                    .padding()
                    .background(AppColors.accentError.opacity(0.1))
                    .cornerRadius(8)
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

    // MARK: - Provider Details Section

    private var providerDetailsSection: some View {
        SettingsSection(title: "Provider Details") {
            if let catalog = configService.activeCatalog {
                VStack(spacing: 8) {
                    ForEach(catalog.providers) { provider in
                        ProviderSummaryRow(provider: provider)
                    }
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        SettingsSection(title: "Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(AppTypography.bodyMedium())
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accentError)

                Text("This will restore the bundled model catalog that shipped with the app.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .alert("Reset to Defaults?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will replace your current model configuration with the bundled defaults. Your current configuration will be backed up.")
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

// MARK: - Provider Summary Row

struct ProviderSummaryRow: View {
    let provider: ProviderConfig

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(AppTypography.titleSmall())
                            .foregroundColor(AppColors.textPrimary)

                        Text("\(provider.models.count) models")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateTertiary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(provider.models) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textPrimary)

                                HStack(spacing: 8) {
                                    Text(model.category.rawValue.capitalized)
                                        .font(AppTypography.labelSmall())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(categoryColor(model.category).opacity(0.2))
                                        .foregroundColor(categoryColor(model.category))
                                        .cornerRadius(4)

                                    Text("\(model.contextWindow / 1000)K context")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(model.pricing.inputPerMillion, specifier: "%.2f")/M in")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                Text("$\(model.pricing.outputPerMillion, specifier: "%.2f")/M out")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 8)
                .background(AppColors.substrateSecondary)
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.divider, lineWidth: 1)
        )
    }

    private func categoryColor(_ category: ModelCategory) -> Color {
        switch category {
        case .frontier: return AppColors.signalMercury
        case .reasoning: return AppColors.accentWarning
        case .fast: return AppColors.accentSuccess
        case .legacy: return AppColors.textTertiary
        }
    }
}

// MARK: - Draft Preview Sheet

struct DraftPreviewSheet: View {
    let catalog: ModelCatalog?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let catalog = catalog {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Version \(catalog.version)")
                                .font(AppTypography.titleMedium())
                            Spacer()
                            Text(catalog.lastUpdated.formatted())
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding()

                        ForEach(catalog.providers) { provider in
                            ProviderSummaryRow(provider: provider)
                        }
                    }
                    .padding()
                } else {
                    Text("No draft available")
                        .foregroundColor(AppColors.textSecondary)
                        .padding()
                }
            }
            .background(AppColors.substratePrimary)
            .navigationTitle("Draft Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ModelSyncSettingsView(viewModel: SettingsViewModel.shared)
}
