import SwiftUI

struct LiveVoiceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    // Local draft so we can persist changes through SettingsViewModel.updateSetting(...)
    @State private var draft: LiveSettings
    @State private var isHydratingDraft = true

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.settings.liveSettings)
    }

    var body: some View {
        Form {
            // MARK: - Mode Selection
            Section {
                Toggle("Use On-Device Models", isOn: $draft.useOnDeviceModels)
            } header: {
                Text("Mode")
            } footer: {
                if draft.useOnDeviceModels {
                    Text("Live mode runs entirely on-device using MLX models. No internet required.")
                } else {
                    Text("Use cloud providers for real-time voice conversations.")
                }
            }

            // MARK: - Provider Selection (Cloud Mode)
            if !draft.useOnDeviceModels {
                Section(header: Text("Default Provider")) {
                    Picker("Provider", selection: $draft.defaultProvider) {
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
                        executionModeBadge(for: draft.defaultProvider)
                    }
                }

                Section(header: Text("Model Configuration")) {
                    HStack {
                        Text("Model ID")
                        Spacer()
                        TextField("Model ID", text: $draft.defaultModelId)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 200)
                    }
                }

                Section(header: Text("Voices")) {
                    // Show voice picker based on provider
                    switch draft.defaultProvider {
                    case .openai:
                        Picker("Voice", selection: $draft.openAIVoice) {
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
                        Picker("Voice", selection: $draft.geminiVoice) {
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
            if draft.useOnDeviceModels {
                Section {
                    Picker("MLX Model", selection: mlxModelBinding) {
                        Text("Default (Gemma3)").tag("")
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
                Toggle("Local Voice Detection", isOn: $draft.useLocalVAD)

                if draft.useLocalVAD {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Sensitivity")
                            Spacer()
                            Text(sensitivityLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $draft.vadSensitivity,
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

            // MARK: - Noise Gate
            Section {
                Toggle("Noise Gate", isOn: $draft.noiseGateEnabled)

                if draft.noiseGateEnabled {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Threshold")
                            Spacer()
                            Text(noiseGateThresholdLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $draft.noiseGateThreshold,
                            in: 0.005...0.1,
                            step: 0.005
                        )
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Hold Time")
                            Spacer()
                            Text("\(draft.noiseGateHoldMs) ms")
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: noiseGateHoldBinding,
                            in: 50...500,
                            step: 50
                        )
                    }
                }
            } header: {
                Text("Noise Gate")
            } footer: {
                Text("Filters out background noise. Higher threshold blocks more ambient sounds but may cut off quiet speech.")
            }

            // MARK: - Speech Recognition
            Section {
                Toggle("On-Device Speech Recognition", isOn: $draft.useOnDeviceSTT)
            } header: {
                Text("Speech Recognition")
            } footer: {
                Text("Uses Apple's on-device speech recognition for privacy. Required for HTTP streaming providers.")
            }

            // MARK: - TTS Fallback
            Section {
                Picker("TTS Engine", selection: $draft.fallbackTTSEngine) {
                    ForEach(TTSEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                if draft.fallbackTTSEngine == .kokoro {
                    Picker("Voice", selection: $draft.defaultKokoroVoice) {
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
                Picker("Latency Mode", selection: $draft.latencyMode) {
                    ForEach(LatencyMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                Toggle("Prefer Native Real-time", isOn: $draft.preferRealtime)
            } header: {
                Text("Performance")
            } footer: {
                Text("Ultra mode minimizes latency but may reduce audio quality. Native real-time uses WebSocket for lowest latency.")
            }
        }
        .navigationTitle("Live Voice")
        // Keep draft in sync with viewModel (e.g., iCloud sync updates settings)
        .onAppear {
            // Avoid treating initial hydration as a user edit
            isHydratingDraft = true
            draft = viewModel.settings.liveSettings
            DispatchQueue.main.async { isHydratingDraft = false }
        }
        // Persist edits (debounced)
        .onChange(of: draft) { _, newValue in
            guard !isHydratingDraft else { return }
            persistDebounced(newValue)
        }
        #if os(macOS)
        .formStyle(.grouped)
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Helpers

    private var sensitivityLabel: String {
        let value = draft.vadSensitivity
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

    private var noiseGateThresholdLabel: String {
        let value = draft.noiseGateThreshold
        if value < 0.015 {
            return "Very Low"
        } else if value < 0.03 {
            return "Low"
        } else if value < 0.05 {
            return "Medium"
        } else if value < 0.07 {
            return "High"
        } else {
            return "Very High"
        }
    }

    private var noiseGateHoldBinding: Binding<Double> {
        Binding(
            get: { Double(draft.noiseGateHoldMs) },
            set: { draft.noiseGateHoldMs = Int($0) }
        )
    }

    // MARK: - Persistence

    /// Simple debounce so slider drags don’t spam disk/iCloud writes.
    private func persistDebounced(_ newValue: LiveSettings) {
        let token = UUID()
        pendingPersistToken = token

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms
            guard pendingPersistToken == token else { return }
            await viewModel.updateSetting(\.liveSettings, newValue)
        }
    }

    @State private var pendingPersistToken: UUID?

    private func executionModeBadge(for provider: AIProvider) -> some View {
        let mode = LiveProviderFactory.shared.detectCapabilities(
            for: provider,
            modelId: draft.defaultModelId
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
            get: { draft.preferredMLXModel ?? "" },
            set: { draft.preferredMLXModel = $0.isEmpty ? nil : $0 }
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
