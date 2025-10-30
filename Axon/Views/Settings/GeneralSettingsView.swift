//
//  GeneralSettingsView.swift
//  Axon
//
//  General settings for theme, AI provider, and model selection
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.colorScheme) var systemColorScheme

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
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                    }
                }
            }

            // MARK: - AI Provider Section

            GeneralSettingsSection(title: "AI Provider") {
                VStack(spacing: 12) {
                    ForEach(AIProvider.allCases) { provider in
                        SettingsOptionRow(
                            title: provider.displayName,
                            icon: "cpu.fill",
                            isSelected: viewModel.settings.defaultProvider == provider
                        ) {
                            Task {
                                // Switch provider and reset to first model
                                if let firstModel = provider.availableModels.first {
                                    await viewModel.updateSetting(\.defaultModel, firstModel.id)
                                }
                                await viewModel.updateSetting(\.defaultProvider, provider)
                            }
                        }
                    }
                }
            }

            // MARK: - Model Selection

            GeneralSettingsSection(title: "Model") {
                VStack(spacing: 12) {
                    ForEach(viewModel.settings.defaultProvider.availableModels) { model in
                        ModelRow(
                            model: model,
                            isSelected: viewModel.settings.defaultModel == model.id
                        ) {
                            Task {
                                await viewModel.updateSetting(\.defaultModel, model.id)
                            }
                        }
                    }
                }
            }

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
        }
    }

    private func themeIcon(_ theme: Theme) -> String {
        switch theme {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .auto: return "circle.lefthalf.filled"
        }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: AIModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(model.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Label(
                            String(format: "%.0fK context", Double(model.contextWindow) / 1000),
                            systemImage: "brain.head.profile"
                        )
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.signalMercury)
                        .font(.system(size: 20))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
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
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 32)

            Text(title)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColors.signalMercury)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        GeneralSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}

