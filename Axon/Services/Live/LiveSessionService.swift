import SwiftUI
import AVFoundation
import Combine

@MainActor
class LiveSessionService: ObservableObject, LiveProviderDelegate {
    static let shared = LiveSessionService()

    // MARK: - Published State

    @Published var status: LiveSessionStatus = .idle {
        didSet {
            debugLog(.liveSession, "Status changed: \(oldValue) → \(status)")
        }
    }
    @Published var isMicEnabled: Bool = true
    @Published var inputLevel: Float = 0.0
    @Published var outputLevel: Float = 0.0
    @Published var latestTranscript: String = ""

    /// Current execution mode (WebSocket, HTTP Streaming, or MLX)
    @Published var activeExecutionMode: ExecutionMode?

    /// Current provider capabilities
    @Published var currentCapabilities: LiveProviderCapabilities?

    /// Whether the noise gate is currently open (audio is passing through)
    @Published var isNoiseGateOpen: Bool = false

    /// Whether recording is enabled for this session
    @Published var isRecordingEnabled: Bool = true

    /// Current session recording (if any)
    @Published var currentRecording: LiveSessionRecording?

    /// Whether the assistant is currently speaking (for echo suppression)
    @Published private(set) var isAssistantSpeaking: Bool = false

    // MARK: - Private State

    private var provider: LiveProviderProtocol?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var playerNode: AVAudioPlayerNode?

    /// Noise gate for filtering background noise
    private let noiseGate = NoiseGate()

    /// Whether noise gate is enabled for this session
    private var noiseGateEnabled: Bool = true

    /// Track previous gate state to detect transitions
    private var wasNoiseGateOpen: Bool = false

    /// Timer for detecting when assistant stops speaking
    private var assistantSpeakingTimer: Timer?

    /// How long to wait after last audio before considering assistant done speaking (ms)
    private let assistantSpeakingTimeoutMs: Double = 300

    /// Thread service for conversation capture
    private let threadService = LiveSessionThreadService.shared

    /// Current provider info for recording
    private var currentProviderName: String = ""
    private var currentModelId: String = ""
    private var currentVoice: String = ""
    private var currentConversationId: String?

    /// Output audio format for playback (24kHz mono Int16 - Gemini/OpenAI standard)
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!

    private let factory = LiveProviderFactory.shared
    private var cancellables = Set<AnyCancellable>()

    init() {}
    
    // MARK: - Session Management

    /// Start a Live session with the specified provider and configuration
    /// - Parameters:
    ///   - config: Session configuration (model, voice, system instruction, etc.)
    ///   - providerType: The AI provider to use
    func startSession(config: LiveSessionConfig, providerType: AIProvider) async {
        debugLog(.liveSession, "startSession called with provider: \(providerType.displayName), model: \(config.modelId)")

        guard status == .idle || status == .disconnected else {
            debugLog(.liveSession, "startSession blocked - current status: \(String(describing: self.status))")
            return
        }

        status = .connecting
        latestTranscript = ""  // Reset transcript
        debugLog(.liveSession, "Status changed to connecting")

        // Configure noise gate from settings
        let liveSettings = SettingsViewModel.shared.settings.liveSettings
        noiseGateEnabled = liveSettings.noiseGateEnabled
        noiseGate.configure(from: liveSettings)
        noiseGate.reset()
        isNoiseGateOpen = false
        debugLog(.liveSession, "Noise gate configured: enabled=\(noiseGateEnabled), threshold=\(liveSettings.noiseGateThreshold)")

        // Store provider info for recording
        currentProviderName = providerType.rawValue
        currentModelId = config.modelId
        currentVoice = config.voice

        // Start recording if enabled
        if isRecordingEnabled {
            threadService.startSession(
                conversationId: currentConversationId,
                provider: currentProviderName,
                modelId: currentModelId,
                voice: currentVoice
            )
            debugLog(.liveSession, "Started session recording")
        }

        // Detect capabilities for this provider/model combination
        let capabilities = factory.detectCapabilities(for: providerType, modelId: config.modelId)
        currentCapabilities = capabilities
        activeExecutionMode = capabilities.executionMode
        debugLog(.liveSession, "Detected execution mode: \(capabilities.executionMode.displayName)")

        // Get API key (not needed for on-device)
        var apiKey = ""
        if capabilities.executionMode != .onDeviceMLX {
            guard let apiProvider = providerType.apiProvider,
                  let key = SettingsViewModel.shared.getAPIKey(apiProvider), !key.isEmpty else {
                debugLog(.liveSession, "Missing API Key for \(providerType.displayName)")
                status = .error("Missing API Key for \(providerType.displayName)")
                return
            }
            apiKey = key
            debugLog(.liveSession, "API Key retrieved successfully")
        }

        // Build full config with API key
        let fullConfig = LiveSessionConfig(
            apiKey: apiKey,
            modelId: config.modelId,
            voice: config.voice,
            systemInstruction: config.systemInstruction,
            tools: config.tools,
            executionMode: config.executionMode ?? capabilities.executionMode,
            latencyMode: config.latencyMode,
            useLocalVAD: config.useLocalVAD,
            useOnDeviceSTT: config.useOnDeviceSTT,
            fallbackTTSEngine: config.fallbackTTSEngine,
            fallbackTTSVoice: config.fallbackTTSVoice,
            mlxModelId: config.mlxModelId
        )

        do {
            // Create provider using factory
            debugLog(.liveSession, "Creating provider via factory...")
            self.provider = try factory.createProvider(
                for: providerType,
                modelId: config.modelId,
                config: fullConfig
            )
            self.provider?.delegate = self

            debugLog(.liveSession, "Starting audio engine...")
            try await startAudioEngine()
            debugLog(.liveSession, "Audio engine started successfully")

            debugLog(.liveSession, "Connecting to provider...")
            try await self.provider?.connect(config: fullConfig)
            debugLog(.liveSession, "Provider connection initiated")
            // status update handled by delegate
        } catch {
            debugLog(.liveSession, "❌ Connection failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            // Don't call stopSession() here - it sets status to .disconnected which hides the overlay
            // Instead, just clean up the provider
            provider?.disconnect()
            provider = nil
            activeExecutionMode = nil
            currentCapabilities = nil
        }
    }
    
    func stopSession() {
        debugLog(.liveSession, "stopSession called")
        provider?.disconnect()
        stopAudioEngine()

        // Clean up echo suppression timer
        assistantSpeakingTimer?.invalidate()
        assistantSpeakingTimer = nil
        isAssistantSpeaking = false

        // End recording and save
        Task {
            if let recording = await threadService.endSession() {
                currentRecording = recording
                debugLog(.liveSession, "Session recording saved with \(recording.turns.count) turns")
            }
        }

        status = .disconnected
        provider = nil
        activeExecutionMode = nil
        currentCapabilities = nil
        debugLog(.liveSession, "Session stopped and cleaned up")
    }

    /// Send text input to the current provider
    func sendText(_ text: String) {
        guard status == .connected else {
            debugLog(.liveSession, "Cannot send text - not connected")
            return
        }
        provider?.sendText(text)
    }

    func toggleMic() {
        isMicEnabled.toggle()
        debugLog(.liveSession, "Mic toggled: \(self.isMicEnabled ? "enabled" : "disabled")")
    }

    private func startAudioEngine() async throws {
        debugLog(.liveSession, "🎤 Initializing AVAudioEngine...")

        // Request microphone permission first
        debugLog(.liveSession, "Requesting microphone permission...")
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            debugLog(.liveSession, "❌ Microphone permission denied by user")
            throw NSError(domain: "LiveSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Please enable in Settings."])
        }
        debugLog(.liveSession, "✅ Microphone permission granted")

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            debugLog(.liveSession, "Failed to create AVAudioEngine")
            return
        }

        debugLog(.liveSession, "Getting input node...")
        inputNode = engine.inputNode
        playerNode = AVAudioPlayerNode()

        guard let input = inputNode, let player = playerNode else {
            debugLog(.liveSession, "Failed to get inputNode or playerNode")
            return
        }

        debugLog(.liveSession, "Attaching player node to engine...")
        engine.attach(player)
        // Connect with explicit 24kHz mono format for Gemini/OpenAI audio output
        engine.connect(player, to: engine.mainMixerNode, format: outputFormat)

        // Input Format (Hardware)
        let inputFormat = input.inputFormat(forBus: 0)
        debugLog(.liveSession, "Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch, \(inputFormat.commonFormat.rawValue)")

        // Check for valid sample rate (0 Hz indicates microphone permission issue)
        guard inputFormat.sampleRate > 0 else {
            debugLog(.liveSession, "Invalid input format - sample rate is 0. Check microphone permissions.")
            throw NSError(domain: "LiveSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied or unavailable. Please check permissions in Settings."])
        }

        debugLog(.liveSession, "Installing tap on input node...")
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, self.isMicEnabled else { return }

            // Calculate level for visualization
            let level = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.inputLevel = level
            }

            // ECHO SUPPRESSION: Don't send audio while assistant is speaking
            // This prevents the microphone from picking up speaker output and
            // sending it back to the model, which causes stuttering/interruptions
            if self.isAssistantSpeaking {
                return
            }

            // Apply noise gate if enabled
            if self.noiseGateEnabled {
                let shouldPass = self.noiseGate.shouldPass(buffer: buffer)
                let gateOpen = self.noiseGate.state == .open || self.noiseGate.state == .hold

                // Update gate state on main thread and detect transitions
                DispatchQueue.main.async {
                    // Detect rising edge: gate just opened (user started speaking)
                    if gateOpen && !self.wasNoiseGateOpen {
                        // User started speaking - finalize any pending assistant turn
                        if self.isRecordingEnabled {
                            self.threadService.onUserStartedSpeaking()
                        }
                    }
                    self.wasNoiseGateOpen = gateOpen

                    if self.isNoiseGateOpen != gateOpen {
                        self.isNoiseGateOpen = gateOpen
                    }
                }

                // Only send audio if gate is open
                if shouldPass {
                    self.provider?.sendAudio(buffer: buffer)

                    // Record user audio when transmitting
                    if self.isRecordingEnabled {
                        self.threadService.recordUserAudio(buffer: buffer)
                    }
                }
            } else {
                // No noise gate - send all audio
                self.provider?.sendAudio(buffer: buffer)

                // Record user audio
                if self.isRecordingEnabled {
                    self.threadService.recordUserAudio(buffer: buffer)
                }
            }
        }

        debugLog(.liveSession, "Starting audio engine...")
        try engine.start()
        debugLog(.liveSession, "Audio engine started")

        player.play()
        debugLog(.liveSession, "Player node started")
    }

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        debugLog(.liveSession, "Current microphone authorization status: \(status.rawValue)")

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            debugLog(.liveSession, "Requesting microphone authorization...")
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            debugLog(.liveSession, "Microphone access denied or restricted")
            return false
        @unknown default:
            return false
        }
    }
    
    private func stopAudioEngine() {
        debugLog(.liveSession, "Stopping audio engine...")
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        playerNode = nil
        debugLog(.liveSession, "Audio engine stopped and cleaned up")
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map{ channelDataValue[$0] }
        let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        return rms
    }
    
    // MARK: - LiveProviderDelegate

    func onAudioData(_ data: Data) {
        debugLog(.liveSession, "Received audio data: \(data.count) bytes")
        playAudio(data: data)

        // Mark assistant as speaking (for echo suppression)
        if !isAssistantSpeaking {
            isAssistantSpeaking = true
            debugLog(.liveSession, "Assistant started speaking - suppressing mic input")
        }

        // Reset the speaking timeout timer
        assistantSpeakingTimer?.invalidate()
        assistantSpeakingTimer = Timer.scheduledTimer(withTimeInterval: assistantSpeakingTimeoutMs / 1000.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isAssistantSpeaking = false
                debugLog(.liveSession, "Assistant stopped speaking - mic input enabled")
            }
        }

        // Record assistant audio
        if isRecordingEnabled {
            threadService.recordAssistantAudio(data: data)
        }
    }

    /// Called when assistant finishes speaking (audio playback queue empty or turn complete)
    func onAssistantTurnComplete() {
        debugLog(.liveSession, "Assistant turn complete")

        // Clear speaking state immediately on explicit turn complete
        assistantSpeakingTimer?.invalidate()
        assistantSpeakingTimer = nil
        isAssistantSpeaking = false

        if isRecordingEnabled {
            threadService.onAssistantAudioComplete()
        }
    }

    func onTextDelta(_ text: String) {
        debugLog(.liveSession, "Text delta: \(text)")
        latestTranscript += text

        // Record assistant transcript (streaming)
        if isRecordingEnabled {
            threadService.addAssistantTranscript(text, isFinal: false)
        }
    }

    func onTranscript(_ text: String, role: String) {
        debugLog(.liveSession, "Transcript (\(role)): \(text)")

        // Record transcripts
        if isRecordingEnabled {
            if role == "user" {
                threadService.addUserTranscript(text)
                threadService.finalizeUserTurn()
            } else if role == "assistant" {
                threadService.addAssistantTranscript(text, isFinal: true)
            }
        }
    }

    func onStatusChange(_ status: LiveSessionStatus) {
        debugLog(.liveSession, "Status changed: \(String(describing: status))")
        self.status = status
    }

    func onError(_ error: Error) {
        debugLog(.liveSession, "Provider error: \(error.localizedDescription)")
        self.status = .error(error.localizedDescription)
    }

    func onToolCall(name: String, args: [String : Any], id: String) {
        debugLog(.liveSession, "Tool call received: \(name), id: \(id)")
    }

    // MARK: - Recording Playback

    /// Play back the last recorded session
    func playLastRecording() {
        guard let recording = currentRecording else {
            debugLog(.liveSession, "No recording to play")
            return
        }
        threadService.playRecording(recording)
    }

    /// Stop playback
    func stopRecordingPlayback() {
        threadService.stopPlayback()
    }

    /// Toggle playback pause/resume
    func toggleRecordingPlayback() {
        threadService.togglePlayback()
    }

    /// Whether recording playback is active
    var isPlayingRecording: Bool {
        threadService.isPlaying
    }

    /// Playback progress (0.0 to 1.0)
    var recordingPlaybackProgress: Double {
        threadService.playbackProgress
    }

    /// Convert the last recording to a chat conversation
    func saveRecordingAsConversation() async throws -> Conversation? {
        guard let recording = currentRecording else { return nil }
        return try await threadService.convertToConversation(recording)
    }

    // MARK: - Audio Playback

    private func playAudio(data: Data) {
        guard let player = playerNode, let engine = audioEngine else {
            debugLog(.liveSession, "playAudio called but player or engine is nil")
            return
        }

        // Use the same format we connected the player with (24kHz mono Int16)
        if let buffer = data.toPCMBuffer(format: outputFormat) {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)

            // rudimentary level meter for output
            DispatchQueue.main.async {
                self.outputLevel = 0.5
                withAnimation(.linear(duration: 0.2)) {
                    self.outputLevel = 0.0
                }
            }
        } else {
            debugLog(.liveSession, "Failed to convert data to PCM buffer")
        }
    }
}

// Helper: Data -> AVAudioPCMBuffer
extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(self.count) / 2) else { return nil }
        buffer.frameLength = buffer.frameCapacity
        
        self.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
            if let int16ChannelData = buffer.int16ChannelData {
                let bytes = bufferPointer.bindMemory(to: Int16.self)
                // Copy data to channel 0
                // Note: Int16 channel data is MutablePointer<MutablePointer<Int16>>
                // We assume 1 channel
                if Int(format.channelCount) > 0 {
                    let channel0 = int16ChannelData[0]
                    // Safely copy
                    for i in 0..<Int(buffer.frameLength) {
                        if i < bytes.count {
                            channel0[i] = bytes[i]
                        }
                    }
                }
            }
        }
        return buffer
    }
}
