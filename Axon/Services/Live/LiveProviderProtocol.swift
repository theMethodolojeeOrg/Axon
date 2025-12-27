import Foundation
import AVFoundation

/// Protocol for real-time AI providers (Gemini Live, OpenAI Realtime, HTTP Streaming, MLX)
protocol LiveProviderProtocol: AnyObject {
    /// Unique identifier for this provider
    var id: String { get }

    /// Delegate for receiving events
    var delegate: LiveProviderDelegate? { get set }

    /// The capabilities of this provider
    var capabilities: LiveProviderCapabilities { get }

    /// Connect to the provider
    func connect(config: LiveSessionConfig) async throws

    /// Disconnect from the provider
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
    /// Received audio data from the model
    func onAudioData(_ data: Data)

    /// Received a text delta (streaming response)
    func onTextDelta(_ text: String)

    /// Received a transcript (user or assistant speech)
    func onTranscript(_ text: String, role: String)

    /// Session status changed
    func onStatusChange(_ status: LiveSessionStatus)

    /// An error occurred
    func onError(_ error: Error)

    /// Model requested a tool call
    func onToolCall(name: String, args: [String: Any], id: String)
}

// MARK: - Session Configuration

/// Configuration for a Live session
struct LiveSessionConfig {
    // MARK: Core Configuration

    /// API key for the provider (empty for on-device)
    let apiKey: String

    /// Model identifier
    let modelId: String

    /// Voice name for TTS
    let voice: String

    /// System instruction/prompt
    let systemInstruction: String?

    /// Available tools for function calling
    let tools: [ToolDefinition]?

    // MARK: Universal Mode Configuration

    /// Explicit execution mode (nil = auto-detect from provider)
    var executionMode: ExecutionMode?

    /// Latency vs quality trade-off
    var latencyMode: LatencyMode

    /// Use local voice activity detection
    var useLocalVAD: Bool

    /// Use on-device speech-to-text
    var useOnDeviceSTT: Bool

    /// TTS engine for non-native audio providers
    var fallbackTTSEngine: TTSEngine

    /// Kokoro voice for TTS fallback
    var fallbackTTSVoice: KokoroTTSVoice?

    /// MLX model ID for on-device mode
    var mlxModelId: String?

    // MARK: Initialization

    /// Full initializer with all options
    init(
        apiKey: String,
        modelId: String,
        voice: String,
        systemInstruction: String? = nil,
        tools: [ToolDefinition]? = nil,
        executionMode: ExecutionMode? = nil,
        latencyMode: LatencyMode = .balanced,
        useLocalVAD: Bool = true,
        useOnDeviceSTT: Bool = true,
        fallbackTTSEngine: TTSEngine = .kokoro,
        fallbackTTSVoice: KokoroTTSVoice? = .af_heart,
        mlxModelId: String? = nil
    ) {
        self.apiKey = apiKey
        self.modelId = modelId
        self.voice = voice
        self.systemInstruction = systemInstruction
        self.tools = tools
        self.executionMode = executionMode
        self.latencyMode = latencyMode
        self.useLocalVAD = useLocalVAD
        self.useOnDeviceSTT = useOnDeviceSTT
        self.fallbackTTSEngine = fallbackTTSEngine
        self.fallbackTTSVoice = fallbackTTSVoice
        self.mlxModelId = mlxModelId
    }

    /// Convenience initializer for backward compatibility
    init(
        apiKey: String,
        modelId: String,
        voice: String,
        systemInstruction: String?,
        tools: [ToolDefinition]?
    ) {
        self.init(
            apiKey: apiKey,
            modelId: modelId,
            voice: voice,
            systemInstruction: systemInstruction,
            tools: tools,
            executionMode: nil,
            latencyMode: .balanced,
            useLocalVAD: true,
            useOnDeviceSTT: true,
            fallbackTTSEngine: .kokoro,
            fallbackTTSVoice: .af_heart,
            mlxModelId: nil
        )
    }
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
