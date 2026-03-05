//
//  KokoroVoiceManagerView.swift
//  Axon
//
//  Manage Kokoro TTS voice downloads
//

import SwiftUI

struct KokoroVoiceManagerView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var kokoroService = KokoroTTSService.shared
    @StateObject private var ttsService = TTSPlaybackService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Info banner
                SettingsInfoBanner(
                    icon: "waveform.badge.plus",
                    text: "Download additional voices for Kokoro TTS. Built-in voices are always available. Each voice is approximately 500KB."
                )

                // Built-in voices section
                builtInVoicesSection

                // American Female voices
                voiceSection(
                    title: "American Female",
                    voices: KokoroTTSVoice.allCases.filter { $0.accent == .american && $0.gender == .female && !$0.isBuiltIn }
                )

                // American Male voices
                voiceSection(
                    title: "American Male",
                    voices: KokoroTTSVoice.allCases.filter { $0.accent == .american && $0.gender == .male && !$0.isBuiltIn }
                )

                // British Female voices
                voiceSection(
                    title: "British Female",
                    voices: KokoroTTSVoice.allCases.filter { $0.accent == .british && $0.gender == .female }
                )

                // British Male voices
                voiceSection(
                    title: "British Male",
                    voices: KokoroTTSVoice.allCases.filter { $0.accent == .british && $0.gender == .male }
                )
            }
            .padding()
        }
        .background(AppColors.substratePrimary)
        .navigationTitle("Manage Voices")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Built-in Voices Section

    private var builtInVoicesSection: some View {
        UnifiedSettingsSection(title: "Built-in Voices") {
            VStack(spacing: 8) {
                ForEach(KokoroTTSVoice.builtInVoices) { voice in
                    VoiceManagementRow(
                        voice: voice,
                        isAvailable: kokoroService.isVoiceAvailable(voice),
                        downloadProgress: kokoroService.voiceDownloadProgress[voice.rawValue],
                        settings: viewModel.settings,
                        onDownload: { },
                        onDelete: { },
                        onPreview: { await previewVoice(voice) }
                    )
                }
            }
        }
    }

    // MARK: - Voice Section

    private func voiceSection(title: String, voices: [KokoroTTSVoice]) -> some View {
        UnifiedSettingsSection(title: title) {
            VStack(spacing: 8) {
                ForEach(voices) { voice in
                    VoiceManagementRow(
                        voice: voice,
                        isAvailable: kokoroService.isVoiceAvailable(voice),
                        downloadProgress: kokoroService.voiceDownloadProgress[voice.rawValue],
                        settings: viewModel.settings,
                        onDownload: { await downloadVoice(voice) },
                        onDelete: { deleteVoice(voice) },
                        onPreview: { await previewVoice(voice) }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func downloadVoice(_ voice: KokoroTTSVoice) async {
        do {
            try await kokoroService.downloadVoice(voice)
            // Update settings to track downloaded voice
            var downloaded = viewModel.settings.ttsSettings.downloadedKokoroVoices
            downloaded.insert(voice.rawValue)
            await viewModel.updateTTSSetting(\.downloadedKokoroVoices, downloaded)
        } catch {
            debugLog(.ttsPlayback, "[KokoroVoiceManagerView] Failed to download voice: \(error)")
        }
    }

    private func deleteVoice(_ voice: KokoroTTSVoice) {
        do {
            try kokoroService.deleteVoice(voice)
            // Update settings to remove downloaded voice
            var downloaded = viewModel.settings.ttsSettings.downloadedKokoroVoices
            downloaded.remove(voice.rawValue)
            Task { await viewModel.updateTTSSetting(\.downloadedKokoroVoices, downloaded) }
        } catch {
            debugLog(.ttsPlayback, "[KokoroVoiceManagerView] Failed to delete voice: \(error)")
        }
    }

    private func previewVoice(_ voice: KokoroTTSVoice) async {
        do {
            try await ttsService.previewKokoroVoice(voice, settings: viewModel.settings)
        } catch {
            debugLog(.ttsPlayback, "[KokoroVoiceManagerView] Failed to preview voice: \(error)")
        }
    }
}

// MARK: - Voice Management Row

private struct VoiceManagementRow: View {
    let voice: KokoroTTSVoice
    let isAvailable: Bool
    let downloadProgress: Double?
    let settings: AppSettings
    let onDownload: () async -> Void
    let onDelete: () -> Void
    let onPreview: () async -> Void

    @StateObject private var ttsService = TTSPlaybackService.shared
    @State private var isDownloading = false
    @State private var error: String?

    private var isPreviewingThisVoice: Bool {
        ttsService.currentMessageId == "preview_kokoro_\(voice.rawValue)"
    }

    var body: some View {
        SettingsCard(padding: 12) {
            HStack(spacing: 12) {
                // Voice info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(voice.registryDisplayName)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if voice.isBuiltIn {
                            Text("Built-in")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentSuccess)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppColors.accentSuccess.opacity(0.15))
                                .cornerRadius(4)
                        } else if isAvailable {
                            Text("Downloaded")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalMercury)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppColors.signalMercury.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }

                    Text(voice.registryDescription)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)

                    if let error = error {
                        Text(error)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.accentWarning)
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    // Preview button (only if available)
                    if isAvailable {
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
                    }

                    // Download/Delete button
                    if voice.isBuiltIn {
                        // Built-in voices can't be deleted
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.accentSuccess)
                            .frame(width: 32, height: 32)
                    } else if let progress = downloadProgress, progress < 1.0 {
                        // Downloading
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                            .frame(width: 32, height: 32)
                    } else if isAvailable {
                        // Delete button
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.accentWarning)
                                .frame(width: 32, height: 32)
                                .background(AppColors.accentWarning.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Download button
                        Button {
                            isDownloading = true
                            error = nil
                            Task {
                                await onDownload()
                                isDownloading = false
                            }
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.signalMercury)
                                .frame(width: 32, height: 32)
                                .background(AppColors.signalMercury.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isDownloading)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        KokoroVoiceManagerView(viewModel: SettingsViewModel())
    }
}
