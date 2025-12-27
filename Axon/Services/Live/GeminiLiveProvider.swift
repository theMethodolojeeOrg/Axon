import Foundation
import AVFoundation

class GeminiLiveProvider: LiveProviderProtocol {
    let id = "gemini"
    weak var delegate: LiveProviderDelegate?

    /// Gemini Live capabilities - native real-time duplex audio
    var capabilities: LiveProviderCapabilities {
        .geminiLive
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var isSetupComplete = false  // Wait for setupComplete before sending audio
    private let queue = DispatchQueue(label: "com.axon.gemini.live", qos: .userInitiated)

    // Config
    private var currentConfig: LiveSessionConfig?
    
    func connect(config: LiveSessionConfig) async throws {
        debugLog(.liveSession, "[GeminiLive] 🔌 connect() called with model: \(config.modelId)")
        self.currentConfig = config

        // Construct URL - Note: v1beta is required for Live API
        let baseUrl = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
        guard let url = URL(string: "\(baseUrl)?key=\(config.apiKey.prefix(8))...") else {
            debugLog(.liveSession, "[GeminiLive] ❌ Invalid URL construction")
            throw LiveSessionError.invalidURL
        }

        debugLog(.liveSession, "[GeminiLive] 🌐 Creating WebSocket...")
        let request = URLRequest(url: URL(string: "\(baseUrl)?key=\(config.apiKey)")!)
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)

        isConnected = true
        debugLog(.liveSession, "[GeminiLive] 📡 Calling delegate?.onStatusChange(.connecting)")
        await MainActor.run {
            delegate?.onStatusChange(.connecting)
        }

        webSocketTask?.resume()
        debugLog(.liveSession, "[GeminiLive] ▶️ WebSocket resumed")

        // Start receiving messages
        listen()

        // Give the WebSocket a moment to fully connect before sending setup
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Send Setup Message
        debugLog(.liveSession, "[GeminiLive] 📤 Sending setup message...")
        try await sendSetupMessage(config: config)

        debugLog(.liveSession, "[GeminiLive] ✅ Connection established successfully")
        await MainActor.run {
            delegate?.onStatusChange(.connected)
        }
    }

    func disconnect() {
        debugLog(.liveSession, "[GeminiLive] 🔴 disconnect() called")
        isConnected = false
        isSetupComplete = false  // Reset for next connection
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        debugLog(.liveSession, "[GeminiLive] 📡 Calling delegate?.onStatusChange(.disconnected)")
        DispatchQueue.main.async {
            self.delegate?.onStatusChange(.disconnected)
        }
    }
    
    func sendAudio(buffer: AVAudioPCMBuffer) {
        // Don't send audio until setup is complete - prevents flooding the socket
        guard isConnected, isSetupComplete, let task = webSocketTask else { return }

        // Convert to 16kHz Int16 PCM (Gemini requirement)
        guard let audioData = buffer.toGeminiFormat() else {
            debugLog(.liveSession, "[GeminiLive] Failed to convert audio to Gemini format")
            return
        }

        let base64Audio = audioData.base64EncodedString()

        // Construct JSON message - note the rate parameter in MIME type
        let messageDict: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "audio/pcm;rate=16000",
                        "data": base64Audio
                    ]
                ]
            ]
        ]

        sendJSON(messageDict)
    }
    
    func sendText(_ text: String) {
        guard isConnected else { return }
        
        let messageDict: [String: Any] = [
            "client_content": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "turn_complete": true
            ]
        ]
        
        sendJSON(messageDict)
    }
    
    func sendToolOutput(toolCallId: String, output: String) {
         guard isConnected else { return }
         // TODO: Implement proper tool response structure
    }
    
    // MARK: - Private Methods

    private func listen() {
        guard isConnected, let task = webSocketTask else {
            debugLog(.liveSession, "[GeminiLive] listen called but not connected or no task")
            return
        }

        task.receive { [weak self] result in
            guard let self = self, self.isConnected else {
                debugLog(.liveSession, "[GeminiLive] ⚠️ receive callback but not connected or self is nil")
                return
            }

            switch result {
            case .failure(let error):
                debugLog(.liveSession, "[GeminiLive] ❌ WebSocket receive error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.delegate?.onError(error)
                }
                self.disconnect()
            case .success(let message):
                self.handleMessage(message)
                self.listen()
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        var data: Data?

        switch message {
        case .string(let text):
            data = text.data(using: .utf8)
        case .data(let binaryData):
            data = binaryData
        @unknown default:
            break
        }

        guard let jsonData = data else {
            debugLog(.liveSession, "[GeminiLive] Received empty message")
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                // Log the top-level keys for debugging
                debugLog(.liveSession, "[GeminiLive] Received message keys: \(json.keys.joined(separator: ", "))")

                if let serverContent = json["serverContent"] as? [String: Any] {
                    if let modelTurn = serverContent["modelTurn"] as? [String: Any],
                       let parts = modelTurn["parts"] as? [[String: Any]] {
                        debugLog(.liveSession, "[GeminiLive] Processing \(parts.count) parts from model turn")
                        for part in parts {
                            if let text = part["text"] as? String {
                                debugLog(.liveSession, "[GeminiLive] Text part received: \(text.prefix(50))...")
                                DispatchQueue.main.async {
                                    self.delegate?.onTextDelta(text)
                                }
                            }
                            if let inlineData = part["inlineData"] as? [String: Any],
                               let mimeType = inlineData["mimeType"] as? String,
                               mimeType.hasPrefix("audio"),
                               let base64Data = inlineData["data"] as? String,
                               let audioData = Data(base64Encoded: base64Data) {
                                debugLog(.liveSession, "[GeminiLive] Audio data received: \(audioData.count) bytes")
                                DispatchQueue.main.async {
                                    self.delegate?.onAudioData(audioData)
                                }
                            }
                        }
                    }
                }

                if json["setupComplete"] != nil {
                    debugLog(.liveSession, "[GeminiLive] ✅ setupComplete received - now accepting audio")
                    self.isSetupComplete = true
                }

                if let error = json["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Unknown error"
                    debugLog(.liveSession, "[GeminiLive] Gemini API error: \(message)")
                }
            }
        } catch {
            debugLog(.liveSession, "[GeminiLive] JSON parse error: \(error.localizedDescription)")
        }
    }
    
    private func sendSetupMessage(config: LiveSessionConfig) async throws {
        // Model format must be "models/{model_id}" per API docs
        let modelPath = config.modelId.hasPrefix("models/") ? config.modelId : "models/\(config.modelId)"
        debugLog(.liveSession, "[GeminiLive] 📋 Sending setup with model: \(modelPath), voice: \(config.voice)")

        var messageDict: [String: Any] = [
            "setup": [
                "model": modelPath,
                "generation_config": [
                    "response_modalities": ["AUDIO"],
                    "speech_config": [
                        "voice_config": [
                            "prebuilt_voice_config": [
                                "voice_name": config.voice
                            ]
                        ]
                    ]
                ]
            ]
        ]

        if let systemInstruction = config.systemInstruction {
            debugLog(.liveSession, "[GeminiLive] Adding system instruction")
            if var setup = messageDict["setup"] as? [String: Any] {
                setup["system_instruction"] = [
                    "parts": [
                        ["text": systemInstruction]
                    ]
                ]
                messageDict["setup"] = setup
            }
        }

        sendJSON(messageDict)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let task = webSocketTask else {
            debugLog(.liveSession, "[GeminiLive] sendJSON called but no webSocketTask")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            debugLog(.liveSession, "[GeminiLive] Sending JSON message (\(data.count) bytes)")
            let message = URLSessionWebSocketTask.Message.data(data)
            task.send(message) { error in
                if let error = error {
                    debugLog(.liveSession, "[GeminiLive] Send error: \(error.localizedDescription)")
                }
            }
        } catch {
            debugLog(.liveSession, "[GeminiLive] JSON serialization error: \(error.localizedDescription)")
        }
    }
}

enum LiveSessionError: Error {
    case invalidURL
}

extension AVAudioPCMBuffer {
    /// Convert audio buffer to Gemini Live API format: 16kHz, Int16, mono, little-endian
    func toGeminiFormat() -> Data? {
        guard let floatData = self.floatChannelData else { return nil }

        let inputSampleRate = self.format.sampleRate
        let inputFrameLength = Int(self.frameLength)

        // Target: 16kHz
        let targetSampleRate: Double = 16000

        // Calculate output frame count after resampling
        let resampleRatio = targetSampleRate / inputSampleRate
        let outputFrameCount = Int(Double(inputFrameLength) * resampleRatio)

        // Get input samples (channel 0 only - mono)
        let inputSamples = UnsafeBufferPointer(start: floatData[0], count: inputFrameLength)

        // Resample using linear interpolation and convert Float32 → Int16
        var int16Samples = [Int16](repeating: 0, count: outputFrameCount)

        for i in 0..<outputFrameCount {
            // Map output index back to input
            let inputIndex = Double(i) / resampleRatio
            let index0 = Int(inputIndex)
            let index1 = min(index0 + 1, inputFrameLength - 1)
            let fraction = Float(inputIndex - Double(index0))

            // Linear interpolation
            let sample0 = inputSamples[index0]
            let sample1 = inputSamples[index1]
            let interpolatedSample = sample0 + (sample1 - sample0) * fraction

            // Clamp and convert to Int16 (-32768 to 32767)
            let clampedSample = max(-1.0, min(1.0, interpolatedSample))
            int16Samples[i] = Int16(clampedSample * 32767)
        }

        // Convert to Data (little-endian, which is native on Apple Silicon/Intel)
        return int16Samples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
    }

    /// Original toData for compatibility
    func toData() -> Data {
        let channels = UnsafeBufferPointer(start: self.floatChannelData, count: Int(self.format.channelCount))
        let ch0 = channels[0]
        let frameLength = Int(self.frameLength)
        let data = Data(bytes: ch0, count: frameLength * MemoryLayout<Float>.size)
        return data
    }
}
