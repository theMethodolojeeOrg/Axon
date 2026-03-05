import Foundation

// MARK: - Execution Mode

/// Defines how a Live provider executes - WebSocket, HTTP streaming, or on-device
enum ExecutionMode: String, Codable, CaseIterable, Sendable {
    /// Native duplex WebSocket (Gemini Live, OpenAI Realtime)
    case cloudWebSocket = "cloudWebSocket"

    /// Standard HTTP streaming chat APIs (Anthropic, OpenAI non-realtime, etc.)
    case cloudHTTPStreaming = "cloudHTTPStreaming"

    /// On-device MLX models (fully offline)
    case onDeviceMLX = "onDeviceMLX"

    var displayName: String {
        switch self {
        case .cloudWebSocket:
            return "Real-time"
        case .cloudHTTPStreaming:
            return "Streaming"
        case .onDeviceMLX:
            return "On-Device"
        }
    }

    var description: String {
        switch self {
        case .cloudWebSocket:
            return "Full duplex WebSocket for lowest latency"
        case .cloudHTTPStreaming:
            return "HTTP streaming with local STT/TTS"
        case .onDeviceMLX:
            return "Fully offline using local MLX models"
        }
    }
}

// MARK: - Latency Mode

/// Controls the trade-off between latency and quality
enum LatencyMode: String, Codable, CaseIterable, Sendable {
    /// Minimize latency (may reduce quality)
    case ultra = "ultra"

    /// Default balanced mode
    case balanced = "balanced"

    /// Maximize quality (may increase latency)
    case quality = "quality"

    var displayName: String {
        switch self {
        case .ultra:
            return "Ultra Low Latency"
        case .balanced:
            return "Balanced"
        case .quality:
            return "High Quality"
        }
    }

    /// Silence threshold in milliseconds before ending utterance
    var silenceThresholdMs: Int {
        switch self {
        case .ultra:
            return 300
        case .balanced:
            return 500
        case .quality:
            return 800
        }
    }
}

// MARK: - TTS Engine

/// Available text-to-speech engines
enum TTSEngine: String, Codable, CaseIterable, Sendable {
    /// On-device Kokoro neural TTS
    case kokoro = "kokoro"

    /// Apple's AVSpeechSynthesizer
    case system = "system"

    /// No TTS (text-only mode)
    case none = "none"

    var displayName: String {
        switch self {
        case .kokoro:
            return "Kokoro (Neural)"
        case .system:
            return "System Voice"
        case .none:
            return "Text Only"
        }
    }

    var description: String {
        switch self {
        case .kokoro:
            return "High-quality on-device neural TTS"
        case .system:
            return "Apple's built-in speech synthesis"
        case .none:
            return "Disable audio output, show text only"
        }
    }
}

// MARK: - Audio Format

/// Supported audio formats for Live providers
enum AudioFormat: String, Codable, CaseIterable, Sendable {
    case pcm16_24k_mono = "pcm16_24k_mono"
    case pcm16_16k_mono = "pcm16_16k_mono"
    case float32_48k_stereo = "float32_48k_stereo"

    var sampleRate: Int {
        switch self {
        case .pcm16_24k_mono:
            return 24000
        case .pcm16_16k_mono:
            return 16000
        case .float32_48k_stereo:
            return 48000
        }
    }

    var channels: Int {
        switch self {
        case .pcm16_24k_mono, .pcm16_16k_mono:
            return 1
        case .float32_48k_stereo:
            return 2
        }
    }
}

// MARK: - Provider Capabilities

/// Describes the capabilities of a Live provider
struct LiveProviderCapabilities: Codable, Equatable, Sendable {
    /// Can receive and send streaming audio directly
    let supportsStreamingAudio: Bool

    /// Supports full duplex real-time communication
    let supportsRealtimeDuplex: Bool

    /// Requires WebSocket connection (vs HTTP)
    let requiresWebSocket: Bool

    /// Provider handles voice activity detection server-side
    let supportsServerSideVAD: Bool

    /// Supports function/tool calling
    let supportsFunctionCalling: Bool

    /// The execution mode for this provider
    let executionMode: ExecutionMode

    /// Maximum supported sample rate (nil = no limit)
    let maxSampleRate: Int?

    /// Supported audio formats
    let supportedAudioFormats: [AudioFormat]

    // MARK: - Convenience Initializers

    /// Default initializer
    init(
        supportsStreamingAudio: Bool,
        supportsRealtimeDuplex: Bool,
        requiresWebSocket: Bool,
        supportsServerSideVAD: Bool,
        supportsFunctionCalling: Bool,
        executionMode: ExecutionMode,
        maxSampleRate: Int? = nil,
        supportedAudioFormats: [AudioFormat] = [.pcm16_24k_mono]
    ) {
        self.supportsStreamingAudio = supportsStreamingAudio
        self.supportsRealtimeDuplex = supportsRealtimeDuplex
        self.requiresWebSocket = requiresWebSocket
        self.supportsServerSideVAD = supportsServerSideVAD
        self.supportsFunctionCalling = supportsFunctionCalling
        self.executionMode = executionMode
        self.maxSampleRate = maxSampleRate
        self.supportedAudioFormats = supportedAudioFormats
    }

    // MARK: - Predefined Capabilities

    /// Capabilities for Gemini Live API
    static let geminiLive = LiveProviderCapabilities(
        supportsStreamingAudio: true,
        supportsRealtimeDuplex: true,
        requiresWebSocket: true,
        supportsServerSideVAD: true,
        supportsFunctionCalling: true,
        executionMode: .cloudWebSocket,
        maxSampleRate: 24000,
        supportedAudioFormats: [.pcm16_24k_mono]
    )

    /// Capabilities for OpenAI Realtime API
    static let openAIRealtime = LiveProviderCapabilities(
        supportsStreamingAudio: true,
        supportsRealtimeDuplex: true,
        requiresWebSocket: true,
        supportsServerSideVAD: true,
        supportsFunctionCalling: true,
        executionMode: .cloudWebSocket,
        maxSampleRate: 24000,
        supportedAudioFormats: [.pcm16_24k_mono]
    )

    /// Capabilities for HTTP streaming providers (Anthropic, standard OpenAI, etc.)
    static let httpStreaming = LiveProviderCapabilities(
        supportsStreamingAudio: false,
        supportsRealtimeDuplex: false,
        requiresWebSocket: false,
        supportsServerSideVAD: false,
        supportsFunctionCalling: true,
        executionMode: .cloudHTTPStreaming,
        maxSampleRate: 24000,
        supportedAudioFormats: [.pcm16_24k_mono]
    )

    /// Capabilities for on-device MLX models
    static let onDeviceMLX = LiveProviderCapabilities(
        supportsStreamingAudio: false,
        supportsRealtimeDuplex: false,
        requiresWebSocket: false,
        supportsServerSideVAD: false,
        supportsFunctionCalling: false,
        executionMode: .onDeviceMLX,
        maxSampleRate: 24000,
        supportedAudioFormats: [.pcm16_24k_mono]
    )
}

// MARK: - Provider Errors

/// Errors specific to Live providers
enum LiveProviderError: LocalizedError {
    case notConfigured
    case connectionFailed(String)
    case audioFormatNotSupported
    case sttNotAuthorized
    case ttsNotAvailable
    case modelNotLoaded
    case providerNotSupported(String)
    case capabilityMismatch(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Provider is not configured"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .audioFormatNotSupported:
            return "Audio format not supported by this provider"
        case .sttNotAuthorized:
            return "Speech recognition not authorized"
        case .ttsNotAvailable:
            return "Text-to-speech is not available"
        case .modelNotLoaded:
            return "Model is not loaded"
        case .providerNotSupported(let provider):
            return "Provider '\(provider)' is not supported for Live mode"
        case .capabilityMismatch(let detail):
            return "Capability mismatch: \(detail)"
        }
    }
}
