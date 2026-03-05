//
//  CreateAudioSheet.swift
//  Axon
//
//  Studio-style sheet for generating audio via OpenAI/Gemini/ElevenLabs TTS.
//

import SwiftUI

struct CreateAudioSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var creationService = DirectMediaCreationService.shared
    @StateObject private var settingsViewModel = SettingsViewModel.shared

    @State private var text = ""
    @State private var selectedProvider: TTSProvider = .openai
    @State private var selectedOpenAIVoice: OpenAITTSVoice = .alloy
    @State private var selectedGeminiVoice: GeminiTTSService.GeminiVoice = .puck
    @State private var selectedElevenLabsVoiceId: String?
    @State private var selectedElevenLabsVoiceName: String?
    @State private var voiceDirection: String = ""
    @State private var selectedOpenAIModel: OpenAITTSModel = .gpt4oMiniTTS

    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedItem: CreativeItem?
    @State private var showDetailSheet = false

    // Waveform animation
    @State private var waveAnimating = false

    private var availableProviders: [TTSProvider] {
        creationService.availableTTSProviders
    }

    private var estimatedCost: Double {
        MediaCostEstimator.estimateTTSCost(provider: selectedProvider, characterCount: text.count)
    }

    var body: some View {
        #if os(macOS)
        sheetContent
            .frame(minWidth: 520, idealWidth: 580, minHeight: 560, idealHeight: 700)
            .onAppear { setupOnAppear() }
            .sheet(isPresented: $showDetailSheet) {
                if let item = generatedItem { CreativeItemDetailView(item: item) }
            }
        #else
        sheetContent
            .navigationTitle("Audio Studio")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDetailSheet) {
                if let item = generatedItem { CreativeItemDetailView(item: item) }
            }
            .onAppear { setupOnAppear() }
        #endif
    }

    private func setupOnAppear() {
        if let firstProvider = availableProviders.first {
            selectedProvider = firstProvider
        }
        if creationService.hasElevenLabsKey {
            Task {
                await settingsViewModel.refreshElevenLabsCatalog()
                if let first = settingsViewModel.availableVoices.first {
                    selectedElevenLabsVoiceId = first.id
                    selectedElevenLabsVoiceName = first.name
                }
            }
        }
        waveAnimating = true
    }

    private var sheetContent: some View {
        ZStack(alignment: .top) {
            AppColors.substratePrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero banner with animated waveform
                    heroBanner

                    VStack(spacing: 20) {
                        #if os(macOS)
                        HStack {
                            Spacer()
                            Button("Cancel") { dismiss() }
                                .foregroundColor(AppColors.textSecondary)
                                .font(AppTypography.bodySmall())
                        }
                        .padding(.top, 4)
                        #endif

                        // Text input
                        textSection

                        // Provider picker (if multiple available)
                        if availableProviders.count > 1 {
                            providerSection
                        }

                        // Voice selection
                        voiceSection

                        // Voice direction / model (for OpenAI & Gemini)
                        if selectedProvider == .openai || selectedProvider == .gemini {
                            voiceDirectionSection
                        }

                        // Cost + Generate
                        bottomSection

                        if let error = errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [AppColors.signalLichen.opacity(0.8), AppColors.signalLichenDark.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 120)

            // Decorative orbs
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 160, height: 160)
                .offset(x: -40, y: -30)

            // Waveform decoration
            HStack(spacing: 3) {
                ForEach(Array(waveformHeights.enumerated()), id: \.offset) { idx, baseH in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 3, height: waveAnimating ? baseH : baseH * 0.4)
                        .animation(
                            waveAnimating
                                ? .easeInOut(duration: 0.6 + Double(idx % 5) * 0.1)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(idx) * 0.04)
                                : .none,
                            value: waveAnimating
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)
            .padding(.bottom, 20)

            // Title
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("Audio Studio")
                            .font(AppTypography.titleMedium(.semibold))
                            .foregroundColor(.white)
                    }
                    Text("Text-to-Speech")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
    }

    private let waveformHeights: [CGFloat] = [
        16, 28, 44, 22, 50, 18, 38, 52, 20, 34, 16, 46, 30, 54, 18, 42, 26, 50, 14, 36, 48, 20, 40, 28, 44
    ]

    // MARK: - Text Section

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Script", systemImage: "text.alignleft")
                    .font(AppTypography.labelMedium(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                if text.count > 0 {
                    HStack(spacing: 6) {
                        Text("\(text.count) chars")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.textTertiary)
                        if estimatedCost > 0 {
                            Text("·")
                                .foregroundColor(AppColors.textTertiary)
                                .font(.system(size: 10))
                            Text("Est. \(MediaCostEstimator.formattedCost(estimatedCost))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Enter the text you want to convert to speech…")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(12)
            }
            .background(AppColors.substrateSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        text.isEmpty ? AppColors.glassBorder : AppColors.signalLichen.opacity(0.4),
                        lineWidth: 1.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
        }
        .padding(.top, 20)
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Provider", systemImage: "cpu")
                .font(AppTypography.labelMedium(.semibold))
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 8) {
                ForEach(availableProviders, id: \.self) { provider in
                    ProviderChip(
                        label: provider.displayName,
                        isSelected: selectedProvider == provider
                    ) { selectedProvider = provider }
                }
                Spacer()
            }
        }
    }

    // MARK: - Voice Section

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Voice", systemImage: "person.wave.2")
                .font(AppTypography.labelMedium(.semibold))
                .foregroundColor(AppColors.textSecondary)

            switch selectedProvider {
            case .apple, .kokoro, .mlxAudio:
                localTTSInfoCard
            case .openai:
                voiceCardGrid(
                    voices: OpenAITTSVoice.allCases.map { v in
                        VoiceCardData(id: v.rawValue, name: v.registryDisplayName, tone: v.registryToneDescription)
                    },
                    selectedId: selectedOpenAIVoice.rawValue,
                    onSelect: { id in
                        if let v = OpenAITTSVoice(rawValue: id) { selectedOpenAIVoice = v }
                    }
                )
            case .gemini:
                voiceCardGrid(
                    voices: GeminiTTSService.GeminiVoice.allCases.map { v in
                        VoiceCardData(id: v.rawValue, name: v.registryDisplayName, tone: v.registryToneDescription)
                    },
                    selectedId: selectedGeminiVoice.rawValue,
                    onSelect: { id in
                        if let v = GeminiTTSService.GeminiVoice(rawValue: id) { selectedGeminiVoice = v }
                    }
                )
            case .elevenlabs:
                elevenLabsVoicePicker
            }
        }
    }

    private var localTTSInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppColors.signalLichen)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(selectedProvider.displayName) is for reading messages aloud")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                Text("Switch to ElevenLabs, OpenAI, or Gemini to save audio files.")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.signalLichen.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.signalLichen.opacity(0.2), lineWidth: 1)
        )
    }

    private struct VoiceCardData {
        let id: String
        let name: String
        let tone: String?
    }

    private func voiceCardGrid(
        voices: [VoiceCardData],
        selectedId: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)],
            spacing: 8
        ) {
            ForEach(voices, id: \.id) { voice in
                VoiceCard(
                    name: voice.name,
                    tone: voice.tone,
                    isSelected: selectedId == voice.id,
                    accentColor: AppColors.signalLichen
                ) { onSelect(voice.id) }
            }
        }
    }

    private var elevenLabsVoicePicker: some View {
        Group {
            if settingsViewModel.availableVoices.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().scaleEffect(0.8).tint(AppColors.signalLichen)
                    Text("Loading voices…")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.substrateSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(settingsViewModel.availableVoices.prefix(12), id: \.id) { voice in
                        VoiceCard(
                            name: voice.name,
                            tone: nil,
                            isSelected: selectedElevenLabsVoiceId == voice.id,
                            accentColor: AppColors.signalLichen
                        ) {
                            selectedElevenLabsVoiceId = voice.id
                            selectedElevenLabsVoiceName = voice.name
                        }
                    }
                }
            }
        }
    }

    // MARK: - Voice Direction Section

    private var voiceDirectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Model picker for OpenAI
            if selectedProvider == .openai {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Model", systemImage: "cpu")
                        .font(AppTypography.labelMedium(.semibold))
                        .foregroundColor(AppColors.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(OpenAITTSModel.allCases, id: \.self) { model in
                            ProviderChip(
                                label: model.displayName,
                                isSelected: selectedOpenAIModel == model
                            ) { selectedOpenAIModel = model }
                        }
                        Spacer()
                    }

                    if !selectedOpenAIModel.supportsInstructions {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle").font(.system(size: 11))
                            Text("Voice direction requires GPT-4o Mini TTS")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(AppColors.textTertiary)
                    }
                }
            }

            // Direction field
            if selectedProvider == .gemini || (selectedProvider == .openai && selectedOpenAIModel.supportsInstructions) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Voice Direction", systemImage: "dial.medium")
                            .font(AppTypography.labelMedium(.semibold))
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Text("Optional")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColors.substrateTertiary)
                            .clipShape(Capsule())
                    }

                    TextField(
                        "e.g. Speak in a warm, conversational tone with slight British accent…",
                        text: $voiceDirection,
                        axis: .vertical
                    )
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(AppColors.substrateSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(AppColors.glassBorder, lineWidth: 1)
                    )

                    Text("Controls accent, emotion, pacing, and speaking style")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 14) {
            // Generate button
            Button { generateAudio() } label: {
                HStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "waveform.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isGenerating ? "Generating…" : "Generate Audio")
                        .font(AppTypography.bodyMedium(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Group {
                        if text.isEmpty || isGenerating {
                            AnyView(AppColors.substrateTertiary)
                        } else {
                            AnyView(
                                LinearGradient(
                                    colors: [AppColors.signalLichen, AppColors.signalLichenDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
                )
                .foregroundColor(text.isEmpty || isGenerating ? AppColors.textTertiary : .white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(
                    color: text.isEmpty ? .clear : AppColors.signalLichen.opacity(0.35),
                    radius: 10, x: 0, y: 5
                )
            }
            .disabled(text.isEmpty || isGenerating)
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)
                .font(.system(size: 14))
            Text(error)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.accentError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentError.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accentError.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func generateAudio() {
        errorMessage = nil
        isGenerating = true

        Task {
            do {
                let item: CreativeItem

                switch selectedProvider {
                case .apple:
                    throw DirectMediaError.generationFailed("Apple TTS is for reading messages aloud. Use ElevenLabs, OpenAI, or Gemini for audio file creation.")
                case .kokoro:
                    throw DirectMediaError.generationFailed("Kokoro TTS is for reading messages aloud. Use ElevenLabs, OpenAI, or Gemini for audio file creation.")
                case .mlxAudio:
                    throw DirectMediaError.generationFailed("MLX Neural TTS is for reading messages aloud. Use ElevenLabs, OpenAI, or Gemini for audio file creation.")
                case .openai:
                    let instructions = selectedOpenAIModel.supportsInstructions && !voiceDirection.isEmpty
                        ? voiceDirection : nil
                    item = try await creationService.generateAudioOpenAI(
                        text: text,
                        voice: selectedOpenAIVoice,
                        model: selectedOpenAIModel,
                        instructions: instructions
                    )
                case .gemini:
                    let direction = !voiceDirection.isEmpty ? voiceDirection : nil
                    item = try await creationService.generateAudioGemini(
                        text: text,
                        voice: selectedGeminiVoice,
                        direction: direction
                    )
                case .elevenlabs:
                    guard let voiceId = selectedElevenLabsVoiceId,
                          let voiceName = selectedElevenLabsVoiceName else {
                        throw DirectMediaError.generationFailed("No voice selected")
                    }
                    item = try await creationService.generateAudioElevenLabs(
                        text: text,
                        voiceId: voiceId,
                        voiceName: voiceName
                    )
                }

                await MainActor.run {
                    CostService.shared.recordTTSGeneration(provider: selectedProvider, characterCount: text.count)
                    generatedItem = item
                    isGenerating = false
                    showDetailSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Voice Card

private struct VoiceCard: View {
    let name: String
    let tone: String?
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                // Mini waveform icon
                HStack(spacing: 2) {
                    ForEach([8, 14, 10, 16, 8], id: \.self) { h in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isSelected ? accentColor : AppColors.textTertiary)
                            .frame(width: 3, height: CGFloat(h))
                    }
                }
                .padding(.bottom, 2)

                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? accentColor : AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let tone = tone {
                    Text(tone)
                        .font(.system(size: 9))
                        .foregroundColor(isSelected ? accentColor.opacity(0.75) : AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accentColor.opacity(0.1) : AppColors.substrateSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? accentColor.opacity(0.5) : AppColors.glassBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Provider Chip

private struct ProviderChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? AppColors.signalLichen : AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? AppColors.signalLichen.opacity(0.12) : AppColors.substrateSecondary)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? AppColors.signalLichen.opacity(0.4) : AppColors.glassBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
    }
}

#Preview {
    CreateAudioSheet()
}
