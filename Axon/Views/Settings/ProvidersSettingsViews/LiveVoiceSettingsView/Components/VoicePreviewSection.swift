//
//  VoicePreviewSection.swift
//  Axon
//
//  Voice preview section for testing TTS output
//

import SwiftUI

/// Section for previewing TTS voice output with waveform visualization
struct VoicePreviewSection: View {
    @ObservedObject var voicePreviewController: VoicePreviewController
    @Binding var defaultKokoroVoice: KokoroTTSVoice
    @Binding var fallbackTTSEngine: TTSEngine

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Hear AI Voice")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(action: {
                        Task {
                            await voicePreviewController.playPreview(
                                voice: defaultKokoroVoice,
                                engine: fallbackTTSEngine
                            )
                        }
                    }) {
                        Image(systemName: voicePreviewController.isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .disabled(voicePreviewController.isLoading)
                }

                // Waveform visualization
                AudioWaveformView(
                    samples: voicePreviewController.waveformSamples,
                    progress: voicePreviewController.playbackProgress,
                    isPlaying: voicePreviewController.isPlaying
                )
                .frame(height: 44)

                if voicePreviewController.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Generating audio...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Voice Preview")
        } footer: {
            Text("Preview how the AI will sound during Live sessions.")
        }
    }
}
