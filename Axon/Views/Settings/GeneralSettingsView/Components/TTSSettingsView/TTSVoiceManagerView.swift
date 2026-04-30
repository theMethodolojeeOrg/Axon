//
//  TTSVoiceManagerView.swift
//  Axon
//
//  Universal TTS voice exploration and pinning view
//

import SwiftUI

/// A universal view for exploring and managing TTS voices across all providers
/// Modeled after KokoroVoiceManagerView but works with any TTS provider
struct TTSVoiceManagerView: View {
    let provider: TTSProvider
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var ttsService = TTSPlaybackService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Info banner
                SettingsInfoBanner(
                    icon: "star.fill",
                    text: "Pin your favorite voices to show them first in the picker. Tap preview to hear a voice sample."
                )

                // Pinned Voices Section
                if !pinnedVoices.isEmpty {
                    pinnedVoicesSection
                }

                // Female Voices Section
                if !femaleVoices.isEmpty {
                    voiceSection(title: "Female Voices", voices: femaleVoices)
                }

                // Male Voices Section
                if !maleVoices.isEmpty {
                    voiceSection(title: "Male Voices", voices: maleVoices)
                }

                // All/Other Voices (for voices without gender info)
                if !otherVoices.isEmpty {
                    voiceSection(title: "Other Voices", voices: otherVoices)
                }
            }
            .padding()
        }
        .background(AppSurfaces.color(.contentBackground))
        .navigationTitle("\(provider.displayName) Voices")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Voice Lists

    private var allVoices: [VoiceInfo] {
        switch provider {
        case .gemini:
            return GeminiTTSVoice.allCases.map { voice in
                VoiceInfo(
                    id: voice.rawValue,
                    displayName: voice.displayName,
                    description: voice.toneDescription,
                    gender: voice.gender
                )
            }
        case .openai:
            return OpenAITTSVoice.allCases.map { voice in
                VoiceInfo(
                    id: voice.rawValue,
                    displayName: voice.displayName,
                    description: voice.toneDescription,
                    gender: voice.gender
                )
            }
        case .apple:
            return AppleTTSVoice.allCases.map { voice in
                VoiceInfo(
                    id: voice.rawValue,
                    displayName: voice.displayName,
                    description: voice.displayName,
                    gender: voice.gender
                )
            }
        case .kokoro:
            return KokoroTTSVoice.allCases.map { voice in
                VoiceInfo(
                    id: voice.rawValue,
                    displayName: voice.registryDisplayName,
                    description: voice.registryDescription,
                    gender: voice.gender
                )
            }
        default:
            return []
        }
    }

    private var pinnedVoiceIds: [String] {
        viewModel.settings.ttsSettings.pinnedVoiceIds(for: provider)
    }

    private var pinnedVoices: [VoiceInfo] {
        let ids = pinnedVoiceIds
        return allVoices.filter { ids.contains($0.id) }
    }

    private var femaleVoices: [VoiceInfo] {
        allVoices.filter { $0.gender == .female && !pinnedVoiceIds.contains($0.id) }
    }

    private var maleVoices: [VoiceInfo] {
        allVoices.filter { $0.gender == .male && !pinnedVoiceIds.contains($0.id) }
    }

    private var otherVoices: [VoiceInfo] {
        allVoices.filter { $0.gender == nil && !pinnedVoiceIds.contains($0.id) }
    }

    // MARK: - Sections

    private var pinnedVoicesSection: some View {
        UnifiedSettingsSection(title: "⭐ Pinned Voices") {
            VStack(spacing: 8) {
                ForEach(pinnedVoices) { voice in
                    VoiceManagerRow(
                        voice: voice,
                        isPinned: true,
                        provider: provider,
                        settings: viewModel.settings,
                        onTogglePin: { togglePin(voice) },
                        onPreview: { await previewVoice(voice) }
                    )
                }
            }
        }
    }

    private func voiceSection(title: String, voices: [VoiceInfo]) -> some View {
        UnifiedSettingsSection(title: title) {
            VStack(spacing: 8) {
                ForEach(voices) { voice in
                    VoiceManagerRow(
                        voice: voice,
                        isPinned: false,
                        provider: provider,
                        settings: viewModel.settings,
                        onTogglePin: { togglePin(voice) },
                        onPreview: { await previewVoice(voice) }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func togglePin(_ voice: VoiceInfo) {
        Task {
            var settings = viewModel.settings.ttsSettings
            settings.togglePinnedVoice(voice.id, for: provider)
            await viewModel.updateTTSSetting(\.pinnedVoices, settings.pinnedVoices)
        }
    }

    private func previewVoice(_ voice: VoiceInfo) async {
        do {
            switch provider {
            case .gemini:
                if let geminiVoice = GeminiTTSVoice(rawValue: voice.id) {
                    try await ttsService.previewGeminiVoice(geminiVoice, settings: viewModel.settings)
                }
            case .openai:
                if let openaiVoice = OpenAITTSVoice(rawValue: voice.id) {
                    try await ttsService.previewOpenAIVoice(openaiVoice, settings: viewModel.settings)
                }
            case .apple:
                if let appleVoice = AppleTTSVoice(rawValue: voice.id) {
                    try await ttsService.previewAppleVoice(appleVoice, settings: viewModel.settings)
                }
            case .kokoro:
                if let kokoroVoice = KokoroTTSVoice(rawValue: voice.id) {
                    try await ttsService.previewKokoroVoice(kokoroVoice, settings: viewModel.settings)
                }
            default:
                break
            }
        } catch {
            debugLog(.ttsPlayback, "[TTSVoiceManagerView] Failed to preview voice: \(error)")
        }
    }
}

// MARK: - Voice Info Model

/// Generic voice info for all providers
struct VoiceInfo: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let gender: VoiceGender?
}

// MARK: - Voice Manager Row

private struct VoiceManagerRow: View {
    let voice: VoiceInfo
    let isPinned: Bool
    let provider: TTSProvider
    let settings: AppSettings
    let onTogglePin: () -> Void
    let onPreview: () async -> Void

    @StateObject private var ttsService = TTSPlaybackService.shared

    private var isPreviewingThisVoice: Bool {
        ttsService.currentMessageId == "preview_\(provider.rawValue)_\(voice.id)"
    }

    var body: some View {
        SettingsCard(padding: 12) {
            HStack(spacing: 12) {
                // Voice info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(voice.displayName)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if isPinned {
                            Text("Pinned")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentSuccess)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppColors.accentSuccess.opacity(0.15))
                                .cornerRadius(4)
                        }

                        if let gender = voice.gender {
                            Text(gender == .female ? "♀" : "♂")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    Text(voice.description)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    // Preview button
                    Button {
                        if isPreviewingThisVoice && (ttsService.isPlaying || ttsService.isGenerating) {
                            ttsService.stop()
                        } else {
                            Task { await onPreview() }
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
                        .frame(width: 32, height: 32)
                        .background(AppColors.signalMercury.opacity(0.15))
                        .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Pin/Unpin button
                    Button {
                        onTogglePin()
                    } label: {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundColor(isPinned ? AppColors.accentWarning : AppColors.signalMercury)
                            .frame(width: 32, height: 32)
                            .background((isPinned ? AppColors.accentWarning : AppColors.signalMercury).opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TTSVoiceManagerView(provider: .gemini, viewModel: SettingsViewModel())
    }
}
