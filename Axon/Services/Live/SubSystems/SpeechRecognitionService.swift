import Foundation
import AVFoundation
import Speech
import Combine

/// Errors specific to speech recognition
enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case requestCreationFailed
    case recognizerUnavailable
    case recognitionFailed(String)
    case audioFormatMismatch

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition is not authorized. Please enable it in Settings."
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        case .recognizerUnavailable:
            return "Speech recognizer is not available for the selected language"
        case .recognitionFailed(let reason):
            return "Speech recognition failed: \(reason)"
        case .audioFormatMismatch:
            return "Audio format does not match recognition requirements"
        }
    }
}

/// On-device speech recognition service using Apple's Speech framework
@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {
    static let shared = SpeechRecognitionService()

    // MARK: - Published State

    /// Whether actively listening for speech
    @Published private(set) var isListening: Bool = false

    /// Partial (in-progress) transcript
    @Published private(set) var partialTranscript: String = ""

    /// Final (committed) transcript
    @Published private(set) var finalTranscript: String = ""

    /// Current authorization status
    @Published private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Whether on-device recognition is available
    @Published private(set) var isOnDeviceAvailable: Bool = false

    // MARK: - Private State

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let locale: Locale
    private var lastTranscriptTime: Date?

    // Callback for real-time transcript updates
    var onTranscriptUpdate: ((String, Bool) -> Void)?

    // MARK: - Initialization

    private override init() {
        self.locale = .current
        super.init()
        setupRecognizer()
    }

    /// Initialize with a specific locale
    init(locale: Locale) {
        self.locale = locale
        super.init()
        setupRecognizer()
    }

    private func setupRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.delegate = self

        // Check on-device availability
        if #available(iOS 13.0, macOS 10.15, *) {
            isOnDeviceAvailable = speechRecognizer?.supportsOnDeviceRecognition ?? false
        }

        // Get current authorization status
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Authorization

    /// Request speech recognition authorization
    /// - Returns: True if authorized
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    self?.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    /// Check if speech recognition is currently authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    // MARK: - Recognition Control

    /// Start speech recognition
    /// - Throws: SpeechRecognitionError if recognition cannot start
    func startRecognition() throws {
        guard authorizationStatus == .authorized else {
            throw SpeechRecognitionError.notAuthorized
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        // Cancel any existing task
        stopRecognition()

        // Create new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let request = recognitionRequest else {
            throw SpeechRecognitionError.requestCreationFailed
        }

        // Configure for real-time results
        request.shouldReportPartialResults = true

        // Prefer on-device recognition for privacy
        if #available(iOS 13.0, macOS 10.15, *) {
            request.requiresOnDeviceRecognition = isOnDeviceAvailable
        }

        // Add contextual hints if needed
        // request.contextualStrings = ["Hey Siri", "OK Google"]

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }

        isListening = true
        partialTranscript = ""
        lastTranscriptTime = Date()

        print("[STT] Started speech recognition (on-device: \(isOnDeviceAvailable))")
    }

    /// Append audio buffer to recognition
    /// - Parameter buffer: The audio buffer to process
    func appendAudio(buffer: AVAudioPCMBuffer) {
        guard isListening else { return }
        recognitionRequest?.append(buffer)
    }

    /// Stop speech recognition
    func stopRecognition() {
        // End audio input
        recognitionRequest?.endAudio()

        // Cancel the task
        recognitionTask?.cancel()

        // Clear references
        recognitionRequest = nil
        recognitionTask = nil

        if isListening {
            isListening = false
            print("[STT] Stopped speech recognition")
        }
    }

    /// Reset all state
    func reset() {
        stopRecognition()
        partialTranscript = ""
        finalTranscript = ""
        lastTranscriptTime = nil
    }

    // MARK: - Private Methods

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Check for common non-fatal errors
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // No speech detected - this is normal
                print("[STT] No speech detected")
            } else {
                print("[STT] Recognition error: \(error.localizedDescription)")
            }
            return
        }

        guard let result = result else { return }

        let transcript = result.bestTranscription.formattedString
        lastTranscriptTime = Date()

        if result.isFinal {
            // Final result
            finalTranscript = transcript
            partialTranscript = ""
            onTranscriptUpdate?(transcript, true)
            print("[STT] Final transcript: \(transcript)")
        } else {
            // Partial result
            partialTranscript = transcript
            onTranscriptUpdate?(transcript, false)
        }
    }

    // MARK: - Utility Methods

    /// Get the current transcript (partial or final)
    var currentTranscript: String {
        finalTranscript.isEmpty ? partialTranscript : finalTranscript
    }

    /// Check if we have any transcript
    var hasTranscript: Bool {
        !currentTranscript.isEmpty
    }

    /// Get supported locales
    static var supportedLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales().map { Locale(identifier: $0.identifier) }
    }

    /// Check if a locale is supported
    static func isLocaleSupported(_ locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available {
                print("[STT] Speech recognizer became unavailable")
                stopRecognition()
            } else {
                print("[STT] Speech recognizer is now available")
            }
        }
    }
}

// MARK: - Audio Format Helper

extension SpeechRecognitionService {
    /// Get the expected audio format for speech recognition
    static var expectedAudioFormat: AVAudioFormat? {
        // Speech recognition works best with 16kHz mono
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )
    }

    /// Check if an audio format is compatible with speech recognition
    static func isFormatCompatible(_ format: AVAudioFormat) -> Bool {
        // Speech framework is flexible but prefers:
        // - Sample rate: 16kHz or higher
        // - Channels: 1 (mono)
        // - Format: Float32 or Int16
        return format.channelCount >= 1 && format.sampleRate >= 8000
    }
}
