import SwiftUI

/// Settings view for Native Live Mode configuration
struct NativeLiveSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            // Provider Mode Section
            providerModeSection

            // Provider-Specific Settings
            if viewModel.settings.liveSettings.useOnDeviceModels {
                onDeviceSettingsSection
            } else {
                cloudProviderSection
            }

            // Voice Activity Detection
            vadSection

            // Speech Recognition
            sttSection

            // Text-to-Speech Fallback
            ttsSection

            // Performance
            performanceSection
        }
        .navigationTitle("Native Live Mode")
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    // MARK: - Provider Mode Section

    private var providerModeSection: some View {
        Section {
            Toggle("Use On-Device Models", isOn: $viewModel.settings.liveSettings.useOnDeviceModels)

            if !viewModel.settings.liveSettings.useOnDeviceModels {
                Picker("Default Provider", selection: $viewModel.settings.liveSettings.defaultProvider) {
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
        } header: {
            Text("Provider Mode")
        } footer: {
            if viewModel.settings.liveSettings.useOnDeviceModels {
                Text("Live mode runs entirely on-device using MLX models. No internet required.")
            } else {
                Text("Native real-time providers (Gemini, OpenAI) have lowest latency. Others use STT/TTS.")
            }
        }
    }

    // MARK: - Cloud Provider Section

    private var cloudProviderSection: some View {
        Section {
            TextField("Model ID", text: $viewModel.settings.liveSettings.defaultModelId)
                .textFieldStyle(.roundedBorder)

            // Voice selection based on provider
            switch viewModel.settings.liveSettings.defaultProvider {
            case .gemini:
                Picker("Voice", selection: $viewModel.settings.liveSettings.geminiVoice) {
                    ForEach(geminiVoices, id: \.self) { voice in
                        Text(voice).tag(voice)
                    }
                }
            case .openai:
                Picker("Voice", selection: $viewModel.settings.liveSettings.openAIVoice) {
                    ForEach(openAIVoices, id: \.self) { voice in
                        Text(voice.capitalized).tag(voice)
                    }
                }
            default:
                // HTTP streaming providers use Kokoro voice
                EmptyView()
            }
        } header: {
            Text("Cloud Provider Settings")
        }
    }

    // MARK: - On-Device Settings Section

    private var onDeviceSettingsSection: some View {
        Section {
            Picker("MLX Model", selection: mlxModelBinding) {
                Text("Default (Gemma3)").tag("")
                // Add more models as they become available
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

    // MARK: - VAD Section

    private var vadSection: some View {
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
    }

    // MARK: - STT Section

    private var sttSection: some View {
        Section {
            Toggle("On-Device Speech Recognition", isOn: $viewModel.settings.liveSettings.useOnDeviceSTT)
        } header: {
            Text("Speech Recognition")
        } footer: {
            Text("Uses Apple's on-device speech recognition for privacy. Required for HTTP streaming providers.")
        }
    }

    // MARK: - TTS Section

    private var ttsSection: some View {
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
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
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

    // MARK: - Voice Lists

    private var geminiVoices: [String] {
        ["Aoede", "Callirrhoe", "Charon", "Fenrir", "Kore", "Leda", "Orus", "Puck", "Zephyr"]
    }

    private var openAIVoices: [String] {
        ["alloy", "ash", "ballad", "coral", "echo", "marin", "sage", "shimmer", "verse"]
    }

    private var popularKokoroVoices: [KokoroTTSVoice] {
        [.af_heart, .af_bella, .af_nova, .am_echo, .am_adam, .bf_emma, .bm_george]
    }

    private var availableMLXModels: [String] {
        // Return available downloaded models
        // This could be populated from MLXModelService
        []
    }
}


// MARK: - Preview

#Preview {
    NavigationStack {
        NativeLiveSettingsView(viewModel: SettingsViewModel.shared)
    }
}
