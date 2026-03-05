//
//  VoiceSettingsSection.swift
//  Axon
//
//  Voice output settings for Live Voice mode
//

import SwiftUI

/// Section for TTS engine and voice selection
struct VoiceSettingsSection: View {
    @Binding var useOnDeviceModels: Bool
    @Binding var defaultProvider: AIProvider
    @Binding var openAIVoice: String
    @Binding var geminiVoice: String
    @Binding var fallbackTTSEngine: TTSEngine
    @Binding var defaultKokoroVoice: KokoroTTSVoice
    let popularKokoroVoices: [KokoroTTSVoice]

    var body: some View {
        Section {
            // Native voice picker for WebSocket providers
            if !useOnDeviceModels {
                switch defaultProvider {
                case .openai:
                    Picker("OpenAI Voice", selection: $openAIVoice) {
                        Text("Alloy").tag("alloy")
                        Text("Ash").tag("ash")
                        Text("Ballad").tag("ballad")
                        Text("Coral").tag("coral")
                        Text("Echo").tag("echo")
                        Text("Marin").tag("marin")
                        Text("Sage").tag("sage")
                        Text("Shimmer").tag("shimmer")
                        Text("Verse").tag("verse")
                    }
                case .gemini:
                    Picker("Gemini Voice", selection: $geminiVoice) {
                        Text("Aoede").tag("Aoede")
                        Text("Callirrhoe").tag("Callirrhoe")
                        Text("Charon").tag("Charon")
                        Text("Fenrir").tag("Fenrir")
                        Text("Kore").tag("Kore")
                        Text("Leda").tag("Leda")
                        Text("Orus").tag("Orus")
                        Text("Puck").tag("Puck")
                        Text("Zephyr").tag("Zephyr")
                    }
                default:
                    EmptyView()
                }
            }

            // TTS Engine (always shown - used for fallback or on-device)
            Picker("TTS Engine", selection: $fallbackTTSEngine) {
                ForEach(TTSEngine.allCases, id: \.self) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }

            if fallbackTTSEngine == .kokoro {
                Picker("Kokoro Voice", selection: $defaultKokoroVoice) {
                    ForEach(popularKokoroVoices, id: \.self) { voice in
                        Text(voice.displayName).tag(voice)
                    }
                }
            }
        } header: {
            Text("Voice Output")
        } footer: {
            if useOnDeviceModels || !hasNativeAudio(for: defaultProvider) {
                Text("Kokoro provides high-quality neural text-to-speech for AI responses.")
            } else {
                Text("Native voice is used for real-time providers. Kokoro is available as fallback.")
            }
        }
    }

    private func hasNativeAudio(for provider: AIProvider) -> Bool {
        provider == .gemini || provider == .openai
    }
}
