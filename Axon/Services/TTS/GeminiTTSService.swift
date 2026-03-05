//
//  GeminiTTSService.swift
//  Axon
//
//  Gemini TTS service using gemini-2.5-flash-preview-tts and gemini-2.5-pro-preview-tts models
//  Supports 30 voices, controllable speech styles via natural language prompts
//

import Foundation
import Combine

@MainActor
class GeminiTTSService: ObservableObject {
    static let shared = GeminiTTSService()

    /// Dedicated URLSession with long timeouts for TTS generation
    /// (Gemini TTS can take 60+ seconds for long text)
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120   // 2 minutes for initial response
        config.timeoutIntervalForResource = 600  // 10 minutes total for large audio
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Available Voices (for backwards compatibility)

    /// Gemini TTS prebuilt voices - maps to GeminiTTSVoice in Settings
    enum GeminiVoice: String, CaseIterable, Identifiable, Codable {
        case puck = "Puck"
        case charon = "Charon"
        case kore = "Kore"
        case fenrir = "Fenrir"
        case aoede = "Aoede"
        case zephyr = "Zephyr"
        case orus = "Orus"
        case leda = "Leda"

        var id: String { rawValue }

        var displayName: String { rawValue }

        var toneDescription: String {
            switch self {
            case .puck: return "Upbeat, energetic"
            case .charon: return "Deep, informative"
            case .kore: return "Firm, authoritative"
            case .fenrir: return "Excitable, fast-paced"
            case .aoede: return "Breezy, light"
            case .zephyr: return "Bright, clear"
            case .orus: return "Firm, direct"
            case .leda: return "Youthful"
            }
        }

        // MARK: - Registry Bridge Properties

        /// Get voice config from registry (if available)
        var registryConfig: TTSVoiceConfig? {
            UnifiedModelRegistry.shared.voice(provider: .gemini, voiceId: rawValue)
        }

        /// Display name from registry, falling back to hardcoded value
        var registryDisplayName: String {
            registryConfig?.displayName ?? displayName
        }

        /// Tone description from registry, falling back to hardcoded value
        var registryToneDescription: String {
            registryConfig?.toneDescription ?? toneDescription
        }

        /// Whether this enum case exists in the JSON registry
        var isValidInRegistry: Bool {
            registryConfig != nil
        }
    }

    // MARK: - Text Chunking

    /// Maximum characters per chunk to stay safely under Gemini's 32k token limit
    /// Using ~2500 chars as a safe limit (roughly 600-800 tokens)
    private let maxChunkSize = 2500

    /// Chunk text at natural boundaries (paragraphs, sentences, words)
    private func chunkText(_ text: String, maxChars: Int) -> [String] {
        guard text.count > maxChars else { return [text] }

        var chunks: [String] = []
        var remaining = text

        while !remaining.isEmpty {
            if remaining.count <= maxChars {
                chunks.append(remaining)
                break
            }

            // Find the best split point within maxChars
            let searchRange = remaining.prefix(maxChars)

            // Try to split at paragraph boundary (double newline)
            if let paragraphEnd = searchRange.range(of: "\n\n", options: .backwards) {
                let chunk = String(remaining[..<paragraphEnd.upperBound])
                chunks.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = String(remaining[paragraphEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            // Try to split at sentence boundary (. ! ?)
            if let sentenceEnd = searchRange.lastIndex(where: { ".!?".contains($0) }) {
                let endIndex = remaining.index(after: sentenceEnd)
                let chunk = String(remaining[..<endIndex])
                chunks.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = String(remaining[endIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            // Try to split at word boundary (space)
            if let spaceIndex = searchRange.lastIndex(of: " ") {
                let chunk = String(remaining[..<spaceIndex])
                chunks.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = String(remaining[remaining.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            // Last resort: hard split at maxChars
            let splitIndex = remaining.index(remaining.startIndex, offsetBy: maxChars)
            chunks.append(String(remaining[..<splitIndex]))
            remaining = String(remaining[splitIndex...])
        }

        return chunks.filter { !$0.isEmpty }
    }

    // MARK: - TTS Generation

    /// Generate speech audio from text using Gemini TTS
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use (defaults to Puck)
    ///   - apiKey: Gemini API key
    /// - Returns: Audio data (raw PCM, 24kHz 16-bit mono)
    func generateSpeech(
        text: String,
        voice: GeminiVoice = .puck,
        apiKey: String
    ) async throws -> Data {
        // Use the new method with default model and no direction
        return try await generateSpeech(
            text: text,
            voiceName: voice.rawValue,
            model: .flash,
            direction: nil,
            apiKey: apiKey
        )
    }

    /// Generate speech audio from text using Gemini TTS with full configuration
    /// For long text, automatically chunks and concatenates audio.
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voiceName: The voice name to use (e.g., "Puck", "Kore", etc.)
    ///   - model: The TTS model to use (flash or pro)
    ///   - direction: Optional voice direction/style instructions (natural language)
    ///   - apiKey: Gemini API key
    /// - Returns: Audio data (raw PCM, 24kHz 16-bit mono)
    func generateSpeech(
        text: String,
        voiceName: String,
        model: GeminiTTSModel = .flash,
        direction: String? = nil,
        apiKey: String
    ) async throws -> Data {
        // Check if we need to chunk the text
        let chunks = chunkText(text, maxChars: maxChunkSize)

        if chunks.count > 1 {
            print("[GeminiTTSService] 📦 Long text detected (\(text.count) chars) - splitting into \(chunks.count) chunks")
            return try await generateSpeechChunked(
                chunks: chunks,
                voiceName: voiceName,
                model: model,
                direction: direction,
                apiKey: apiKey
            )
        }

        // Single chunk - use direct generation
        return try await generateSpeechSingle(
            text: text,
            voiceName: voiceName,
            model: model,
            direction: direction,
            apiKey: apiKey
        )
    }

    /// Generate speech for multiple chunks and concatenate the PCM audio
    private func generateSpeechChunked(
        chunks: [String],
        voiceName: String,
        model: GeminiTTSModel,
        direction: String?,
        apiKey: String
    ) async throws -> Data {
        var combinedAudio = Data()
        let totalStart = Date()

        for (index, chunk) in chunks.enumerated() {
            print("[GeminiTTSService] 🔊 Generating chunk \(index + 1)/\(chunks.count) (\(chunk.count) chars)")

            let chunkAudio = try await generateSpeechSingle(
                text: chunk,
                voiceName: voiceName,
                model: model,
                direction: direction,
                apiKey: apiKey
            )

            combinedAudio.append(chunkAudio)
            print("[GeminiTTSService] ✅ Chunk \(index + 1) complete: \(chunkAudio.count) bytes")
        }

        let totalElapsed = Date().timeIntervalSince(totalStart)
        print("[GeminiTTSService] 🎉 All \(chunks.count) chunks complete in \(String(format: "%.1f", totalElapsed))s - total audio: \(combinedAudio.count) bytes")

        return combinedAudio
    }

    /// Generate speech for a single text segment (internal implementation)
    private func generateSpeechSingle(
        text: String,
        voiceName: String,
        model: GeminiTTSModel,
        direction: String?,
        apiKey: String
    ) async throws -> Data {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the prompt - prepend direction if provided
        let prompt: String
        if let direction = direction, !direction.isEmpty {
            // Format: Direction followed by transcript
            prompt = """
            \(direction)

            TRANSCRIPT:
            \(text)
            """
        } else {
            prompt = text
        }

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "response_modalities": ["AUDIO"],
                "speech_config": [
                    "voice_config": [
                        "prebuilt_voice_config": [
                            "voice_name": voiceName
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let textLength = text.count
        let startTime = Date()

        #if DEBUG
        print("[GeminiTTSService] Generating speech with voice: \(voiceName), model: \(model.displayName), text length: \(textLength) chars")
        if let direction = direction, !direction.isEmpty {
            print("[GeminiTTSService] Direction: \(direction.prefix(100))...")
        }
        #endif

        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("[GeminiTTSService] ❌ Invalid response after \(String(format: "%.1f", elapsed))s (text: \(textLength) chars)")
                throw GeminiTTSError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    print("[GeminiTTSService] ❌ API error \(httpResponse.statusCode) after \(String(format: "%.1f", elapsed))s: \(errorText.prefix(500))")
                }
                throw GeminiTTSError.apiError(statusCode: httpResponse.statusCode)
            }

            #if DEBUG
            print("[GeminiTTSService] ✅ Response received in \(String(format: "%.1f", elapsed))s")
            #endif

            // Parse the response to extract audio data
            return try parseAudioResponse(data)
        } catch let error as URLError where error.code == .timedOut {
            let elapsed = Date().timeIntervalSince(startTime)
            print("[GeminiTTSService] ⏱️ TIMEOUT after \(String(format: "%.1f", elapsed))s - text was \(textLength) chars, voice: \(voiceName), model: \(model.rawValue)")
            throw error
        }
    }

    // MARK: - Response Parsing

    private func parseAudioResponse(_ data: Data) throws -> Data {
        // Gemini returns JSON with base64-encoded audio in the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let inlineData = firstPart["inlineData"] as? [String: Any],
              let audioBase64 = inlineData["data"] as? String else {
            throw GeminiTTSError.invalidAudioResponse
        }

        guard let audioData = Data(base64Encoded: audioBase64) else {
            throw GeminiTTSError.invalidBase64Audio
        }

        #if DEBUG
        print("[GeminiTTSService] Received audio data: \(audioData.count) bytes")
        #endif

        return audioData
    }
}

// MARK: - Errors

enum GeminiTTSError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case invalidAudioResponse
    case invalidBase64Audio
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Gemini TTS API"
        case .apiError(let statusCode):
            return "Gemini TTS API error (status \(statusCode))"
        case .invalidAudioResponse:
            return "Could not parse audio from response"
        case .invalidBase64Audio:
            return "Invalid base64 audio data"
        case .missingApiKey:
            return "Gemini API key is required for TTS"
        }
    }
}
