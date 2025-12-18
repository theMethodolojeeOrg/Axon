//
//  TTSSettingsView.swift
//  Axon
//
//  Text-to-Speech settings with provider selection (ElevenLabs, Gemini, OpenAI)
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

            qualitySection

            ttsTextSection

            switch viewModel.settings.ttsSettings.provider {
            case .elevenlabs:
                elevenLabsSection
            case .gemini:
                geminiSection
            case .openai:
                openaiSection
            }
        }
    }

    // MARK: - Quality Tier

    private var qualitySection: some View {
        UnifiedSettingsSection(title: "Quality & Cost") {
            VStack(spacing: 12) {
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quality Tier")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        HStack(spacing: 8) {
                            ForEach(TTSQualityTier.allCases) { tier in
                                Button {
                                    Task { await viewModel.updateTTSSetting(\.qualityTier, tier) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: tier.icon)
                                            .font(.system(size: 14))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tier.displayName)
                                                .font(AppTypography.bodySmall(.medium))
                                            Text(tier.description)
                                                .font(AppTypography.labelSmall())
                                                .foregroundColor(AppColors.textSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(viewModel.settings.ttsSettings.qualityTier == tier
                                                  ? AppColors.signalMercury.opacity(0.15)
                                                  : AppColors.substrateSecondary)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(viewModel.settings.ttsSettings.qualityTier == tier
                                                            ? AppColors.signalMercury
                                                            : AppColors.glassBorder, lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(viewModel.settings.ttsSettings.qualityTier == tier
                                                 ? AppColors.signalMercury
                                                 : AppColors.textPrimary)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                            Text("Standard uses faster/cheaper models (Flash, TTS-1). High Quality uses best models available.")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.textTertiary)
                    }
                }
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

                    Divider().background(AppColors.divider)

                    ProviderRow(
                        title: TTSProvider.openai.displayName,
                        subtitle: TTSProvider.openai.description,
                        icon: TTSProvider.openai.icon,
                        isSelected: viewModel.settings.ttsSettings.provider == .openai,
                        status: viewModel.isOpenAITTSConfigured ? .configured : .notConfigured,
                        onSelect: {
                            Task { await viewModel.updateTTSSetting(\.provider, .openai) }
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
                ElevenLabsVoicePickerCard(viewModel: viewModel)

                // Model picker
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        StyledMenuPicker(
                            icon: "cpu",
                            title: viewModel.settings.ttsSettings.model.displayName,
                            selection: Binding(
                                get: { viewModel.settings.ttsSettings.model.rawValue },
                                set: { newValue in
                                    if let model = TTSModel(rawValue: newValue) {
                                        Task { await viewModel.updateTTSSetting(\.model, model) }
                                    }
                                }
                            )
                        ) {
                            #if os(macOS)
                            ForEach(TTSModel.allCases) { model in
                                MenuButtonItem(
                                    id: model.rawValue,
                                    label: "\(model.displayName) - \(model.description)",
                                    isSelected: viewModel.settings.ttsSettings.model == model
                                ) {
                                    Task { await viewModel.updateTTSSetting(\.model, model) }
                                }
                            }
                            #else
                            ForEach(TTSModel.allCases) { model in
                                Text("\(model.displayName) - \(model.description)").tag(model.rawValue)
                            }
                            #endif
                        }
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

    // MARK: - Voice Filtering

    private var filteredGeminiVoices: [GeminiTTSVoice] {
        if let filter = viewModel.settings.ttsSettings.voiceGenderFilter {
            return GeminiTTSVoice.voices(for: filter)
        }
        return GeminiTTSVoice.allCases
    }

    private var filteredOpenAIVoices: [OpenAITTSVoice] {
        if let filter = viewModel.settings.ttsSettings.voiceGenderFilter {
            return OpenAITTSVoice.voices(for: filter)
        }
        return OpenAITTSVoice.allCases
    }

    // MARK: - Gemini

    private var geminiSection: some View {
        UnifiedSettingsSection(title: "Gemini") {
            VStack(alignment: .leading, spacing: 12) {
                // Status card
                SettingsCard(padding: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.isGeminiTTSConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(viewModel.isGeminiTTSConfigured ? AppColors.accentSuccess : AppColors.accentWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isGeminiTTSConfigured ? "Gemini API Key Configured" : "Gemini API Key Required")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Gemini TTS outputs 24kHz audio. Supports controllable speech styles.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                }

                // Model picker
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        StyledMenuPicker(
                            icon: "cpu",
                            title: viewModel.settings.ttsSettings.geminiModel.displayName,
                            selection: Binding(
                                get: { viewModel.settings.ttsSettings.geminiModel.rawValue },
                                set: { newValue in
                                    if let model = GeminiTTSModel(rawValue: newValue) {
                                        Task { await viewModel.updateTTSSetting(\.geminiModel, model) }
                                    }
                                }
                            )
                        ) {
                            #if os(macOS)
                            ForEach(GeminiTTSModel.allCases) { model in
                                MenuButtonItem(
                                    id: model.rawValue,
                                    label: "\(model.displayName) - \(model.description)",
                                    isSelected: viewModel.settings.ttsSettings.geminiModel == model
                                ) {
                                    Task { await viewModel.updateTTSSetting(\.geminiModel, model) }
                                }
                            }
                            #else
                            ForEach(GeminiTTSModel.allCases) { model in
                                Text("\(model.displayName) - \(model.description)").tag(model.rawValue)
                            }
                            #endif
                        }
                        .disabled(!viewModel.isGeminiTTSConfigured)
                    }
                }

                // Voice picker (scrollable grid for 30 voices)
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Voice")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            // Gender filter
                            HStack(spacing: 4) {
                                GenderFilterButton(
                                    label: "All",
                                    isSelected: viewModel.settings.ttsSettings.voiceGenderFilter == nil,
                                    action: { Task { await viewModel.updateTTSSetting(\.voiceGenderFilter, nil) } }
                                )
                                GenderFilterButton(
                                    label: "♀",
                                    isSelected: viewModel.settings.ttsSettings.voiceGenderFilter == .female,
                                    action: { Task { await viewModel.updateTTSSetting(\.voiceGenderFilter, .female) } }
                                )
                                GenderFilterButton(
                                    label: "♂",
                                    isSelected: viewModel.settings.ttsSettings.voiceGenderFilter == .male,
                                    action: { Task { await viewModel.updateTTSSetting(\.voiceGenderFilter, .male) } }
                                )
                            }
                        }

                        ScrollView {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(filteredGeminiVoices) { voice in
                                    GeminiVoiceCard(
                                        voice: voice,
                                        isSelected: viewModel.settings.ttsSettings.geminiVoice == voice,
                                        isConfigured: viewModel.isGeminiTTSConfigured,
                                        settings: viewModel.settings,
                                        onSelect: {
                                            Task { await viewModel.updateTTSSetting(\.geminiVoice, voice) }
                                        }
                                    )
                                    .disabled(!viewModel.isGeminiTTSConfigured)
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }

                // Voice direction/style instructions
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Voice Direction")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            Text("Optional")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        TextField(
                            "e.g., Speak cheerfully with a slight British accent",
                            text: Binding(
                                get: { viewModel.settings.ttsSettings.geminiVoiceDirection },
                                set: { newValue in
                                    Task { await viewModel.updateTTSSetting(\.geminiVoiceDirection, newValue) }
                                }
                            ),
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppColors.substrateSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.glassBorder, lineWidth: 1)
                                )
                        )
                        .lineLimit(2...4)
                        .disabled(!viewModel.isGeminiTTSConfigured)

                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                            Text("Control style, accent, pace, and tone using natural language. Leave empty for default voice.")
                                .font(AppTypography.labelSmall())
                        }
                        .foregroundColor(AppColors.textTertiary)
                    }
                }
                .disabled(!viewModel.isGeminiTTSConfigured)

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

    // MARK: - OpenAI

    private var openaiSection: some View {
        UnifiedSettingsSection(title: "OpenAI") {
            VStack(alignment: .leading, spacing: 12) {
                // Status card
                SettingsCard(padding: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.isOpenAITTSConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(viewModel.isOpenAITTSConfigured ? AppColors.accentSuccess : AppColors.accentWarning)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isOpenAITTSConfigured ? "OpenAI API Key Configured" : "OpenAI API Key Required")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("OpenAI TTS outputs MP3 audio. Uses your OpenAI API key.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                }

                // Model picker
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        StyledMenuPicker(
                            icon: "cpu",
                            title: viewModel.settings.ttsSettings.openaiModel.displayName,
                            selection: Binding(
                                get: { viewModel.settings.ttsSettings.openaiModel.rawValue },
                                set: { newValue in
                                    if let model = OpenAITTSModel(rawValue: newValue) {
                                        Task { await viewModel.updateTTSSetting(\.openaiModel, model) }
                                    }
                                }
                            )
                        ) {
                            #if os(macOS)
                            ForEach(OpenAITTSModel.allCases) { model in
                                MenuButtonItem(
                                    id: model.rawValue,
                                    label: "\(model.displayName) - \(model.description)",
                                    isSelected: viewModel.settings.ttsSettings.openaiModel == model
                                ) {
                                    Task { await viewModel.updateTTSSetting(\.openaiModel, model) }
                                }
                            }
                            #else
                            ForEach(OpenAITTSModel.allCases) { model in
                                Text("\(model.displayName) - \(model.description)").tag(model.rawValue)
                            }
                            #endif
                        }
                        .disabled(!viewModel.isOpenAITTSConfigured)
                    }
                }

                // Voice picker (grid layout like Gemini)
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Voice")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            // Gender filter
                            HStack(spacing: 4) {
                                GenderFilterButton(
                                    label: "All",
                                    isSelected: viewModel.settings.ttsSettings.voiceGenderFilter == nil,
                                    action: { Task { await viewModel.updateTTSSetting(\.voiceGenderFilter, nil) } }
                                )
                                GenderFilterButton(
                                    label: "♀",
                                    isSelected: viewModel.settings.ttsSettings.voiceGenderFilter == .female,
                                    action: { Task { await viewModel.updateTTSSetting(\.voiceGenderFilter, .female) } }
                                )
                                GenderFilterButton(
                                    label: "♂",
                                    isSelected: viewModel.settings.ttsSettings.voiceGenderFilter == .male,
                                    action: { Task { await viewModel.updateTTSSetting(\.voiceGenderFilter, .male) } }
                                )
                            }
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(filteredOpenAIVoices) { voice in
                                OpenAIVoiceCard(
                                    voice: voice,
                                    isSelected: viewModel.settings.ttsSettings.openaiVoice == voice,
                                    isConfigured: viewModel.isOpenAITTSConfigured,
                                    settings: viewModel.settings,
                                    onSelect: {
                                        Task { await viewModel.updateTTSSetting(\.openaiVoice, voice) }
                                    }
                                )
                                .disabled(!viewModel.isOpenAITTSConfigured)
                            }
                        }
                    }
                }

                // Speed slider
                SettingsCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speed")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Speech Rate")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                                Text(String(format: "%.2fx", viewModel.settings.ttsSettings.openaiSpeed))
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(AppColors.signalMercury)
                            }
                            Slider(
                                value: Binding(
                                    get: { viewModel.settings.ttsSettings.openaiSpeed },
                                    set: { newValue in
                                        Task { await viewModel.updateTTSSetting(\.openaiSpeed, newValue) }
                                    }
                                ),
                                in: 0.25...4.0,
                                step: 0.25
                            )
                            .tint(AppColors.signalMercury)

                            HStack {
                                Text("0.25x")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                Spacer()
                                Text("1.0x")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                Spacer()
                                Text("4.0x")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    }
                }
                .disabled(!viewModel.isOpenAITTSConfigured)

                // Voice instructions (only for gpt-4o-mini-tts)
                if viewModel.settings.ttsSettings.openaiModel.supportsInstructions {
                    SettingsCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Voice Instructions")
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textSecondary)

                                Spacer()

                                Text("GPT-4o Mini TTS only")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }

                            TextField(
                                "e.g., Speak in a cheerful and positive tone",
                                text: Binding(
                                    get: { viewModel.settings.ttsSettings.openaiVoiceInstructions },
                                    set: { newValue in
                                        Task { await viewModel.updateTTSSetting(\.openaiVoiceInstructions, newValue) }
                                    }
                                ),
                                axis: .vertical
                            )
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.substrateSecondary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(AppColors.glassBorder, lineWidth: 1)
                                    )
                            )
                            .lineLimit(2...4)

                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                Text("Control accent, emotional range, intonation, speed, tone, and more.")
                                    .font(AppTypography.labelSmall())
                            }
                            .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    .disabled(!viewModel.isOpenAITTSConfigured)
                }

                if !viewModel.isOpenAITTSConfigured {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("Add your OpenAI API key in Settings → API Keys to enable OpenAI TTS.")
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.textTertiary)
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

// MARK: - ElevenLabs Voice Picker Card

private struct ElevenLabsVoicePickerCard: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var ttsService = TTSPlaybackService.shared
    @State private var previewError: String?

    private var isPreviewingCurrentVoice: Bool {
        guard let voiceId = viewModel.settings.ttsSettings.selectedVoiceId else { return false }
        return ttsService.currentMessageId == "preview_elevenlabs_\(voiceId)"
    }

    var body: some View {
        SettingsCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Voice")
                    .font(AppTypography.labelMedium())
                    .foregroundColor(AppColors.textSecondary)

                HStack(spacing: 8) {
                    StyledMenuPicker(
                        icon: "waveform",
                        title: viewModel.settings.ttsSettings.selectedVoiceName ?? "Select a voice",
                        selection: Binding(
                            get: { viewModel.settings.ttsSettings.selectedVoiceId ?? "" },
                            set: { newId in
                                let voice = viewModel.availableVoices.first { $0.id == newId }
                                Task { await viewModel.updateSelectedVoice(id: voice?.id, name: voice?.name) }
                            }
                        )
                    ) {
                        #if os(macOS)
                        if viewModel.availableVoices.isEmpty {
                            Text("No voices found")
                        } else {
                            ForEach(viewModel.availableVoices) { voice in
                                MenuButtonItem(
                                    id: voice.id,
                                    label: voice.name,
                                    isSelected: viewModel.settings.ttsSettings.selectedVoiceId == voice.id
                                ) {
                                    Task { await viewModel.updateSelectedVoice(id: voice.id, name: voice.name) }
                                }
                            }
                        }
                        #else
                        if viewModel.availableVoices.isEmpty {
                            Text("No voices found").tag("")
                        } else {
                            ForEach(viewModel.availableVoices) { voice in
                                Text(voice.name).tag(voice.id)
                            }
                        }
                        #endif
                    }
                    .disabled(!viewModel.isTTSConfigured)

                    // Preview button
                    if viewModel.isTTSConfigured,
                       let voiceId = viewModel.settings.ttsSettings.selectedVoiceId,
                       let voiceName = viewModel.settings.ttsSettings.selectedVoiceName {
                        Button {
                            if isPreviewingCurrentVoice && (ttsService.isPlaying || ttsService.isGenerating) {
                                ttsService.stop()
                            } else {
                                Task {
                                    do {
                                        previewError = nil
                                        try await ttsService.previewElevenLabsVoice(
                                            voiceId: voiceId,
                                            voiceName: voiceName,
                                            settings: viewModel.settings
                                        )
                                    } catch {
                                        previewError = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Group {
                                if isPreviewingCurrentVoice && ttsService.isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 20, height: 20)
                                } else if isPreviewingCurrentVoice && ttsService.isPlaying {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 14))
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14))
                                }
                            }
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 36, height: 36)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = previewError {
                    Text(error)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.accentWarning)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Gemini Voice Card

struct GeminiVoiceCard: View {
    let voice: GeminiTTSVoice
    let isSelected: Bool
    let isConfigured: Bool
    let settings: AppSettings
    let onSelect: () -> Void

    @StateObject private var ttsService = TTSPlaybackService.shared
    @State private var previewError: String?

    private var isPreviewingThisVoice: Bool {
        ttsService.currentMessageId == "preview_gemini_\(voice.rawValue)"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(voice.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()

                    // Preview button
                    if isConfigured {
                        Button {
                            if isPreviewingThisVoice && (ttsService.isPlaying || ttsService.isGenerating) {
                                ttsService.stop()
                            } else {
                                Task {
                                    do {
                                        previewError = nil
                                        try await ttsService.previewGeminiVoice(voice, settings: settings)
                                    } catch {
                                        previewError = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Group {
                                if isPreviewingThisVoice && ttsService.isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 20, height: 20)
                                } else if isPreviewingThisVoice && ttsService.isPlaying {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 12))
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 12))
                                }
                            }
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 28, height: 28)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }

                Text(voice.toneDescription)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)

                if let error = previewError {
                    Text(error)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.accentWarning)
                        .lineLimit(2)
                }
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

// MARK: - Gender Filter Button

private struct GenderFilterButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(AppTypography.labelSmall())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : Color.clear)
                )
                .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - OpenAI Voice Card

struct OpenAIVoiceCard: View {
    let voice: OpenAITTSVoice
    let isSelected: Bool
    let isConfigured: Bool
    let settings: AppSettings
    let onSelect: () -> Void

    @StateObject private var ttsService = TTSPlaybackService.shared
    @State private var previewError: String?

    private var isPreviewingThisVoice: Bool {
        ttsService.currentMessageId == "preview_openai_\(voice.rawValue)"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(voice.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()

                    // Preview button
                    if isConfigured {
                        Button {
                            if isPreviewingThisVoice && (ttsService.isPlaying || ttsService.isGenerating) {
                                ttsService.stop()
                            } else {
                                Task {
                                    do {
                                        previewError = nil
                                        try await ttsService.previewOpenAIVoice(voice, settings: settings)
                                    } catch {
                                        previewError = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            Group {
                                if isPreviewingThisVoice && ttsService.isGenerating {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 20, height: 20)
                                } else if isPreviewingThisVoice && ttsService.isPlaying {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 12))
                                } else {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 12))
                                }
                            }
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 28, height: 28)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }

                Text(voice.toneDescription)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)

                if let error = previewError {
                    Text(error)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.accentWarning)
                        .lineLimit(2)
                }
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
