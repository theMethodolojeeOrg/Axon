//
//  NoiseGate.swift
//  Axon
//
//  Audio noise gate to filter out background noise before sending to Live providers.
//  Prevents ambient sounds from triggering the AI and reduces bandwidth.
//

import Foundation
import AVFoundation

/// State of the noise gate
enum NoiseGateState: String {
    case closed     // Gate is closed, audio is silenced
    case attack     // Gate is opening
    case open       // Gate is fully open, audio passes through
    case hold       // Gate is open but waiting for more speech
    case release    // Gate is closing
}

/// Audio noise gate for filtering background noise
/// Uses RMS energy detection with attack/hold/release envelope
final class NoiseGate {

    // MARK: - Configuration

    /// RMS threshold below which audio is gated (0.0 to 1.0)
    var threshold: Float = 0.02

    /// Attack time in milliseconds (how quickly gate opens)
    var attackMs: Int = 10

    /// Hold time in milliseconds (how long to keep open after signal drops)
    var holdMs: Int = 200

    /// Release time in milliseconds (how quickly gate closes)
    var releaseMs: Int = 50

    /// Hysteresis ratio - gate closes at threshold * hysteresis
    var hysteresisRatio: Float = 0.7

    // MARK: - State

    private(set) var state: NoiseGateState = .closed
    private(set) var currentGain: Float = 0.0  // 0.0 = fully closed, 1.0 = fully open

    private var lastAboveThresholdTime: Date?
    private var stateChangeTime: Date = Date()
    private var smoothedRMS: Float = 0.0
    private let smoothingFactor: Float = 0.3

    // MARK: - Statistics

    private(set) var gatedBufferCount: Int = 0
    private(set) var passedBufferCount: Int = 0

    // MARK: - Initialization

    init(threshold: Float = 0.02, attackMs: Int = 10, holdMs: Int = 200, releaseMs: Int = 50) {
        self.threshold = threshold
        self.attackMs = attackMs
        self.holdMs = holdMs
        self.releaseMs = releaseMs
    }

    /// Configure from LiveSettings
    func configure(from settings: LiveSettings) {
        threshold = settings.noiseGateThreshold
        attackMs = settings.noiseGateAttackMs
        holdMs = settings.noiseGateHoldMs
        releaseMs = settings.noiseGateReleaseMs
    }

    // MARK: - Processing

    /// Process an audio buffer and determine if it should pass
    /// - Parameter buffer: The audio buffer to analyze
    /// - Returns: true if audio should pass through, false if it should be gated
    func shouldPass(buffer: AVAudioPCMBuffer) -> Bool {
        let rms = calculateRMS(buffer: buffer)

        // Apply smoothing
        smoothedRMS = smoothingFactor * smoothedRMS + (1 - smoothingFactor) * rms

        // Update state machine
        updateState(rms: smoothedRMS)

        // Update gain based on state
        updateGain()

        // Track statistics
        let passes = currentGain > 0.5
        if passes {
            passedBufferCount += 1
        } else {
            gatedBufferCount += 1
        }

        return passes
    }

    /// Process buffer and return gated version (applies gain)
    /// - Parameter buffer: The input audio buffer
    /// - Returns: A new buffer with gain applied, or nil if fully gated
    func process(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let shouldPassThrough = shouldPass(buffer: buffer)

        if !shouldPassThrough {
            return nil  // Fully gated
        }

        // If gain is 1.0, return original buffer
        if currentGain >= 0.99 {
            return buffer
        }

        // Apply gain to the buffer (for smooth transitions)
        return applyGain(to: buffer, gain: currentGain)
    }

    /// Reset the gate state
    func reset() {
        state = .closed
        currentGain = 0.0
        lastAboveThresholdTime = nil
        stateChangeTime = Date()
        smoothedRMS = 0.0
        gatedBufferCount = 0
        passedBufferCount = 0
    }

    // MARK: - Private Methods

    private func updateState(rms: Float) {
        let now = Date()
        let timeSinceStateChange = now.timeIntervalSince(stateChangeTime) * 1000  // ms

        // Determine if signal is above threshold (with hysteresis)
        let effectiveThreshold = (state == .open || state == .hold)
            ? threshold * hysteresisRatio
            : threshold

        let isAboveThreshold = rms > effectiveThreshold

        if isAboveThreshold {
            lastAboveThresholdTime = now
        }

        // State machine
        switch state {
        case .closed:
            if isAboveThreshold {
                state = .attack
                stateChangeTime = now
            }

        case .attack:
            if !isAboveThreshold {
                // Signal dropped during attack - go back to closed
                state = .closed
                stateChangeTime = now
            } else if timeSinceStateChange >= Double(attackMs) {
                // Attack complete - gate is now open
                state = .open
                stateChangeTime = now
            }

        case .open:
            if !isAboveThreshold {
                // Signal dropped - enter hold
                state = .hold
                stateChangeTime = now
            }

        case .hold:
            if isAboveThreshold {
                // Signal returned - back to open
                state = .open
                stateChangeTime = now
            } else if timeSinceStateChange >= Double(holdMs) {
                // Hold expired - start release
                state = .release
                stateChangeTime = now
            }

        case .release:
            if isAboveThreshold {
                // Signal returned during release - reopen
                state = .attack
                stateChangeTime = now
            } else if timeSinceStateChange >= Double(releaseMs) {
                // Release complete - gate is now closed
                state = .closed
                stateChangeTime = now
            }
        }
    }

    private func updateGain() {
        let now = Date()
        let timeSinceStateChange = now.timeIntervalSince(stateChangeTime) * 1000  // ms

        switch state {
        case .closed:
            currentGain = 0.0

        case .attack:
            // Linear ramp from 0 to 1 over attack time
            let progress = Float(min(timeSinceStateChange / Double(attackMs), 1.0))
            currentGain = progress

        case .open, .hold:
            currentGain = 1.0

        case .release:
            // Linear ramp from 1 to 0 over release time
            let progress = Float(min(timeSinceStateChange / Double(releaseMs), 1.0))
            currentGain = 1.0 - progress
        }
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0.0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return 0.0
        }

        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        var sumOfSquares: Float = 0.0
        for sample in samples {
            sumOfSquares += sample * sample
        }

        return sqrt(sumOfSquares / Float(frameLength))
    }

    private func applyGain(to buffer: AVAudioPCMBuffer, gain: Float) -> AVAudioPCMBuffer? {
        guard let sourceData = buffer.floatChannelData else { return nil }

        let format = buffer.format
        let frameLength = buffer.frameLength

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        outputBuffer.frameLength = frameLength

        guard let destData = outputBuffer.floatChannelData else { return nil }

        let channelCount = Int(format.channelCount)

        for channel in 0..<channelCount {
            let source = sourceData[channel]
            let dest = destData[channel]

            for frame in 0..<Int(frameLength) {
                dest[frame] = source[frame] * gain
            }
        }

        return outputBuffer
    }
}

// MARK: - Debug Extension

extension NoiseGate {
    var debugDescription: String {
        """
        [NoiseGate] State: \(state.rawValue), Gain: \(String(format: "%.2f", currentGain))
        [NoiseGate] RMS: \(String(format: "%.4f", smoothedRMS)), Threshold: \(String(format: "%.4f", threshold))
        [NoiseGate] Passed: \(passedBufferCount), Gated: \(gatedBufferCount)
        """
    }
}
