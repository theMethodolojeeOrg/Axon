import Foundation
import AVFoundation
import os.log

private let openAILog = Logger(subsystem: "com.axon.app", category: "OpenAILive")

class OpenAILiveProvider: LiveProviderProtocol {
    let id = "openai"
    weak var delegate: LiveProviderDelegate?

    /// OpenAI Realtime capabilities - native real-time duplex audio
    var capabilities: LiveProviderCapabilities {
        .openAIRealtime
    }

    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false

    // Config
    private var currentConfig: LiveSessionConfig?
    
    func connect(config: LiveSessionConfig) async throws {
        openAILog.info("connect called with model: \(config.modelId)")
        self.currentConfig = config

        // Construct URL
        let model = config.modelId.isEmpty ? "gpt-4o-realtime-preview-2024-10-01" : config.modelId
        openAILog.info("Using model: \(model)")

        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)") else {
            openAILog.error("Invalid URL for model: \(model)")
            throw LiveSessionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        openAILog.info("Creating WebSocket connection...")
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)

        isConnected = true
        delegate?.onStatusChange(.connecting)

        webSocketTask?.resume()
        openAILog.info("WebSocket resumed, starting listener...")
        listen()

        // Send session.update to set voice and instructions
        openAILog.info("Sending session update...")
        try await sendSessionUpdate(config: config)

        openAILog.info("Connection established successfully")
        delegate?.onStatusChange(.connected)
    }

    func disconnect() {
        openAILog.info("disconnect called")
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        delegate?.onStatusChange(.disconnected)
        openAILog.info("Disconnected")
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
        guard isConnected, let task = webSocketTask else {
            openAILog.warning("listen called but not connected or no task")
            return
        }

        task.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }

            switch result {
            case .failure(let error):
                openAILog.error("WebSocket receive error: \(error.localizedDescription)")
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

        guard let jsonData = data else {
            openAILog.warning("Received empty message")
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                guard let type = json["type"] as? String else {
                    openAILog.warning("Message missing 'type' field")
                    return
                }

                openAILog.debug("Received message type: \(type)")

                switch type {
                case "error":
                    if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                        openAILog.error("OpenAI API error: \(message)")
                        delegate?.onError(NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: message]))
                    }
                case "session.created":
                    openAILog.info("Session created successfully")

                case "response.audio.delta":
                    if let delta = json["delta"] as? String,
                       let audioData = Data(base64Encoded: delta) {
                        DispatchQueue.main.async {
                            self.delegate?.onAudioData(audioData)
                        }
                    }

                case "response.text.delta":
                    if let delta = json["delta"] as? String {
                        openAILog.debug("Text delta received: \(delta.prefix(50))...")
                        DispatchQueue.main.async {
                            self.delegate?.onTextDelta(delta)
                        }
                    }

                case "response.function_call_arguments.done":
                    openAILog.info("Function call arguments complete")
                    break

                default:
                    openAILog.debug("Unhandled message type: \(type)")
                    break
                }
            }
        } catch {
            openAILog.error("JSON parse error: \(error.localizedDescription)")
        }
    }
    
    private func sendSessionUpdate(config: LiveSessionConfig) async throws {
        openAILog.info("Sending session update with voice: \(config.voice)")
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
        guard let task = webSocketTask else {
            openAILog.warning("sendJSON called but no webSocketTask")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            if let type = dict["type"] as? String {
                openAILog.debug("Sending message type: \(type)")
            }
            let message = URLSessionWebSocketTask.Message.data(data)
            task.send(message) { error in
                if let error = error {
                    openAILog.error("Send error: \(error.localizedDescription)")
                }
            }
        } catch {
            openAILog.error("JSON serialization error: \(error.localizedDescription)")
        }
    }
}
