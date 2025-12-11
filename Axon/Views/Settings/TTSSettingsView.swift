//
//  TTSSettingsView.swift
//  Axon
//
//  Text-to-Speech settings with provider selection (ElevenLabs vs Gemini)
//

import SwiftUI

struct TTSSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var elevenLabsExpanded = true
    @State private var geminiExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Provider Selection Header
            SettingsSection(title: "TTS Provider") {
                Text("Select your preferred text-to-speech provider. Only one can be active at a time.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 8)
            }

            // ElevenLabs Accordion
            TTSProviderAccordion(
                provider: .elevenlabs,
                isSelected: viewModel.settings.ttsSettings.provider == .elevenlabs,
                isExpanded: $elevenLabsExpanded,
                onSelect: {
                    Task {
                        await viewModel.updateTTSSetting(\.provider, TTSProvider.elevenlabs)
                    }
                    withAnimation { geminiExpanded = false }
                }
            ) {
                ElevenLabsSettingsContent(viewModel: viewModel)
            }

            // Gemini Accordion
            TTSProviderAccordion(
                provider: .gemini,
                isSelected: viewModel.settings.ttsSettings.provider == .gemini,
                isExpanded: $geminiExpanded,
                onSelect: {
                    Task {
                        await viewModel.updateTTSSetting(\.provider, TTSProvider.gemini)
                    }
                    withAnimation { elevenLabsExpanded = false }
                }
            ) {
                GeminiTTSSettingsContent(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Provider Accordion

struct TTSProviderAccordion<Content: View>: View {
    let provider: TTSProvider
    let isSelected: Bool
    @Binding var isExpanded: Bool
    let onSelect: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header with toggle and expand button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Provider toggle (radio button style)
                    Button(action: onSelect) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Provider icon
                    Image(systemName: provider.icon)
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                        .frame(width: 28)

                    // Provider info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(provider.description)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Expand indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(16)
                .background(AppColors.substrateSecondary.opacity(0.5))
                .cornerRadius(12)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - ElevenLabs Settings Content

struct ElevenLabsSettingsContent: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // API Key Status
            HStack(spacing: 12) {
                if viewModel.isTTSConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.accentSuccess)
                    Text("API Key Configured")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.accentSuccess)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(AppColors.accentWarning)
                    Text("API Key Required")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.accentWarning)
                }
                Spacer()
            }

            // Voice Picker
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
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(8)
                }
                .pickerStyle(.menu)
            }

            // Model Picker
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
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(8)
                }
                .pickerStyle(.menu)
            }

            // Voice Settings (Stability, Similarity, etc.)
            VStack(alignment: .leading, spacing: 12) {
                Text("Voice Settings")
                    .font(AppTypography.labelMedium())
                    .foregroundColor(AppColors.textSecondary)

                // Stability Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Stability")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Text("\(Int(viewModel.settings.ttsSettings.voiceSettings.stability * 100))%")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.signalMercury)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.settings.ttsSettings.voiceSettings.stability },
                            set: { newValue in
                                Task { await viewModel.updateTTSSetting(\.voiceSettings.stability, newValue) }
                            }
                        ),
                        in: 0...1
                    )
                    .tint(AppColors.signalMercury)
                }

                // Similarity Boost Slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Similarity")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Text("\(Int(viewModel.settings.ttsSettings.voiceSettings.similarityBoost * 100))%")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.signalMercury)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.settings.ttsSettings.voiceSettings.similarityBoost },
                            set: { newValue in
                                Task { await viewModel.updateTTSSetting(\.voiceSettings.similarityBoost, newValue) }
                            }
                        ),
                        in: 0...1
                    )
                    .tint(AppColors.signalMercury)
                }
            }

            // Refresh button
            Button(action: {
                Task { await viewModel.refreshElevenLabsCatalog() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Voices")
                }
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.signalMercury)
            }
            .disabled(!viewModel.isTTSConfigured)
        }
    }
}

// MARK: - Gemini TTS Settings Content

struct GeminiTTSSettingsContent: View {
    @ObservedObject var viewModel: SettingsViewModel

    private var hasGeminiKey: Bool {
        // Reuse existing configuration flag until a dedicated Gemini flag is available
        return viewModel.isTTSConfigured
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // API Key Status
            HStack(spacing: 12) {
                if hasGeminiKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.accentSuccess)
                    Text("Gemini API Key Configured")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.accentSuccess)
                } else {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(AppColors.accentWarning)
                    Text("Gemini API Key Required")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.accentWarning)
                }
                Spacer()
            }

            // Voice Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Voice")
                    .font(AppTypography.labelMedium())
                    .foregroundColor(AppColors.textSecondary)

                // Voice grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(GeminiTTSVoice.allCases) { voice in
                        GeminiVoiceCard(
                            voice: voice,
                            isSelected: viewModel.settings.ttsSettings.geminiVoice == voice,
                            onSelect: {
                                Task { await viewModel.updateTTSSetting(\.geminiVoice, voice) }
                            }
                        )
                    }
                }
            }

            // Info about Gemini TTS
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(AppColors.textTertiary)
                Text("Gemini TTS outputs 24kHz WAV audio. Uses your Gemini API key.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }
}

// MARK: - Gemini Voice Card

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
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : AppColors.substrateTertiary)
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
