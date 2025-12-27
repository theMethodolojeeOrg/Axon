import SwiftUI

struct LiveVoiceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            // MARK: - Mode Selection
            Section {
                Toggle("Use On-Device Models", isOn: $viewModel.settings.liveSettings.useOnDeviceModels)
            } header: {
                Text("Mode")
            } footer: {
                if viewModel.settings.liveSettings.useOnDeviceModels {
                    Text("Live mode runs entirely on-device using MLX models. No internet required.")
                } else {
                    Text("Use cloud providers for real-time voice conversations.")
                }
            }

            // MARK: - Provider Selection (Cloud Mode)
            if !viewModel.settings.liveSettings.useOnDeviceModels {
                Section(header: Text("Default Provider")) {
                    Picker("Provider", selection: $viewModel.settings.liveSettings.defaultProvider) {
                        Text("Gemini Live").tag(AIProvider.gemini)
                        Text("OpenAI Realtime").tag(AIProvider.openai)
                        Text("Anthropic").tag(AIProvider.anthropic)
                        Text("xAI (Grok)").tag(AIProvider.xai)
                        Text("Perplexity").tag(AIProvider.perplexity)
                        Text("DeepSeek").tag(AIProvider.deepseek)
                    }

                    // Show execution mode indicator
                    HStack {
                        Text("Mode")
                        Spacer()
                        executionModeBadge(for: viewModel.settings.liveSettings.defaultProvider)
                    }
                }

                Section(header: Text("Model Configuration")) {
                    HStack {
                        Text("Model ID")
                        Spacer()
                        TextField("Model ID", text: $viewModel.settings.liveSettings.defaultModelId)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 200)
                    }
                }

                Section(header: Text("Voices")) {
                    // Show voice picker based on provider
                    switch viewModel.settings.liveSettings.defaultProvider {
                    case .openai:
                        Picker("Voice", selection: $viewModel.settings.liveSettings.openAIVoice) {
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
                        Picker("Voice", selection: $viewModel.settings.liveSettings.geminiVoice) {
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
                        // HTTP streaming providers use Kokoro TTS
                        Text("Uses Kokoro TTS for voice output")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - On-Device Settings
            if viewModel.settings.liveSettings.useOnDeviceModels {
                Section {
                    Picker("MLX Model", selection: mlxModelBinding) {
                        Text("Default (Qwen3-VL)").tag("")
                        ForEach(availableMLXModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } header: {
                    Text("On-Device Model")
                } footer: {
                    Text("Select the MLX model to use for on-device Live mode.")
                }
            }

            // MARK: - Voice Activity Detection
            Section {
                Toggle("Local Voice Detection", isOn: $viewModel.settings.liveSettings.useLocalVAD)

                if viewModel.settings.liveSettings.useLocalVAD {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Sensitivity")
                            Spacer()
                            Text(sensitivityLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $viewModel.settings.liveSettings.vadSensitivity,
                            in: 0...1,
                            step: 0.1
                        )
                    }
                }
            } header: {
                Text("Voice Activity Detection")
            } footer: {
                Text("Local VAD detects when you start and stop speaking. Higher sensitivity picks up quieter speech.")
            }

            // MARK: - Speech Recognition
            Section {
                Toggle("On-Device Speech Recognition", isOn: $viewModel.settings.liveSettings.useOnDeviceSTT)
            } header: {
                Text("Speech Recognition")
            } footer: {
                Text("Uses Apple's on-device speech recognition for privacy. Required for HTTP streaming providers.")
            }

            // MARK: - TTS Fallback
            Section {
                Picker("TTS Engine", selection: $viewModel.settings.liveSettings.fallbackTTSEngine) {
                    ForEach(TTSEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                if viewModel.settings.liveSettings.fallbackTTSEngine == .kokoro {
                    Picker("Voice", selection: $viewModel.settings.liveSettings.defaultKokoroVoice) {
                        ForEach(popularKokoroVoices, id: \.self) { voice in
                            Text(voice.displayName).tag(voice)
                        }
                    }
                }
            } header: {
                Text("Text-to-Speech Fallback")
            } footer: {
                Text("Used for providers without native audio output (Anthropic, xAI, etc.)")
            }

            // MARK: - Performance
            Section {
                Picker("Latency Mode", selection: $viewModel.settings.liveSettings.latencyMode) {
                    ForEach(LatencyMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Prefer Native Real-time", isOn: $viewModel.settings.liveSettings.preferRealtime)
            } header: {
                Text("Performance")
            } footer: {
                Text("Ultra mode minimizes latency but may reduce audio quality. Native real-time uses WebSocket for lowest latency.")
            }
        }
        .navigationTitle("Live Voice")
        #if os(macOS)
        .formStyle(.grouped)
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Helpers

    private var sensitivityLabel: String {
        let value = viewModel.settings.liveSettings.vadSensitivity
        if value < 0.3 {
            return "Very Sensitive"
        } else if value < 0.5 {
            return "Sensitive"
        } else if value < 0.7 {
            return "Balanced"
        } else {
            return "Less Sensitive"
        }
    }

    private func executionModeBadge(for provider: AIProvider) -> some View {
        let mode = LiveProviderFactory.shared.detectCapabilities(
            for: provider,
            modelId: viewModel.settings.liveSettings.defaultModelId
        ).executionMode

        return Text(mode.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(modeColor(for: mode).opacity(0.2))
            .foregroundColor(modeColor(for: mode))
            .cornerRadius(8)
    }

    private func modeColor(for mode: ExecutionMode) -> Color {
        switch mode {
        case .cloudWebSocket:
            return .green
        case .cloudHTTPStreaming:
            return .blue
        case .onDeviceMLX:
            return .purple
        }
    }

    private var mlxModelBinding: Binding<String> {
        Binding(
            get: { viewModel.settings.liveSettings.preferredMLXModel ?? "" },
            set: { viewModel.settings.liveSettings.preferredMLXModel = $0.isEmpty ? nil : $0 }
        )
    }

    private var popularKokoroVoices: [KokoroTTSVoice] {
        [.af_heart, .af_bella, .af_nova, .am_echo, .am_adam, .bf_emma, .bm_george]
    }

    private var availableMLXModels: [String] {
        // Return available downloaded models from settings
        viewModel.settings.userMLXModels
            .filter { $0.downloadStatus == .downloaded }
            .map { $0.repoId }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LiveVoiceSettingsView(viewModel: SettingsViewModel.shared)
    }
}
