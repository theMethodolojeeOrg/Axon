//
//  DraftSection.swift
//  Axon
//
//  Section for managing pending draft configurations.
//

import SwiftUI

struct DraftSection: View {
    let configService: ModelConfigurationService
    let onActivate: () -> Void
    let onDiscard: () -> Void

    @State private var showingDraftPreview = false

    var body: some View {
        UnifiedSettingsSection(title: "Pending Draft") {
            VStack(alignment: .leading, spacing: 12) {
                if let draft = configService.draftCatalog {
                    SettingsCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version \(draft.version)")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                let totalModels = draft.providers.reduce(0) { $0 + $1.models.count }
                                Text("\(totalModels) models from \(draft.providers.count) providers")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()

                            Button {
                                showingDraftPreview = true
                            } label: {
                                Image(systemName: "eye")
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(AppColors.signalMercury)
                        }
                    }

                    // Validation issues
                    if !configService.draftIssues.isEmpty {
                        SettingsCard(padding: 12) {
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
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: onActivate) {
                            Label("Activate Draft", systemImage: "checkmark.circle")
                                .font(AppTypography.bodyMedium())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accentSuccess)

                        Button(action: onDiscard) {
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
}
