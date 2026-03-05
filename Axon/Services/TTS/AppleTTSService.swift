//
//  AppleTTSService.swift
//  Axon
//
//  Native Apple TTS service using AVSpeechSynthesizer (Premium Neural voices)
//  Provides zero-configuration TTS for users without API keys
//  Supports SSML for natural speech prosody (iOS 16+)
//

import Foundation
import AVFoundation
import Combine

// MARK: - Voice Quality Tier

/// Represents the quality tier of available Apple TTS voices
enum AppleVoiceQualityTier: String, Codable, CaseIterable {
    case premium = "Premium"      // Neural voices - best quality
    case enhanced = "Enhanced"    // Improved voices - good quality
    case compact = "Compact"      // Basic voices - robotic sounding
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .premium: return "Neural voice with natural prosody"
        case .enhanced: return "Improved voice quality"
        case .compact: return "Basic voice (robotic)"
        }
    }
    
    var icon: String {
        switch self {
        case .premium: return "sparkles"
        case .enhanced: return "waveform"
        case .compact: return "speaker.wave.1"
        }
    }
    
    var requiresDownload: Bool {
        switch self {
        case .premium, .enhanced: return true
        case .compact: return false
        }
    }
}

// MARK: - Apple TTS Voice

/// Apple TTS voice options - these are used as preferences, but actual voice
/// selection prioritizes Premium/Enhanced quality versions when available
enum AppleTTSVoice: String, Codable, CaseIterable, Identifiable {
    // US English
    case samantha = "Samantha"
    case alex = "Alex"
    case allison = "Allison"
    case ava = "Ava"
    case tom = "Tom"
    case nicky = "Nicky"
    case evan = "Evan"
    case aaron = "Aaron"
    
    // UK English
    case susan = "Susan"
    case daniel = "Daniel"
    case kate = "Kate"
    case oliver = "Oliver"
    
    // Irish English
    case moira = "Moira"
    
    // Indian English
    case rishi = "Rishi"
    case veena = "Veena"
    
    // Australian English
    case karen = "Karen"
    case lee = "Lee"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .samantha: return "Samantha (US)"
        case .alex: return "Alex (US)"
        case .allison: return "Allison (US)"
        case .ava: return "Ava (US)"
        case .tom: return "Tom (US)"
        case .nicky: return "Nicky (US)"
        case .evan: return "Evan (US)"
        case .aaron: return "Aaron (US)"
        case .susan: return "Susan (UK)"
        case .daniel: return "Daniel (UK)"
        case .kate: return "Kate (UK)"
        case .oliver: return "Oliver (UK)"
        case .moira: return "Moira (Irish)"
        case .rishi: return "Rishi (Indian)"
        case .veena: return "Veena (Indian)"
        case .karen: return "Karen (Australian)"
        case .lee: return "Lee (Australian)"
        }
    }
    
    var language: String {
        switch self {
        case .samantha, .alex, .allison, .ava, .tom, .nicky, .evan, .aaron:
            return "en-US"
        case .susan, .daniel, .kate, .oliver:
            return "en-GB"
        case .moira:
            return "en-IE"
        case .rishi, .veena:
            return "en-IN"
        case .karen, .lee:
            return "en-AU"
        }
    }

    var gender: VoiceGender {
        switch self {
        case .samantha, .allison, .ava, .susan, .moira, .karen, .kate, .nicky, .veena:
            return .female
        case .alex, .daniel, .rishi, .lee, .tom, .oliver, .evan, .aaron:
            return .male
        }
    }

    /// Get all voices filtered by gender
    static func voices(for gender: VoiceGender) -> [AppleTTSVoice] {
        allCases.filter { $0.gender == gender }
    }

    // MARK: - Registry Bridge Properties

    /// Get voice config from registry (if available)
    var registryConfig: TTSVoiceConfig? {
        UnifiedModelRegistry.shared.voice(provider: .apple, voiceId: rawValue)
    }

    /// Display name from registry, falling back to hardcoded value
    var registryDisplayName: String {
        registryConfig?.displayName ?? displayName
    }

    /// Whether this enum case exists in the JSON registry
    var isValidInRegistry: Bool {
        registryConfig != nil
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
    
    /// Cached voice quality tier (refreshed on init and when requested)
    @Published private(set) var currentQualityTier: AppleVoiceQualityTier = .compact

    override private init() {
        super.init()
        synthesizer.delegate = self
        // Detect initial quality tier
        currentQualityTier = Self.detectVoiceQualityTier()
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
    
    // MARK: - Voice Quality Detection
    
    /// Detect the best available voice quality tier on this device
    /// - Returns: The highest quality tier available (Premium > Enhanced > Compact)
    static func detectVoiceQualityTier(for language: String = "en") -> AppleVoiceQualityTier {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: language) }
        
        if voices.contains(where: { $0.quality == .premium }) {
            return .premium
        }
        if voices.contains(where: { $0.quality == .enhanced }) {
            return .enhanced
        }
        return .compact
    }
    
    /// Refresh the cached quality tier (call after user downloads new voices)
    func refreshQualityTier() {
        currentQualityTier = Self.detectVoiceQualityTier()
        print("[AppleTTSService] Voice quality tier: \(currentQualityTier.displayName)")
    }
    
    /// Get the best available voice for a given preference
    /// Prioritizes: Premium version > Enhanced version > Any available
    /// - Parameters:
    ///   - preferred: The user's preferred voice (e.g., .samantha)
    ///   - language: Fallback language if preferred voice unavailable
    /// - Returns: The best available AVSpeechSynthesisVoice
    static func getBestAvailableVoice(
        preferring preferred: AppleTTSVoice = .samantha,
        language: String? = nil
    ) -> AVSpeechSynthesisVoice? {
        let targetLanguage = language ?? preferred.language
        let voiceName = preferred.rawValue
        
        // Get all voices for the target language
        let languageVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == targetLanguage
        }
        
        // Find voices matching the preferred name
        let matchingVoices = languageVoices.filter {
            $0.name.contains(voiceName)
        }
        
        // Priority: Premium > Enhanced > Default matching voice
        if let premium = matchingVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = matchingVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        if let anyMatch = matchingVoices.first {
            return anyMatch
        }
        
        // Fallback: best quality voice in preferred language
        if let premium = languageVoices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = languageVoices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        
        // Last resort: any voice in the language
        return languageVoices.first ?? AVSpeechSynthesisVoice(language: targetLanguage)
    }
    
    /// Get details about the currently selected voice
    static func getVoiceDetails(for voice: AVSpeechSynthesisVoice) -> (name: String, quality: AppleVoiceQualityTier) {
        let tier: AppleVoiceQualityTier
        switch voice.quality {
        case .premium:
            tier = .premium
        case .enhanced:
            tier = .enhanced
        default:
            tier = .compact
        }
        return (voice.name, tier)
    }

    // MARK: - TTS Generation

    /// Generate speech audio from text using Apple's AVSpeechSynthesizer
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice preference (best quality version will be selected)
    ///   - rate: Speech rate (0.0 to 1.0, default 0.46 for natural sound)
    ///   - pitchMultiplier: Pitch multiplier (0.5 to 2.0, default 1.0)
    ///   - useSSML: Whether to use SSML for natural prosody (iOS 16+)
    /// - Returns: Audio data in CAF format
    func generateSpeech(
        text: String,
        voice: AppleTTSVoice = .samantha,
        rate: Float = 0.46, // Slightly slower than default for natural sound
        pitchMultiplier: Float = 1.0,
        useSSML: Bool = true
    ) async throws -> Data {
        // Get best available voice (Premium > Enhanced > Compact)
        guard let avVoice = Self.getBestAvailableVoice(preferring: voice) else {
            throw AppleTTSError.noVoiceAvailable
        }
        
        let voiceDetails = Self.getVoiceDetails(for: avVoice)
        print("[AppleTTSService] Using voice: \(voiceDetails.name) (\(voiceDetails.quality.displayName)), rate: \(rate)")

        // Create utterance - with SSML if available (iOS 16+)
        var utterance: AVSpeechUtterance
        
        if #available(iOS 16.0, macOS 13.0, *), useSSML {
            // Wrap text in SSML with prosody control for more natural speech
            let ssmlString = """
            <speak>
                <prosody rate="95%">
                    \(text)
                </prosody>
            </speak>
            """
            utterance = AVSpeechUtterance(ssmlRepresentation: ssmlString) ?? AVSpeechUtterance(string: text)
        } else {
            utterance = AVSpeechUtterance(string: text)
        }
        
        // Apply voice and settings
        utterance.voice = avVoice
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = 1.0
        
        // Add delays to prevent audio clipping at start/end
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

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

    /// Get all available system voices for English
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.language.starts(with: "en")
        }
    }
    
    /// Get available voices grouped by quality tier
    static func availableVoicesGrouped(language: String = "en") -> [AppleVoiceQualityTier: [AVSpeechSynthesisVoice]] {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: language) }
        
        var grouped: [AppleVoiceQualityTier: [AVSpeechSynthesisVoice]] = [:]
        
        for voice in voices {
            let tier: AppleVoiceQualityTier
            switch voice.quality {
            case .premium:
                tier = .premium
            case .enhanced:
                tier = .enhanced
            default:
                tier = .compact
            }
            grouped[tier, default: []].append(voice)
        }
        
        return grouped
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

