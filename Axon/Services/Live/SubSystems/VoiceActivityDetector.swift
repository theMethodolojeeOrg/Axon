import Foundation
import AVFoundation
import Combine

/// Result of voice activity detection
struct VADResult: Sendable {
    /// Whether speech is detected
    let isSpeech: Bool

    /// Confidence level (0.0 to 1.0)
    let confidence: Float

    /// Duration of silence in milliseconds (0 if currently speaking)
    let silenceDurationMs: Int

    /// The RMS energy level
    let rmsLevel: Float
}

/// Voice Activity Detector for detecting speech in audio buffers
/// Uses energy-based detection (no ML dependencies)
@MainActor
final class VoiceActivityDetector: ObservableObject {
    static let shared = VoiceActivityDetector()

    // MARK: - Published State

    /// Whether the user is currently speaking
    @Published private(set) var isSpeaking: Bool = false

    /// Current speech probability (0.0 to 1.0)
    @Published private(set) var speechProbability: Float = 0.0

    /// Current RMS energy level
    @Published private(set) var currentRMSLevel: Float = 0.0

    /// Duration of current silence in milliseconds
    @Published private(set) var silenceDurationMs: Int = 0

    // MARK: - Configuration

    /// Energy threshold for speech detection (adjustable)
    var energyThreshold: Float = 0.01 {
        didSet {
            // Clamp to valid range
            energyThreshold = max(0.001, min(0.5, energyThreshold))
        }
    }

    /// Minimum duration of silence (in ms) before considering utterance complete
    var silenceThresholdMs: Int = 500

    /// Hysteresis factor to prevent rapid on/off switching
    var hysteresisFactor: Float = 0.7

    /// Smoothing factor for RMS (0 = no smoothing, 1 = maximum smoothing)
    var smoothingFactor: Float = 0.3

    // MARK: - Private State

    private var lastSpeechTime: Date?
    private var smoothedRMS: Float = 0.0
    private var wasAboveThreshold: Bool = false

    // Ring buffer for adaptive threshold
    private var rmsHistory: [Float] = []
    private let rmsHistorySize = 50  // ~1 second at typical buffer rates

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Process an audio buffer and detect voice activity
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: VAD result with speech detection info
    func processAudio(buffer: AVAudioPCMBuffer) -> VADResult {
        let rms = calculateRMS(buffer: buffer)

        // Apply smoothing
        smoothedRMS = smoothingFactor * smoothedRMS + (1 - smoothingFactor) * rms
        currentRMSLevel = smoothedRMS

        // Update RMS history for adaptive threshold
        updateRMSHistory(rms: rms)

        // Determine if speech based on threshold with hysteresis
        let effectiveThreshold = wasAboveThreshold
            ? energyThreshold * hysteresisFactor
            : energyThreshold

        let isCurrentlySpeech = smoothedRMS > effectiveThreshold
        wasAboveThreshold = isCurrentlySpeech

        // Calculate confidence
        let confidence = calculateConfidence(rms: smoothedRMS)

        // Update silence duration
        let now = Date()
        if isCurrentlySpeech {
            lastSpeechTime = now
            silenceDurationMs = 0
        } else if let lastSpeech = lastSpeechTime {
            silenceDurationMs = Int(now.timeIntervalSince(lastSpeech) * 1000)
        }

        // Update published state
        let wasSpeak = isSpeaking
        isSpeaking = isCurrentlySpeech
        speechProbability = confidence

        // Log state changes for debugging
        if wasSpeak != isSpeaking {
            if isSpeaking {
                print("[VAD] Speech started (RMS: \(String(format: "%.4f", smoothedRMS)), threshold: \(String(format: "%.4f", effectiveThreshold)))")
            } else {
                print("[VAD] Speech ended (silence: \(silenceDurationMs)ms)")
            }
        }

        return VADResult(
            isSpeech: isCurrentlySpeech,
            confidence: confidence,
            silenceDurationMs: silenceDurationMs,
            rmsLevel: smoothedRMS
        )
    }

    /// Check if utterance is complete (silence exceeded threshold)
    var isUtteranceComplete: Bool {
        !isSpeaking && silenceDurationMs >= silenceThresholdMs && lastSpeechTime != nil
    }

    /// Reset the detector state
    func reset() {
        isSpeaking = false
        speechProbability = 0.0
        currentRMSLevel = 0.0
        silenceDurationMs = 0
        lastSpeechTime = nil
        smoothedRMS = 0.0
        wasAboveThreshold = false
        rmsHistory.removeAll()
    }

    /// Configure sensitivity (0.0 = most sensitive, 1.0 = least sensitive)
    func setSensitivity(_ sensitivity: Float) {
        // Map sensitivity to threshold (inverse relationship)
        // sensitivity 0.0 -> threshold 0.005 (very sensitive)
        // sensitivity 0.5 -> threshold 0.01 (default)
        // sensitivity 1.0 -> threshold 0.05 (less sensitive)
        let clampedSensitivity = max(0.0, min(1.0, sensitivity))
        energyThreshold = 0.005 + (clampedSensitivity * 0.045)
    }

    // MARK: - Private Methods

    /// Calculate RMS (Root Mean Square) energy from audio buffer
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0.0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0.0
        }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        // Calculate sum of squares
        var sumOfSquares: Float = 0.0
        for sample in samples {
            sumOfSquares += sample * sample
        }

        // Return RMS
        return sqrt(sumOfSquares / Float(frameLength))
    }

    /// Update RMS history for potential adaptive thresholding
    private func updateRMSHistory(rms: Float) {
        rmsHistory.append(rms)
        if rmsHistory.count > rmsHistorySize {
            rmsHistory.removeFirst()
        }
    }

    /// Calculate confidence based on how far RMS is above threshold
    private func calculateConfidence(rms: Float) -> Float {
        guard rms > 0 else { return 0.0 }

        // Confidence is based on how much RMS exceeds threshold
        let ratio = rms / energyThreshold

        if ratio <= 1.0 {
            // Below threshold
            return ratio * 0.5  // 0.0 to 0.5
        } else {
            // Above threshold
            // Asymptotic approach to 1.0
            return 0.5 + 0.5 * (1.0 - 1.0 / ratio)
        }
    }

    /// Get the adaptive noise floor (minimum of recent RMS values)
    var noiseFloor: Float {
        guard !rmsHistory.isEmpty else { return 0.0 }
        return rmsHistory.min() ?? 0.0
    }

    /// Get the peak level (maximum of recent RMS values)
    var peakLevel: Float {
        guard !rmsHistory.isEmpty else { return 0.0 }
        return rmsHistory.max() ?? 0.0
    }
}

// MARK: - VAD Mode Extension (for future ML-based VAD)

extension VoiceActivityDetector {
    /// Available VAD modes
    enum VADMode: String, Codable, CaseIterable, Sendable {
        /// Energy-based detection (fast, no ML)
        case energyBased = "energyBased"

        /// ML-based detection (more accurate, requires CoreML)
        case mlBased = "mlBased"

        /// Hybrid: energy for trigger, ML for confirmation
        case hybrid = "hybrid"

        var displayName: String {
            switch self {
            case .energyBased:
                return "Energy-based"
            case .mlBased:
                return "ML-based"
            case .hybrid:
                return "Hybrid"
            }
        }
    }

    /// Current mode (currently only energy-based is implemented)
    var mode: VADMode {
        .energyBased
    }
}
