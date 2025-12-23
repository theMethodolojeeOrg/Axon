import Foundation
import AVFoundation

/// Protocol for real-time AI providers (Gemini Live, OpenAI Realtime)
protocol LiveProviderProtocol: AnyObject {
    var id: String { get }
    var delegate: LiveProviderDelegate? { get set }
    
    /// Connect to the provider's WebSocket
    func connect(config: LiveSessionConfig) async throws
    
    /// Disconnect
    func disconnect()
    
    /// Send audio data (PCM) to the model
    func sendAudio(buffer: AVAudioPCMBuffer)
    
    /// Send text input (interruption or message)
    func sendText(_ text: String)
    
    /// Send tool execution output back to the model
    func sendToolOutput(toolCallId: String, output: String)
}

/// Delegate for receiving events from the provider
protocol LiveProviderDelegate: AnyObject {
    func onAudioData(_ data: Data)
    func onTextDelta(_ text: String)
    func onTranscript(_ text: String, role: String)
    func onStatusChange(_ status: LiveSessionStatus)
    func onError(_ error: Error)
    func onToolCall(name: String, args: [String: Any], id: String)
}

struct LiveSessionConfig {
    let apiKey: String
    let modelId: String
    let voice: String
    let systemInstruction: String?
    // We'll use a simplified tool representation or link to existing ToolDefinition if accessible
    // For now, flexible dictionary or existing struct
    let tools: [ToolDefinition]? 
}

enum LiveSessionStatus: Equatable {
    case idle
    case connecting
    case connected
    case disconnected
    case error(String)
    
    static func == (lhs: LiveSessionStatus, rhs: LiveSessionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.connecting, .connecting), (.connected, .connected), (.disconnected, .disconnected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}
