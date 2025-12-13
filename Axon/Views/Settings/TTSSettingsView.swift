//
//  TTSSettingsView.swift
//  Axon
//
//  Text-to-Speech settings with provider selection (ElevenLabs vs Gemini)
//

import SwiftUI

struct TTSSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsInfoBanner(
                icon: "speaker.wave.2",
                text: "Configure Text-to-Speech provider, voices, and how messages are read aloud.")

            providerSection

            ttsTextSection

            if viewModel.settings.ttsSettings.provider == .elevenlabs {
                elevenLabsSection
            } else {
                geminiSection
            }
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        UnifiedSettingsSection(title: "TTS Provider") {
            SettingsCard(padding: 0) {
                VStack(spacing: 0) {
                    ProviderRow(
                        title: TTSProvider.elevenlabs.displayName,
                        subtitle: TTSProvider.elevenlabs.description,
                        icon: TTSProvider.elevenlabs.icon,
                        isSelected: viewModel.settings.ttsSettings.provider == .elevenlabs,
                        status: viewModel.isTTSConfigured ? .configured : .notConfigured,
                        onSelect: {
                            Task { await viewModel.updateTTSSetting(\.provider, .elevenlabs) }
                        }
                    )

                    Divider().background(AppColors.divider)

                    ProviderRow(
                        title: TTSProvider.gemini.displayName,
                        subtitle: TTSProvider.gemini.description,
                        icon: TTSProvider.gemini.icon,
                        isSelected: viewModel.settings.ttsSettings.provider == .gemini,
                        status: viewModel.isGeminiTTSConfigured ? .configured : .notConfigured,
                        onSelect: {
                            Task { await viewModel.updateTTSSetting(\.provider, .gemini) }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Text

    private var ttsTextSection: some View {
        UnifiedSettingsSection(title: "TTS Text") {
            VStack(spacing: 12) {
                SettingsToggleRow(
                    title: "Strip markdown before speech",
                    icon: "text.badge.checkmark",
                    isOn: Binding(
                        get: { viewModel.settings.ttsSettings.stripMarkdownBeforeTTS },
                        set: { newValue in
                            Task { await viewModel.updateTTSSetting(\.stripMarkdownBeforeTTS, newValue) }
                        }
                    )
                )

                SettingsToggleRow(
                    title: "Spoken-friendly mode",
                    icon: "waveform.path.ecg",
                    isOn: Binding(
                        get: { viewModel.settings.ttsSettings.spokenFriendlyTTS },
                        set: { newValue in
                            Task { await viewModel.updateTTSSetting(\.spokenFriendlyTTS, newValue) }
                        }
                    )
                )
                .disabled(!viewModel.settings.ttsSettings.stripMarkdownBeforeTTS)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Markdown stripping prevents reading formatting symbols. Spoken-friendly mode applies light normalization for more natural speech.")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.textTertiary)
            }
        }
    }

    // MARK: - ElevenLabs

    private var elevenLabsSection: some View {
        UnifiedSettingsSection(title: "ElevenLabs") {
            VStack(alignment: .leading, spacing: 12) {
                // Status card
                SettingsCard(padding: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.isTTSConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(viewModel.isTTSConfigured ? AppColors.accentSuccess : AppColors.accentWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isTTSConfigured ? "API Key Configured" : "API Key Required")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Voices are cached locally and synced via CloudKit.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Button {
                            Task { await viewModel.refreshElevenLabsCatalog() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(AppTypography.labelSmall())
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.signalMercury)
                        .disabled(!viewModel.isTTSConfigured)
                    }
                }

                // Voice picker
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        Picker(selection: Binding(
                            get: { viewModel.settings.ttsSettings.selectedVoiceId ?? "" },
                            set: { newId in
                                let voice = viewModel.availableVoices.first { $0.id == newId }
                                Task { await viewModel.updateSelectedVoice(id: voice?.id, name: voice?.name) }
                            }
                        )) {
                            if viewModel.availableVoices.isEmpty {
                                Text("No voices found").tag("")
                            } else {
                                ForEach(viewModel.availableVoices) { voice in
                                    Text(voice.name).tag(voice.id)
                                }
                            }
                        } label: {
                            HStack {
                                Text(viewModel.settings.ttsSettings.selectedVoiceName ?? "Select a voice")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.substrateSecondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppColors.glassBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .pickerStyle(.menu)
                        .disabled(!viewModel.isTTSConfigured)
                    }
                }

                // Model picker
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        Picker(selection: Binding(
                            get: { viewModel.settings.ttsSettings.model },
                            set: { newModel in
                                Task { await viewModel.updateTTSSetting(\.model, newModel) }
                            }
                        )) {
                            ForEach(TTSModel.allCases) { model in
                                Text("\(model.displayName) - \(model.description)").tag(model)
                            }
                        } label: {
                            HStack {
                                Text(viewModel.settings.ttsSettings.model.displayName)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.substrateSecondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppColors.glassBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .pickerStyle(.menu)
                        .disabled(!viewModel.isTTSConfigured)
                    }
                }

                // Voice settings sliders
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice Settings")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        sliderRow(
                            title: "Stability",
                            value: Binding(
                                get: { viewModel.settings.ttsSettings.voiceSettings.stability },
                                set: { newValue in
                                    Task { await viewModel.updateTTSSetting(\.voiceSettings.stability, newValue) }
                                }
                            )
                        )

                        sliderRow(
                            title: "Similarity",
                            value: Binding(
                                get: { viewModel.settings.ttsSettings.voiceSettings.similarityBoost },
                                set: { newValue in
                                    Task { await viewModel.updateTTSSetting(\.voiceSettings.similarityBoost, newValue) }
                                }
                            )
                        )
                    }
                }
                .disabled(!viewModel.isTTSConfigured)
            }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.signalMercury)
            }
            Slider(value: value, in: 0...1)
                .tint(AppColors.signalMercury)
        }
    }

    // MARK: - Gemini

    private var geminiSection: some View {
        UnifiedSettingsSection(title: "Gemini") {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCard(padding: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.isGeminiTTSConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(viewModel.isGeminiTTSConfigured ? AppColors.accentSuccess : AppColors.accentWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isGeminiTTSConfigured ? "Gemini API Key Configured" : "Gemini API Key Required")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Gemini TTS outputs 24kHz WAV audio. Uses your Gemini API key.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                }

                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Voice")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(GeminiTTSVoice.allCases) { voice in
                                GeminiVoiceCard(
                                    voice: voice,
                                    isSelected: viewModel.settings.ttsSettings.geminiVoice == voice,
                                    onSelect: {
                                        Task { await viewModel.updateTTSSetting(\.geminiVoice, voice) }
                                    }
                                )
                                .disabled(!viewModel.isGeminiTTSConfigured)
                            }
                        }

                        if !viewModel.isGeminiTTSConfigured {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                Text("Add your Gemini API key in Settings → API Keys to enable Gemini TTS.")
                                    .font(AppTypography.labelSmall())
                            }
                            .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Provider Row

private enum ProviderStatus {
    case configured
    case notConfigured
}

private struct ProviderRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let status: ProviderStatus
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(subtitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                if status == .configured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.accentSuccess)
                } else {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(AppColors.accentWarning)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.signalMercury)
                        .font(.system(size: 18))
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gemini Voice Card (kept, but now lives in-card)

struct GeminiVoiceCard: View {
    let voice: GeminiTTSVoice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(voice.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }

                Text(voice.toneDescription)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScrollView {
        TTSSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
