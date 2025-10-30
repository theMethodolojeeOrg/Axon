//
//  TTSSettingsView.swift
//  Axon
//
//  Text-to-Speech settings with voice configuration
//

import SwiftUI

struct TTSSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingAPIKeyInput = false
    @State private var editingAPIKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // ElevenLabs API Key Section
            SettingsSection(title: "ElevenLabs API Key") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ElevenLabs API Key")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            HStack(spacing: 8) {
                                if viewModel.isTTSConfigured {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppColors.accentSuccess)
                                    Text("Configured")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.accentSuccess)
                                } else {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(AppColors.accentWarning)
                                    Text("Not Configured")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.accentWarning)
                                }
                            }
                        }

                        Spacer()

                        Menu {
                            Button(action: {
                                editingAPIKey = viewModel.getAPIKey(.elevenlabs) ?? ""
                                showingAPIKeyInput = true
                            }) {
                                Label(viewModel.isTTSConfigured ? "Edit Key" : "Add Key", systemImage: "pencil")
                            }

                            if viewModel.isTTSConfigured {
                                Button(role: .destructive, action: {
                                    Task {
                                        await viewModel.clearTTSAPIKey()
                                    }
                                }) {
                                    Label("Remove Key", systemImage: "trash")
                                }
                            }

                            Divider()

                            Button(action: {
                                if let url = URL(string: "https://elevenlabs.io/app/settings/api-keys") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Label("Get API Key", systemImage: "link")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .foregroundColor(AppColors.textSecondary)
                                .font(.system(size: 24))
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }
            }

            // TTS Model Section
            SettingsSection(title: "TTS Model") {
                VStack(spacing: 12) {
                    ForEach(TTSModel.allCases) { model in
                        SettingsRadioRow(
                            title: model.displayName,
                            subtitle: model.description,
                            isSelected: viewModel.settings.ttsSettings.model == model
                        ) {
                            Task {
                                await viewModel.updateTTSSetting(\.model, model)
                            }
                        }
                    }
                }
            }

            // Output Format Section
            SettingsSection(title: "Output Format") {
                VStack(spacing: 12) {
                    ForEach(TTSOutputFormat.allCases) { format in
                        SettingsRadioRow(
                            title: format.displayName,
                            subtitle: format.description,
                            isSelected: viewModel.settings.ttsSettings.outputFormat == format
                        ) {
                            Task {
                                await viewModel.updateTTSSetting(\.outputFormat, format)
                            }
                        }
                    }
                }
            }

            // Voice Settings Section
            SettingsSection(title: "Voice Settings") {
                VStack(spacing: 20) {
                    // Stability
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Stability")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("\(Int(viewModel.settings.ttsSettings.voiceSettings.stability * 100))%")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.settings.ttsSettings.voiceSettings.stability },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateTTSSetting(\.voiceSettings.stability, newValue)
                                    }
                                }
                            ),
                            in: 0...1,
                            step: 0.01
                        )
                        .tint(AppColors.signalMercury)

                        Text("Higher values create more consistent voice, lower values add variation")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Similarity Boost
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Similarity Boost")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("\(Int(viewModel.settings.ttsSettings.voiceSettings.similarityBoost * 100))%")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.settings.ttsSettings.voiceSettings.similarityBoost },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateTTSSetting(\.voiceSettings.similarityBoost, newValue)
                                    }
                                }
                            ),
                            in: 0...1,
                            step: 0.01
                        )
                        .tint(AppColors.signalMercury)

                        Text("Boosts similarity to the original voice at expense of stability")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Style
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Style")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("\(Int(viewModel.settings.ttsSettings.voiceSettings.style * 100))%")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.settings.ttsSettings.voiceSettings.style },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateTTSSetting(\.voiceSettings.style, newValue)
                                    }
                                }
                            ),
                            in: 0...1,
                            step: 0.01
                        )
                        .tint(AppColors.signalMercury)

                        Text("Higher values exaggerate the style, lower values are more neutral")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    // Speaker Boost
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(isOn: Binding(
                                get: { viewModel.settings.ttsSettings.voiceSettings.useSpeakerBoost },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateTTSSetting(\.voiceSettings.useSpeakerBoost, newValue)
                                    }
                                }
                            )) {
                                Text("Speaker Boost")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            .tint(AppColors.signalMercury)
                        }

                        Text("Boosts similarity to the speaker but may cause artifacts")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }
        .sheet(isPresented: $showingAPIKeyInput) {
            APIKeyInputSheet(
                provider: .elevenlabs,
                keyValue: $editingAPIKey,
                onSave: {
                    Task {
                        await viewModel.saveTTSAPIKey(editingAPIKey)
                        showingAPIKeyInput = false
                    }
                },
                onCancel: {
                    showingAPIKeyInput = false
                }
            )
        }
    }
}

// MARK: - Settings Radio Row

struct SettingsRadioRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(subtitle)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "circle.fill" : "circle")
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)
                    .font(.system(size: 20))
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


// MARK: - Preview

#Preview {
    ScrollView {
        TTSSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
