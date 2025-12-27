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

    // MARK: - Private State

    private var provider: LiveProviderProtocol?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var playerNode: AVAudioPlayerNode?

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

            // Calculate level
            let level = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.inputLevel = level
            }

            // Send to provider
            self.provider?.sendAudio(buffer: buffer)
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
    }

    func onTextDelta(_ text: String) {
        debugLog(.liveSession, "Text delta: \(text)")
        latestTranscript += text
    }

    func onTranscript(_ text: String, role: String) {
        debugLog(.liveSession, "Transcript (\(role)): \(text)")
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
