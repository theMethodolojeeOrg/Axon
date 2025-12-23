import SwiftUI
import AVFoundation
import Combine

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
        guard status == .idle || status == .disconnected else { return }
        
        status = .connecting
        
        // Retrieve API Key
        guard let apiProvider = providerType.apiProvider,
              let apiKey = SettingsViewModel.shared.getAPIKey(apiProvider), !apiKey.isEmpty else {
            print("LiveSessionService: Missing API Key for \(providerType)")
            status = .error("Missing API Key for \(providerType.displayName)")
            return
        }
        
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
             self.provider = GeminiLiveProvider()
        case .openai:
             self.provider = OpenAILiveProvider()
        default:
             // Fallback or error
             print("LiveSessionService: Unsupported provider \(providerType)")
             status = .error("Unsupported provider")
             return
        }
        
        self.provider?.delegate = self
        
        do {
            try await startAudioEngine()
            try await self.provider?.connect(config: fullConfig)
            // status update handled by delegate
        } catch {
            print("LiveSessionService: Connection failed - \(error)")
            status = .error(error.localizedDescription)
            stopSession()
        }
    }
    
    func stopSession() {
        provider?.disconnect()
        stopAudioEngine()
        status = .disconnected
        provider = nil
    }
    
    func toggleMic() {
        isMicEnabled.toggle()
        // Logic to mute input tap
    }
    
    private func startAudioEngine() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        inputNode = engine.inputNode
        playerNode = AVAudioPlayerNode()
        
        guard let input = inputNode, let player = playerNode else { return }
        
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        
        // Input Format (Hardware)
        let inputFormat = input.inputFormat(forBus: 0)
        
        // Install Tap
        // Note: OpenAI/Gemini expect ~24kHz mono usually. We might need downsampling.
        // For MVP, we send what we have or rely on provider wrapper to convert.
        // `GeminiLiveProvider` and `OpenAILiveProvider` currently expect PCM buffer.
        // We'll trust the provider to handle format or fail.
        // Ideally, we'd use a specific format for the tap, but inputNode tap must match hardware or be converted.
        
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
        
        try engine.start()
        player.play()
    }
    
    private func stopAudioEngine() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        playerNode = nil
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
        // Play audio
        playAudio(data: data)
    }
    
    func onTextDelta(_ text: String) {
        latestTranscript += text
    }
    
    func onTranscript(_ text: String, role: String) {
        // Could be used for history
    }
    
    func onStatusChange(_ status: LiveSessionStatus) {
        self.status = status
    }
    
    func onError(_ error: Error) {
        self.status = .error(error.localizedDescription)
    }
    
    func onToolCall(name: String, args: [String : Any], id: String) {
        // Handle tool call (placeholder)
        print("LiveSessionService: Tool Call - \(name)")
    }
    
    // MARK: - Audio Playback
    
    private func playAudio(data: Data) {
        guard let player = playerNode, let engine = audioEngine else { return }
        
        // Assume 24kHz 1ch Int16 PCM (OpenAI/Gemini standard)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: false)!
        
        if let buffer = data.toPCMBuffer(format: format) {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            
            // rudimentary level meter for output
            // (real implementation would tap the player output)
            DispatchQueue.main.async {
                self.outputLevel = 0.5 // visual feedback
                withAnimation(.linear(duration: 0.2)) {
                    self.outputLevel = 0.0
                }
            }
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
