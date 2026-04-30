//
//  GeneralSettingsView.swift
//  Axon
//
//  General settings for theme, AI provider, and model selection
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @ObservedObject var temporalService = TemporalContextService.shared
    @Environment(\.colorScheme) var systemColorScheme

    @State private var showingNegotiationSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - Theme Section

            GeneralSettingsSection(title: "Theme") {
                VStack(spacing: 12) {
                    ForEach(Theme.allCases) { theme in
                        SettingsOptionRow(
                            title: theme.displayName,
                            icon: themeIcon(theme),
                            isSelected: viewModel.settings.theme == theme
                        ) {
                            Task {
                                await viewModel.updateSetting(\.theme, theme)
                            }
                        }
                    }

                    if viewModel.settings.theme == .auto {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(AppColors.textTertiary)
                            Text("Following system: \(systemColorScheme == .dark ? "Dark" : "Light")")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding()
                        .background(AppSurfaces.color(.cardBackground))
                        .cornerRadius(8)
                    }
                }
            }

            // MARK: - AI Provider Section

            ProviderSelectionSection(
                viewModel: viewModel,
                showingNegotiationSheet: $showingNegotiationSheet
            )

            // MARK: - Model Selection

            ModelSelectionSection(viewModel: viewModel)

            // MARK: - Display Options

            GeneralSettingsSection(title: "Display") {
                VStack(spacing: 12) {
                    SettingsToggleRow(
                        title: "Show Artifacts by Default",
                        icon: "doc.text.fill",
                        isOn: Binding(
                            get: { viewModel.settings.showArtifactsByDefault },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.showArtifactsByDefault, newValue)
                                }
                            }
                        )
                    )

                    SettingsToggleRow(
                        title: "Enable Keyboard Shortcuts",
                        icon: "command",
                        isOn: Binding(
                            get: { viewModel.settings.enableKeyboardShortcuts },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.enableKeyboardShortcuts, newValue)
                                }
                            }
                        )
                    )
                }
            }

            // MARK: - Temporal Awareness

            GeneralSettingsSection(title: "Temporal Awareness") {
                VStack(spacing: 12) {
                    // Mode selector (Sync / Drift)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mode")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)

                        HStack(spacing: 8) {
                            ForEach(TemporalMode.allCases) { mode in
                                TemporalModeButton(
                                    mode: mode,
                                    isSelected: viewModel.settings.temporalSettings.mode == mode
                                ) {
                                    Task {
                                        await viewModel.updateSetting(\.temporalSettings.mode, mode)
                                        // Also update the service
                                        if mode == .sync {
                                            TemporalContextService.shared.enableSync()
                                        } else {
                                            TemporalContextService.shared.enableDrift()
                                        }
                                    }
                                }
                            }
                        }

                        Text(viewModel.settings.temporalSettings.mode.description)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppSurfaces.color(.cardBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
                            )
                    )

                    // Turn count display (live from Core Data)
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lifetime Turns")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text("\(temporalService.lifetimeTurnCount) turns together")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppSurfaces.color(.cardBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
                            )
                    )

                    // Show status bar toggle
                    SettingsToggleRow(
                        title: "Show Status Bar",
                        icon: "chart.bar.fill",
                        isOn: Binding(
                            get: { viewModel.settings.temporalSettings.showStatusBar },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.temporalSettings.showStatusBar, newValue)
                                }
                            }
                        )
                    )

                    // Philosophy note
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(AppColors.signalSaturn.opacity(0.7))
                        Text("Temporal symmetry: Provide Axon with temporal grounding and recieve turn-based temporal grounding in return.")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppColors.signalSaturn.opacity(0.1))
                    )
                }
            }

            // MARK: - Text-to-Speech

            GeneralSettingsSection(title: "Text-to-Speech") {
                NavigationLink {
                    SettingsSubviewContainer {
                        TTSSettingsView(viewModel: viewModel)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Voice Settings")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text(ttsSummary)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppSurfaces.color(.cardBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // MARK: - Data Management

            GeneralSettingsSection(title: "Data Management") {
                NavigationLink {
                    DataManagementView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Customize Data Distribution")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text(dataManagementSummary)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(AppSurfaces.color(.cardBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .sheet(isPresented: $showingNegotiationSheet) {
            CovenantNegotiationView(preselectedCategory: .providerChange)
                #if os(macOS)
                .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 800)
                #endif
        }
    }

    private var ttsSummary: String {
        let tts = viewModel.settings.ttsSettings
        return "\(tts.provider.displayName) · \(tts.qualityTier.displayName)"
    }

    private var dataManagementSummary: String {
        let config = viewModel.settings.deviceModeConfig
        return "\(config.cloudSyncProvider.displayName) · \(config.dataStorage.displayName) · \(config.aiProcessing.displayName) AI"
    }

    private func themeIcon(_ theme: Theme) -> String {
        switch theme {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .auto: return "circle.lefthalf.filled"
        }
    }

    // Note: Model selection helpers (pricingText, preferredDefaultModelId, versionScore, etc.)
    // have been moved to SettingsComponents.swift as part of the reusable model selection components.
}

// MARK: - Reusable Components

struct GeneralSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.headlineSmall())
                .foregroundColor(AppColors.textPrimary)

            content
        }
    }
}

struct SettingsOptionRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                    .frame(width: 32)

                Text(title)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.signalMercury)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppSurfaces.color(.selectedBackground) : AppSurfaces.color(.cardBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppSurfaces.color(.selectedBorder) : AppSurfaces.color(.cardBorder), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// SettingsToggleRow moved to SharedUIElements.swift
// MLXSelectedModelCard moved to SettingsComponents.swift as MLXModelInfoCard

// MARK: - Temporal Mode Button

struct TemporalModeButton: View {
    let mode: TemporalMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                Text(mode.displayName)
                    .font(AppTypography.bodyMedium(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury : AppSurfaces.color(.cardBackground))
            )
            .foregroundColor(isSelected ? .white : AppColors.textPrimary)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        GeneralSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppSurfaces.color(.contentBackground))
}
