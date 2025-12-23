import Foundation
import AVFoundation

class GeminiLiveProvider: LiveProviderProtocol {
    let id = "gemini"
    weak var delegate: LiveProviderDelegate?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private let queue = DispatchQueue(label: "com.axon.gemini.live", qos: .userInitiated)
    
    // Config
    private var currentConfig: LiveSessionConfig?
    
    func connect(config: LiveSessionConfig) async throws {
        self.currentConfig = config
        
        // Construct URL
        let baseUrl = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"
        guard let url = URL(string: "\(baseUrl)?key=\(config.apiKey)") else {
            throw LiveSessionError.invalidURL
        }
        
        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        
        isConnected = true
        delegate?.onStatusChange(.connecting)
        
        webSocketTask?.resume()
        
        // Start receiving messages
        listen()
        
        // Send Setup Message
        try await sendSetupMessage(config: config)
        
        delegate?.onStatusChange(.connected)
    }
    
    func disconnect() {
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        delegate?.onStatusChange(.disconnected)
    }
    
    func sendAudio(buffer: AVAudioPCMBuffer) {
        guard isConnected, let task = webSocketTask else { return }
        
        // Convert PCM buffer to Data
        let audioData = buffer.toData()
        let base64Audio = audioData.base64EncodedString()
        
        // Construct JSON message
        let messageDict: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "audio/pcm",
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
        guard isConnected, let task = webSocketTask else { return }
        
        task.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }
            
            switch result {
            case .failure(let error):
                print("GeminiLiveProvider: Receive error: \(error)")
                self.delegate?.onError(error)
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
        
        guard let jsonData = data else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if let serverContent = json["serverContent"] as? [String: Any] {
                    if let modelTurn = serverContent["modelTurn"] as? [String: Any],
                       let parts = modelTurn["parts"] as? [[String: Any]] {
                        for part in parts {
                            if let text = part["text"] as? String {
                                DispatchQueue.main.async {
                                    self.delegate?.onTextDelta(text)
                                }
                            }
                            if let inlineData = part["inlineData"] as? [String: Any],
                               let mimeType = inlineData["mimeType"] as? String,
                               mimeType.hasPrefix("audio"),
                               let base64Data = inlineData["data"] as? String,
                               let audioData = Data(base64Encoded: base64Data) {
                                DispatchQueue.main.async {
                                    self.delegate?.onAudioData(audioData)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("GeminiLiveProvider: Parse error: \(error)")
        }
    }
    
    private func sendSetupMessage(config: LiveSessionConfig) async throws {
        var messageDict: [String: Any] = [
            "setup": [
                "model": config.modelId,
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
        guard let task = webSocketTask else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            let message = URLSessionWebSocketTask.Message.data(data)
            task.send(message) { error in
                if let error = error {
                    print("GeminiLiveProvider: Send JSON error: \(error)")
                }
            }
        } catch {
            print("GeminiLiveProvider: Serialization error: \(error)")
        }
    }
}

enum LiveSessionError: Error {
    case invalidURL
}

extension AVAudioPCMBuffer {
    func toData() -> Data {
        let channelCount = 1
        let channels = UnsafeBufferPointer(start: self.floatChannelData, count: Int(self.format.channelCount))
        let ch0 = channels[0]
        let frameLength = Int(self.frameLength)
        let data = Data(bytes: ch0, count: frameLength * MemoryLayout<Float>.size)
        return data
    }
}
