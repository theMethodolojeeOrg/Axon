import Foundation
import AVFoundation

class OpenAILiveProvider: LiveProviderProtocol {
    let id = "openai"
    weak var delegate: LiveProviderDelegate?
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    
    // Config
    private var currentConfig: LiveSessionConfig?
    
    func connect(config: LiveSessionConfig) async throws {
        self.currentConfig = config
        
        // Construct URL
        let model = config.modelId.isEmpty ? "gpt-4o-realtime-preview-2024-10-01" : config.modelId
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else {
            throw LiveSessionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        
        isConnected = true
        delegate?.onStatusChange(.connecting)
        
        webSocketTask?.resume()
        listen()
        
        // Wait for session.created (handled in listen), or send session.update immediately
        // We'll send session.update to set voice and instructions
        try await sendSessionUpdate(config: config)
        
        delegate?.onStatusChange(.connected)
    }
    
    func disconnect() {
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        delegate?.onStatusChange(.disconnected)
    }
    
    func sendAudio(buffer: AVAudioPCMBuffer) {
        guard isConnected else { return }
        
        // OpenAI expects base64 encoded PCM16 24kHz mono by default
        // We need to ensure we are sending compatible data.
        // For now, wrapping raw pcm.
        let audioData = buffer.toData()
        let base64 = audioData.base64EncodedString()
        
        let event: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64
        ]
        
        sendJSON(event)
    }
    
    func sendText(_ text: String) {
        // Send as text message or interruption
        // item.create
        /*
        {
            "type": "conversation.item.create",
            "item": {
                "type": "message",
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": text
                    }
                ]
            }
        }
        */
        guard isConnected else { return }
        
        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": text
                    ]
                ]
            ]
        ]
        sendJSON(event)
        
        // Trigger response
        let responseEvent: [String: Any] = ["type": "response.create"]
        sendJSON(responseEvent)
    }
    
    func sendToolOutput(toolCallId: String, output: String) {
        guard isConnected else { return }
        
        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": toolCallId,
                "output": output
            ]
        ]
        sendJSON(event)
        
        // Trigger response
        let responseEvent: [String: Any] = ["type": "response.create"]
        sendJSON(responseEvent)
    }
    
    // MARK: - Private
    
    private func listen() {
        guard isConnected, let task = webSocketTask else { return }
        
        task.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }
            
            switch result {
            case .failure(let error):
                print("OpenAILiveProvider: Error \(error)")
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
        case .string(let text): data = text.data(using: .utf8)
        case .data(let binary): data = binary
        @unknown default: break
        }
        
        guard let jsonData = data else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                guard let type = json["type"] as? String else { return }
                
                switch type {
                case "error":
                    if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                        print("OpenAI Error: \(message)")
                        delegate?.onError(NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
                    }
                case "session.created":
                    print("OpenAI Session Created")
                    
                case "response.audio.delta":
                    if let delta = json["delta"] as? String,
                       let audioData = Data(base64Encoded: delta) {
                        DispatchQueue.main.async {
                            self.delegate?.onAudioData(audioData)
                        }
                    }
                    
                case "response.text.delta":
                    if let delta = json["delta"] as? String {
                         DispatchQueue.main.async {
                             self.delegate?.onTextDelta(delta)
                         }
                    }
                    
                case "response.function_call_arguments.done":
                    // Tool call handling
                    // logic to accumulate arguments would be needed for streaming args
                    // or wait for "response.done" or "item.created" with function_call
                    break
                    
                default:
                    break
                }
            }
        } catch {
            print("OpenMJSON Error: \(error)")
        }
    }
    
    private func sendSessionUpdate(config: LiveSessionConfig) async throws {
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "voice": config.voice,
                "instructions": config.systemInstruction ?? "You are a helpful AI assistant."
            ]
        ]
        sendJSON(event)
    }
    
    private func sendJSON(_ dict: [String: Any]) {
        guard let task = webSocketTask else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            let message = URLSessionWebSocketTask.Message.data(data)
            task.send(message) { error in
                if let error = error {
                    print("OpenAI Send Error: \(error)")
                }
            }
        } catch {
            print("OpenAI JSON Error: \(error)")
        }
    }
}
