import SwiftUI
import AVFoundation
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LiveVoiceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    // Local draft so we can persist changes through SettingsViewModel.updateSetting(...)
    @State private var draft: LiveSettings
    @State private var isHydratingDraft = true

    // Voice preview state (TTS playback)
    @StateObject private var voicePreviewController = VoicePreviewController()

    // Microphone preview state (live mic input visualization)
    @StateObject private var micPreviewController = MicrophonePreviewController()

    // Transcription test state
    @StateObject private var transcriptionTestController = TranscriptionTestController()

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
            }

            // MARK: - On-Device Model Selection
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

            // MARK: - Voice Settings (Combined Section)
            Section {
                // Native voice picker for WebSocket providers
                if !draft.useOnDeviceModels {
                    switch draft.defaultProvider {
                    case .openai:
                        Picker("OpenAI Voice", selection: $draft.openAIVoice) {
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
                        Picker("Gemini Voice", selection: $draft.geminiVoice) {
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
                Picker("TTS Engine", selection: $draft.fallbackTTSEngine) {
                    ForEach(TTSEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }

                if draft.fallbackTTSEngine == .kokoro {
                    Picker("Kokoro Voice", selection: $draft.defaultKokoroVoice) {
                        ForEach(popularKokoroVoices, id: \.self) { voice in
                            Text(voice.displayName).tag(voice)
                        }
                    }
                }
            } header: {
                Text("Voice Output")
            } footer: {
                if draft.useOnDeviceModels || !hasNativeAudio(for: draft.defaultProvider) {
                    Text("Kokoro provides high-quality neural text-to-speech for AI responses.")
                } else {
                    Text("Native voice is used for real-time providers. Kokoro is available as fallback.")
                }
            }

            // MARK: - Voice Preview (TTS Playback)
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Hear AI Voice")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(action: {
                            Task {
                                await voicePreviewController.playPreview(
                                    voice: draft.defaultKokoroVoice,
                                    engine: draft.fallbackTTSEngine
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

            // MARK: - Microphone Preview (Live Input Visualization)
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Test Microphone")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(action: {
                            if micPreviewController.isListening {
                                micPreviewController.stopListening()
                            } else {
                                micPreviewController.startListening(
                                    noiseGateEnabled: draft.noiseGateEnabled,
                                    noiseGateThreshold: draft.noiseGateThreshold
                                )
                            }
                        }) {
                            Image(systemName: micPreviewController.isListening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(micPreviewController.isListening ? Color.red : Color.accentColor))
                        }
                        .buttonStyle(.plain)
                    }

                    // Live waveform visualization
                    LiveWaveformView(
                        samples: micPreviewController.waveformSamples,
                        isActive: micPreviewController.isListening,
                        isGateOpen: micPreviewController.isNoiseGateOpen
                    )
                    .frame(height: 60)

                    // Status indicators
                    if micPreviewController.isListening {
                        HStack(spacing: 16) {
                            // Noise gate indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(micPreviewController.isNoiseGateOpen ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                Text(micPreviewController.isNoiseGateOpen ? "Transmitting" : "Gate Closed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Peak level
                            Text("Level: \(Int(micPreviewController.peakLevel * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Microphone Preview")
            } footer: {
                Text("See how your microphone input looks to the AI. The noise gate filters out background sounds.")
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

            // MARK: - Test Transcription
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Test Transcription")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button(action: {
                            if transcriptionTestController.isListening {
                                transcriptionTestController.stopListening()
                            } else {
                                transcriptionTestController.startListening()
                            }
                        }) {
                            Image(systemName: transcriptionTestController.isListening ? "stop.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(transcriptionTestController.isListening ? Color.red : Color.accentColor))
                        }
                        .buttonStyle(.plain)
                    }

                    // Transcript display
                    if !transcriptionTestController.transcript.isEmpty || transcriptionTestController.isListening {
                        Text(transcriptionTestController.transcript.isEmpty ? "Listening..." : transcriptionTestController.transcript)
                            .font(.body)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            #if os(macOS)
                            .background(Color(NSColor.controlBackgroundColor))
                            #else
                            .background(Color(.secondarySystemBackground))
                            #endif
                            .cornerRadius(8)
                            .foregroundColor(transcriptionTestController.transcript.isEmpty ? .secondary : .primary)
                    }

                    // Mic level indicator when listening
                    if transcriptionTestController.isListening {
                        HStack(spacing: 4) {
                            ForEach(0..<10, id: \.self) { index in
                                Capsule()
                                    .fill(index < Int(transcriptionTestController.audioLevel * 10) ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 4, height: 16)
                            }
                        }
                    }
                }
            } header: {
                Text("Speech Recognition Test")
            } footer: {
                Text("Test how your voice is transcribed using Apple's on-device speech recognition.")
            }

            // MARK: - Speech Recognition Settings
            Section {
                Toggle("On-Device Speech Recognition", isOn: $draft.useOnDeviceSTT)
            } header: {
                Text("Speech Recognition")
            } footer: {
                Text("Uses Apple's on-device speech recognition for privacy. Required for HTTP streaming providers.")
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
        .onDisappear {
            voicePreviewController.stop()
            micPreviewController.stopListening()
            transcriptionTestController.stopListening()
        }
        #if os(macOS)
        .formStyle(.grouped)
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Helpers

    private func hasNativeAudio(for provider: AIProvider) -> Bool {
        provider == .gemini || provider == .openai
    }

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

    /// Simple debounce so slider drags don't spam disk/iCloud writes.
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

// MARK: - Voice Preview Controller (TTS Playback)

@MainActor
class VoicePreviewController: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var playbackProgress: Double = 0
    @Published var waveformSamples: [Float] = Array(repeating: 0.3, count: 50)

    private var audioPlayer: AVAudioPlayer?
    private var displayLink: Timer?
    private var playerDelegate: AudioPlayerDelegateWrapper?

    private let previewText = "Hello! I'm your AI assistant. How can I help you today?"

    func playPreview(voice: KokoroTTSVoice, engine: TTSEngine) async {
        if isPlaying {
            stop()
            return
        }

        guard engine == .kokoro else {
            // System TTS preview
            await playSystemTTSPreview()
            return
        }

        isLoading = true

        do {
            let ttsService = KokoroTTSService.shared

            // Generate speech
            let audioData = try await ttsService.generateSpeech(
                text: previewText,
                voice: voice,
                speed: 1.0
            )

            // Generate waveform samples from audio
            waveformSamples = generateWaveformSamples(from: audioData)

            // Play audio
            audioPlayer = try AVAudioPlayer(data: audioData)
            playerDelegate = AudioPlayerDelegateWrapper { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.stopDisplayLink()
                }
            }
            audioPlayer?.delegate = playerDelegate
            audioPlayer?.play()
            isPlaying = true
            isLoading = false

            startDisplayLink()
        } catch {
            print("[AudioPreview] Error: \(error.localizedDescription)")
            isLoading = false
        }
    }

    private func playSystemTTSPreview() async {
        #if os(macOS)
        let synthesizer = NSSpeechSynthesizer()
        synthesizer.startSpeaking(previewText)
        #else
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: previewText)
        synthesizer.speak(utterance)
        #endif

        // Generate placeholder waveform
        waveformSamples = (0..<50).map { _ in Float.random(in: 0.2...0.8) }
        isPlaying = true

        // Approximate duration
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        isPlaying = false
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        playerDelegate = nil
        isPlaying = false
        playbackProgress = 0
        stopDisplayLink()
    }

    private func startDisplayLink() {
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.playbackProgress = player.currentTime / player.duration
            }
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        playbackProgress = 0
    }

    private func generateWaveformSamples(from data: Data) -> [Float] {
        // Simple waveform extraction - sample amplitude at regular intervals
        let sampleCount = 50
        var samples: [Float] = []

        // Treat data as Int16 samples
        let int16Count = data.count / 2
        guard int16Count > 0 else { return Array(repeating: 0.3, count: sampleCount) }

        let step = max(1, int16Count / sampleCount)

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for i in stride(from: 0, to: min(int16Count, sampleCount * step), by: step) {
                let sample = Float(abs(int16Buffer[i])) / 32768.0
                samples.append(min(1.0, sample * 2)) // Amplify for visibility
            }
        }

        // Ensure we have enough samples
        while samples.count < sampleCount {
            samples.append(0.3)
        }

        return samples
    }
}

// MARK: - Audio Player Delegate Wrapper

private class AudioPlayerDelegateWrapper: NSObject, AVAudioPlayerDelegate {
    let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion()
    }
}

// MARK: - Microphone Preview Controller (Live Input Visualization)

@MainActor
class MicrophonePreviewController: ObservableObject {
    @Published var isListening = false
    @Published var waveformSamples: [Float] = Array(repeating: 0.0, count: 64)
    @Published var peakLevel: Float = 0
    @Published var isNoiseGateOpen = false

    private var audioEngine: AVAudioEngine?
    private var noiseGateEnabled = true
    private var noiseGateThreshold: Float = 0.02
    private var sampleIndex = 0

    func startListening(noiseGateEnabled: Bool, noiseGateThreshold: Float) {
        self.noiseGateEnabled = noiseGateEnabled
        self.noiseGateThreshold = Float(noiseGateThreshold)

        do {
            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            // Install tap for audio visualization
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                Task { @MainActor in
                    self?.processAudioBuffer(buffer)
                }
            }

            try engine.start()
            isListening = true
            waveformSamples = Array(repeating: 0.0, count: 64)
            sampleIndex = 0
        } catch {
            print("[MicPreview] Error starting audio engine: \(error.localizedDescription)")
        }
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false
        peakLevel = 0
        isNoiseGateOpen = false
        waveformSamples = Array(repeating: 0.0, count: 64)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        // Calculate RMS level
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        peakLevel = min(1.0, rms * 5) // Amplify for visibility

        // Check noise gate
        if noiseGateEnabled {
            isNoiseGateOpen = rms > noiseGateThreshold
        } else {
            isNoiseGateOpen = true
        }

        // Update waveform samples (rolling buffer)
        let normalizedLevel = min(1.0, rms * 8) // Amplify for visualization
        waveformSamples[sampleIndex % 64] = normalizedLevel
        sampleIndex += 1

        // Shift samples for scrolling effect
        if sampleIndex >= 64 {
            waveformSamples = Array(waveformSamples.dropFirst()) + [normalizedLevel]
        }
    }
}

// MARK: - Live Waveform View (Scrolling Mic Input)

struct LiveWaveformView: View {
    let samples: [Float]
    let isActive: Bool
    let isGateOpen: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 1) {
                ForEach(0..<samples.count, id: \.self) { index in
                    let sample = samples.indices.contains(index) ? samples[index] : 0.0
                    let barHeight = max(2, CGFloat(sample) * geometry.size.height)

                    Capsule()
                        .fill(barColor(for: sample))
                        .frame(
                            width: max(2, (geometry.size.width - CGFloat(samples.count)) / CGFloat(samples.count)),
                            height: barHeight
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? (isGateOpen ? Color.green.opacity(0.5) : Color.gray.opacity(0.3)) : Color.clear, lineWidth: 2)
                )
        )
        .animation(.easeOut(duration: 0.05), value: samples)
    }

    private func barColor(for sample: Float) -> Color {
        if !isActive {
            return Color.gray.opacity(0.3)
        }

        if !isGateOpen {
            return Color.gray.opacity(0.5)
        }

        // Color gradient based on level
        if sample > 0.8 {
            return Color.red
        } else if sample > 0.5 {
            return Color.orange
        } else if sample > 0.2 {
            return Color.green
        } else {
            return Color.green.opacity(0.7)
        }
    }
}

// MARK: - Transcription Test Controller

@MainActor
class TranscriptionTestController: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private let speechService = SpeechRecognitionService.shared

    func startListening() {
        Task {
            // Request authorization if needed
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                transcript = "Speech recognition not authorized. Please enable in Settings."
                return
            }

            do {
                // Setup audio engine
                audioEngine = AVAudioEngine()
                guard let engine = audioEngine else { return }

                let inputNode = engine.inputNode
                let format = inputNode.outputFormat(forBus: 0)

                // Start speech recognition
                try speechService.startRecognition()

                // Install tap for audio level and recognition
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                    Task { @MainActor in
                        // Update audio level
                        self?.updateAudioLevel(buffer: buffer)
                    }

                    // Send to speech recognition
                    self?.speechService.appendAudio(buffer: buffer)
                }

                try engine.start()
                isListening = true
                transcript = ""

                // Listen for transcript updates
                speechService.onTranscriptUpdate = { [weak self] text, isFinal in
                    Task { @MainActor in
                        self?.transcript = text
                    }
                }
            } catch {
                transcript = "Error: \(error.localizedDescription)"
            }
        }
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        speechService.stopRecognition()
        isListening = false
        audioLevel = 0
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        audioLevel = min(1.0, rms * 5) // Amplify for visibility
    }
}

// MARK: - Audio Waveform View

struct AudioWaveformView: View {
    let samples: [Float]
    let progress: Double
    let isPlaying: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<samples.count, id: \.self) { index in
                    let sample = samples.indices.contains(index) ? samples[index] : 0.3
                    let progressIndex = Int(progress * Double(samples.count))
                    let isPast = index < progressIndex

                    Capsule()
                        .fill(isPast ? Color.accentColor : Color.accentColor.opacity(0.3))
                        .frame(width: max(2, (geometry.size.width - CGFloat(samples.count) * 2) / CGFloat(samples.count)),
                               height: CGFloat(sample) * geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.2), Color.orange.opacity(0.2), Color.red.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .cornerRadius(8)
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LiveVoiceSettingsView(viewModel: SettingsViewModel.shared)
    }
}
