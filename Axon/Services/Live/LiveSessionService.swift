import SwiftUI
import AVFoundation
import Combine
import os.log

private let liveLog = Logger(subsystem: "com.axon.app", category: "LiveSession")

@MainActor
class LiveSessionService: ObservableObject, LiveProviderDelegate {
    static let shared = LiveSessionService()

    @Published var status: LiveSessionStatus = .idle
    @Published var isMicEnabled: Bool = true
    @Published var inputLevel: Float = 0.0
    @Published var outputLevel: Float = 0.0
    @Published var latestTranscript: String = ""
    
    private var provider: LiveProviderProtocol?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var playerNode: AVAudioPlayerNode?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {}
    
    func startSession(config: LiveSessionConfig, providerType: AIProvider) async {
        liveLog.info("startSession called with provider: \(providerType.displayName), model: \(config.modelId)")

        guard status == .idle || status == .disconnected else {
            liveLog.warning("startSession blocked - current status: \(String(describing: self.status))")
            return
        }

        status = .connecting
        liveLog.info("Status changed to connecting")

        // Retrieve API Key
        guard let apiProvider = providerType.apiProvider,
              let apiKey = SettingsViewModel.shared.getAPIKey(apiProvider), !apiKey.isEmpty else {
            liveLog.error("Missing API Key for \(providerType.displayName)")
            status = .error("Missing API Key for \(providerType.displayName)")
            return
        }
        liveLog.debug("API Key retrieved successfully")
        
        // Inject API Key into config
        let fullConfig = LiveSessionConfig(
            apiKey: apiKey,
            modelId: config.modelId,
            voice: config.voice,
            systemInstruction: config.systemInstruction,
            tools: config.tools
        )
        
        // Select provider
        switch providerType {
        case .gemini:
            liveLog.info("Creating GeminiLiveProvider")
            self.provider = GeminiLiveProvider()
        case .openai:
            liveLog.info("Creating OpenAILiveProvider")
            self.provider = OpenAILiveProvider()
        default:
            liveLog.error("Unsupported provider: \(providerType.displayName)")
            status = .error("Unsupported provider")
            return
        }

        self.provider?.delegate = self

        do {
            liveLog.info("Starting audio engine...")
            try await startAudioEngine()
            liveLog.info("Audio engine started successfully")

            liveLog.info("Connecting to provider...")
            try await self.provider?.connect(config: fullConfig)
            liveLog.info("Provider connection initiated")
            // status update handled by delegate
        } catch {
            liveLog.error("Connection failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            stopSession()
        }
    }
    
    func stopSession() {
        liveLog.info("stopSession called")
        provider?.disconnect()
        stopAudioEngine()
        status = .disconnected
        provider = nil
        liveLog.info("Session stopped and cleaned up")
    }

    func toggleMic() {
        isMicEnabled.toggle()
        liveLog.info("Mic toggled: \(self.isMicEnabled ? "enabled" : "disabled")")
    }

    private func startAudioEngine() async throws {
        liveLog.info("Initializing AVAudioEngine...")

        // Request microphone permission first
        liveLog.info("Requesting microphone permission...")
        let permissionGranted = await requestMicrophonePermission()
        guard permissionGranted else {
            liveLog.error("Microphone permission denied by user")
            throw NSError(domain: "LiveSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Please enable in Settings."])
        }
        liveLog.info("Microphone permission granted")

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            liveLog.error("Failed to create AVAudioEngine")
            return
        }

        liveLog.info("Getting input node...")
        inputNode = engine.inputNode
        playerNode = AVAudioPlayerNode()

        guard let input = inputNode, let player = playerNode else {
            liveLog.error("Failed to get inputNode or playerNode")
            return
        }

        liveLog.info("Attaching player node to engine...")
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)

        // Input Format (Hardware)
        let inputFormat = input.inputFormat(forBus: 0)
        liveLog.info("Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) ch, \(inputFormat.commonFormat.rawValue)")

        // Check for valid sample rate (0 Hz indicates microphone permission issue)
        guard inputFormat.sampleRate > 0 else {
            liveLog.error("Invalid input format - sample rate is 0. Check microphone permissions.")
            throw NSError(domain: "LiveSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied or unavailable. Please check permissions in Settings."])
        }

        liveLog.info("Installing tap on input node...")
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

        liveLog.info("Starting audio engine...")
        try engine.start()
        liveLog.info("Audio engine started")

        player.play()
        liveLog.info("Player node started")
    }

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        liveLog.info("Current microphone authorization status: \(status.rawValue)")

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            liveLog.info("Requesting microphone authorization...")
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            liveLog.warning("Microphone access denied or restricted")
            return false
        @unknown default:
            return false
        }
    }
    
    private func stopAudioEngine() {
        liveLog.info("Stopping audio engine...")
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        playerNode = nil
        liveLog.info("Audio engine stopped and cleaned up")
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
        liveLog.debug("Received audio data: \(data.count) bytes")
        playAudio(data: data)
    }

    func onTextDelta(_ text: String) {
        liveLog.debug("Text delta: \(text)")
        latestTranscript += text
    }

    func onTranscript(_ text: String, role: String) {
        liveLog.info("Transcript (\(role)): \(text)")
    }

    func onStatusChange(_ status: LiveSessionStatus) {
        liveLog.info("Status changed: \(String(describing: status))")
        self.status = status
    }

    func onError(_ error: Error) {
        liveLog.error("Provider error: \(error.localizedDescription)")
        self.status = .error(error.localizedDescription)
    }

    func onToolCall(name: String, args: [String : Any], id: String) {
        liveLog.info("Tool call received: \(name), id: \(id)")
    }
    
    // MARK: - Audio Playback

    private func playAudio(data: Data) {
        guard let player = playerNode, let engine = audioEngine else {
            liveLog.warning("playAudio called but player or engine is nil")
            return
        }

        // Assume 24kHz 1ch Int16 PCM (OpenAI/Gemini standard)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!

        if let buffer = data.toPCMBuffer(format: format) {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)

            // rudimentary level meter for output
            DispatchQueue.main.async {
                self.outputLevel = 0.5
                withAnimation(.linear(duration: 0.2)) {
                    self.outputLevel = 0.0
                }
            }
        } else {
            liveLog.warning("Failed to convert data to PCM buffer")
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
