//
//  LiveSettings.swift
//  Axon
//
//  Realtime voice settings
//

import Foundation

// MARK: - Live Settings for Realtime Voice

struct LiveSettings: Codable, Equatable, Sendable {
    // MARK: - Provider Settings

    /// Active Live provider (defaults to Gemini)
    var defaultProvider: AIProvider = .gemini

    /// Default model ID for Live sessions
    var defaultModelId: String = "gemini-2.5-flash-native-audio-preview-12-2025"

    /// OpenAI-specific voice (default: marin)
    var openAIVoice: String = "marin"

    /// Gemini-specific voice (default: Leda)
    var geminiVoice: String = "Leda"

    // MARK: - Universal Mode Settings (NEW)

    /// Use on-device MLX models instead of cloud providers
    var useOnDeviceModels: Bool = false

    /// Preferred MLX model for on-device Live mode
    var preferredMLXModel: String? = nil

    // MARK: - VAD Settings

    /// Use local voice activity detection (vs server-side)
    var useLocalVAD: Bool = true

    /// VAD sensitivity (0.0 = very sensitive, 1.0 = less sensitive)
    var vadSensitivity: Float = 0.5

    // MARK: - Noise Gate Settings

    /// Enable noise gate to filter out background noise
    var noiseGateEnabled: Bool = true

    /// Noise gate threshold (0.0 = very sensitive, 1.0 = aggressive filtering)
    /// This is the RMS level below which audio is silenced
    var noiseGateThreshold: Float = 0.02

    /// Attack time - how quickly the gate opens when speech is detected (ms)
    var noiseGateAttackMs: Int = 10

    /// Hold time - how long to keep gate open after speech stops (ms)
    var noiseGateHoldMs: Int = 200

    /// Release time - how quickly the gate closes after hold time (ms)
    var noiseGateReleaseMs: Int = 50

    // MARK: - STT Settings

    /// Use on-device speech-to-text
    var useOnDeviceSTT: Bool = true

    // MARK: - TTS Fallback Settings

    /// TTS engine for non-native audio providers
    var fallbackTTSEngine: TTSEngine = .kokoro

    /// Default Kokoro voice for TTS fallback
    var defaultKokoroVoice: KokoroTTSVoice = .af_heart

    // MARK: - Performance Settings

    /// Latency vs quality trade-off
    var latencyMode: LatencyMode = .balanced

    /// Prefer native real-time providers when available
    var preferRealtime: Bool = true
}
