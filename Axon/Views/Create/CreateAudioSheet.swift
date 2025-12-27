//
//  CreateAudioSheet.swift
//  Axon
//
//  Sheet for generating audio via OpenAI/Gemini/ElevenLabs TTS.
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
    
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedItem: CreativeItem?
    @State private var showDetailSheet = false
    
    private var availableProviders: [TTSProvider] {
        creationService.availableTTSProviders
    }
    
    private var estimatedCost: Double {
        MediaCostEstimator.estimateTTSCost(provider: selectedProvider, characterCount: text.count)
    }
    
    var body: some View {
        #if os(macOS)
        // macOS: Direct content without NavigationStack to avoid sidebar-like behavior
        sheetContent
            .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 650)
            .onAppear {
                setupOnAppear()
            }
            .sheet(isPresented: $showDetailSheet) {
                if let item = generatedItem {
                    CreativeItemDetailView(item: item)
                }
            }
        #else
        // iOS: Keep NavigationStack for proper navigation
        NavigationStack {
            sheetContent
                .navigationTitle("Generate Audio")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(AppColors.textSecondary)
                    }
                }
                .sheet(isPresented: $showDetailSheet) {
                    if let item = generatedItem {
                        CreativeItemDetailView(item: item)
                    }
                }
        }
        .onAppear {
            setupOnAppear()
        }
        #endif
    }

    private func setupOnAppear() {
        // Set default provider to first available
        if let firstProvider = availableProviders.first {
            selectedProvider = firstProvider
        }

        // Load ElevenLabs voices if needed
        if creationService.hasElevenLabsKey {
            Task {
                await settingsViewModel.refreshElevenLabsCatalog()
                if let first = settingsViewModel.availableVoices.first {
                    selectedElevenLabsVoiceId = first.id
                    selectedElevenLabsVoiceName = first.name
                }
            }
        }
    }

    private var sheetContent: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    #if os(macOS)
                    // macOS header with title and cancel button
                    HStack {
                        Text("Generate Audio")
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(AppColors.textSecondary)
                    }
                    #endif

                    // Header
                    headerSection

                    // Text input
                    textSection

                    // Provider selection
                    if availableProviders.count > 1 {
                        providerSection
                    }

                    // Voice selection
                    voiceSection

                    // Generate button
                    generateButton

                    // Error display
                    if let error = errorMessage {
                        errorView(error)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundColor(AppColors.signalMercury)
            
            Text("Create with Text-to-Speech")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)
            
            Text("Enter text to convert to speech")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.top)
    }
    
    // MARK: - Text Section
    
    private var textSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Text")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
            
            TextEditor(text: $text)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(12)
                .background(AppColors.substrateSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
            
            HStack {
                Text("\(text.count) characters")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                
                Spacer()
                
                if text.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 12))
                        Text(MediaCostEstimator.formattedCost(estimatedCost))
                    }
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }
    
    // MARK: - Provider Section
    
    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
            
            Picker("Provider", selection: $selectedProvider) {
                ForEach(availableProviders, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
    
    // MARK: - Voice Section
    
    @ViewBuilder
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
            
            switch selectedProvider {
            case .apple:
                appleInfoView
            case .kokoro:
                kokoroInfoView
            case .mlxAudio:
                mlxInfoView
            case .openai:
                openAIVoicePicker
            case .gemini:
                geminiVoicePicker
            case .elevenlabs:
                elevenLabsVoicePicker
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
    
    private var openAIVoicePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OpenAITTSVoice.allCases, id: \.self) { voice in
                    VoiceChip(
                        name: voice.rawValue.capitalized,
                        isSelected: selectedOpenAIVoice == voice
                    ) {
                        selectedOpenAIVoice = voice
                    }
                }
            }
        }
    }

    private var appleInfoView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppColors.signalMercury)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple TTS is for reading messages")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                
                Text("For audio file creation, switch to ElevenLabs, OpenAI, or Gemini.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private var mlxInfoView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 4) {
                Text("MLX Neural TTS is for reading messages")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("For audio file creation, switch to ElevenLabs, OpenAI, or Gemini.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private var kokoroInfoView: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 4) {
                Text("Kokoro TTS is for reading messages")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("For audio file creation, switch to ElevenLabs, OpenAI, or Gemini.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
    
    private var geminiVoicePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GeminiTTSService.GeminiVoice.allCases, id: \.self) { voice in
                    VoiceChip(
                        name: voice.displayName,
                        subtitle: voice.toneDescription,
                        isSelected: selectedGeminiVoice == voice
                    ) {
                        selectedGeminiVoice = voice
                    }
                }
            }
        }
    }
    
    private var elevenLabsVoicePicker: some View {
        Group {
            if settingsViewModel.availableVoices.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading voices...")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(settingsViewModel.availableVoices.prefix(10), id: \.id) { voice in
                            VoiceChip(
                                name: voice.name,
                                isSelected: selectedElevenLabsVoiceId == voice.id
                            ) {
                                selectedElevenLabsVoiceId = voice.id
                                selectedElevenLabsVoiceName = voice.name
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button {
            generateAudio()
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "waveform")
                }
                
                Text(isGenerating ? "Generating..." : "Generate Audio")
                    .font(AppTypography.bodyMedium(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(text.isEmpty || isGenerating ? AppColors.textTertiary : AppColors.signalMercury)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(text.isEmpty || isGenerating)
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)
            
            Text(error)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.accentError)
        }
        .padding()
        .background(AppColors.accentError.opacity(0.1))
        .cornerRadius(12)
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
                    // Apple TTS is for in-chat TTS only, not for gallery audio creation
                    throw DirectMediaError.generationFailed("Apple TTS is available for reading messages aloud. For audio file creation, please use ElevenLabs, OpenAI, or Gemini.")
                case .kokoro:
                    // Kokoro TTS is for in-chat TTS only, not for gallery audio creation
                    throw DirectMediaError.generationFailed("Kokoro TTS is available for reading messages aloud. For audio file creation, please use ElevenLabs, OpenAI, or Gemini.")
                case .mlxAudio:
                    // MLX-Audio is for in-chat TTS only, not for gallery audio creation
                    throw DirectMediaError.generationFailed("MLX Neural TTS is available for reading messages aloud. For audio file creation, please use ElevenLabs, OpenAI, or Gemini.")
                case .openai:
                    item = try await creationService.generateAudioOpenAI(
                        text: text,
                        voice: selectedOpenAIVoice
                    )
                case .gemini:
                    item = try await creationService.generateAudioGemini(
                        text: text,
                        voice: selectedGeminiVoice
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
                    // Record cost
                    CostService.shared.recordTTSGeneration(provider: selectedProvider, characterCount: text.count)
                    generatedItem = item
                    isGenerating = false
                    // Automatically show the detail view
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

// MARK: - Voice Chip

private struct VoiceChip: View {
    let name: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(name)
                    .font(AppTypography.labelMedium())
                    .foregroundColor(isSelected ? .white : AppColors.textPrimary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : AppColors.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? AppColors.signalMercury : AppColors.substrateTertiary)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreateAudioSheet()
}
