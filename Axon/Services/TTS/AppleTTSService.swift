//
//  AppleTTSService.swift
//  Axon
//
//  Native Apple TTS service using AVSpeechSynthesizer (Siri voices)
//  Provides zero-configuration TTS for users without API keys
//

import Foundation
import AVFoundation
import Combine

/// Apple TTS voice options with Siri-style identifiers
enum AppleTTSVoice: String, Codable, CaseIterable, Identifiable {
    case samantha = "com.apple.voice.compact.en-US.Samantha"
    case alex = "com.apple.speech.synthesis.voice.Alex"
    case allison = "com.apple.voice.compact.en-US.Allison"
    case ava = "com.apple.voice.compact.en-US.Ava"
    case susan = "com.apple.voice.compact.en-GB.Susan"
    case daniel = "com.apple.voice.compact.en-GB.Daniel"
    case moira = "com.apple.voice.compact.en-IE.Moira"
    case rishi = "com.apple.voice.compact.en-IN.Rishi"
    case karen = "com.apple.voice.compact.en-AU.Karen"
    case lee = "com.apple.voice.compact.en-AU.Lee"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .samantha: return "Samantha (US)"
        case .alex: return "Alex (US)"
        case .allison: return "Allison (US)"
        case .ava: return "Ava (US)"
        case .susan: return "Susan (UK)"
        case .daniel: return "Daniel (UK)"
        case .moira: return "Moira (Irish)"
        case .rishi: return "Rishi (Indian)"
        case .karen: return "Karen (Australian)"
        case .lee: return "Lee (Australian)"
        }
    }

    var gender: VoiceGender {
        switch self {
        case .samantha, .allison, .ava, .susan, .moira, .karen:
            return .female
        case .alex, .daniel, .rishi, .lee:
            return .male
        }
    }

    /// Get the best available voice, falling back if the preferred one isn't installed
    static func bestAvailableVoice(preferring preferred: AppleTTSVoice = .samantha) -> AVSpeechSynthesisVoice? {
        // Try the preferred voice first
        if let voice = AVSpeechSynthesisVoice(identifier: preferred.rawValue) {
            return voice
        }

        // Try other voices in order of preference
        for voiceCase in AppleTTSVoice.allCases {
            if let voice = AVSpeechSynthesisVoice(identifier: voiceCase.rawValue) {
                return voice
            }
        }

        // Fall back to default English voice
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Get all voices filtered by gender
    static func voices(for gender: VoiceGender) -> [AppleTTSVoice] {
        allCases.filter { $0.gender == gender }
    }
}

@MainActor
final class AppleTTSService: NSObject, ObservableObject {
    static let shared = AppleTTSService()

    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var continuation: CheckedContinuation<Data, Error>?

    @Published var isSpeaking = false

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Errors

    enum AppleTTSError: LocalizedError {
        case synthesisSetupFailed(String)
        case noVoiceAvailable
        case audioCaptureFailed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .synthesisSetupFailed(let reason):
                return "Apple TTS setup failed: \(reason)"
            case .noVoiceAvailable:
                return "No Apple TTS voice available. Please check your device settings."
            case .audioCaptureFailed:
                return "Failed to capture audio from Apple TTS"
            case .cancelled:
                return "Apple TTS was cancelled"
            }
        }
    }

    // MARK: - TTS Generation

    /// Generate speech audio from text using Apple's AVSpeechSynthesizer
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use (defaults to Samantha)
    ///   - rate: Speech rate (0.0 to 1.0, default 0.5)
    ///   - pitchMultiplier: Pitch multiplier (0.5 to 2.0, default 1.0)
    /// - Returns: Audio data in M4A format
    func generateSpeech(
        text: String,
        voice: AppleTTSVoice = .samantha,
        rate: Float = AVSpeechUtteranceDefaultSpeechRate,
        pitchMultiplier: Float = 1.0
    ) async throws -> Data {
        // Get best available voice
        guard let avVoice = AppleTTSVoice.bestAvailableVoice(preferring: voice) else {
            throw AppleTTSError.noVoiceAvailable
        }

        print("[AppleTTSService] Generating speech with voice: \(avVoice.name), rate: \(rate)")

        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = avVoice
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = 1.0

        // Use write(to:) API for iOS 13+ to capture audio to file
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            // Create temporary file for audio output
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("caf")

            do {
                // Use the write API (iOS 13+) to capture audio without playing
                try synthesizer.write(utterance) { [weak self] buffer in
                    guard let self = self else { return }

                    guard let pcmBuffer = buffer as? AVAudioPCMBuffer, pcmBuffer.frameLength > 0 else {
                        // Empty buffer signals completion
                        Task { @MainActor in
                            self.finishAudioCapture(tempURL: tempURL)
                        }
                        return
                    }

                    // Write buffer to file
                    Task { @MainActor in
                        do {
                            if self.audioFile == nil {
                                self.audioFile = try AVAudioFile(
                                    forWriting: tempURL,
                                    settings: pcmBuffer.format.settings,
                                    commonFormat: .pcmFormatFloat32,
                                    interleaved: false
                                )
                            }
                            try self.audioFile?.write(from: pcmBuffer)
                        } catch {
                            print("[AppleTTSService] Error writing audio buffer: \(error)")
                        }
                    }
                }
            } catch {
                continuation.resume(throwing: AppleTTSError.synthesisSetupFailed(error.localizedDescription))
                self.continuation = nil
            }
        }
    }

    private func finishAudioCapture(tempURL: URL) {
        defer {
            audioFile = nil
        }

        guard let continuation = self.continuation else { return }
        self.continuation = nil

        // Read the audio data from the temp file
        do {
            let audioData = try Data(contentsOf: tempURL)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

            if audioData.isEmpty {
                continuation.resume(throwing: AppleTTSError.audioCaptureFailed)
            } else {
                print("[AppleTTSService] Generated audio: \(audioData.count) bytes")
                continuation.resume(returning: audioData)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            continuation.resume(throwing: AppleTTSError.audioCaptureFailed)
        }
    }

    /// Stop any current speech synthesis
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Get all available system voices for the current locale
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.starts(with: "en")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AppleTTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
            print("[AppleTTSService] Started speaking")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            print("[AppleTTSService] Finished speaking")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            if let continuation = self.continuation {
                self.continuation = nil
                continuation.resume(throwing: AppleTTSError.cancelled)
            }
            print("[AppleTTSService] Cancelled speaking")
        }
    }
}
