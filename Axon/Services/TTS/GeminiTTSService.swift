//
//  GeminiTTSService.swift
//  Axon
//
//  Gemini TTS service using gemini-2.5-flash-preview-tts model
//  Supports multiple voices and controllable speech styles
//

import Foundation
import Combine

@MainActor
class GeminiTTSService: ObservableObject {
    static let shared = GeminiTTSService()

    private init() {}

    // MARK: - Available Voices

    /// Gemini TTS prebuilt voices with tone descriptions
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
    }

    // MARK: - TTS Generation

    /// Generate speech audio from text using Gemini TTS
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use (defaults to Puck)
    ///   - apiKey: Gemini API key
    /// - Returns: Audio data (WAV format, 24kHz)
    func generateSpeech(
        text: String,
        voice: GeminiVoice = .puck,
        apiKey: String
    ) async throws -> Data {
        let model = "gemini-2.5-flash-preview-tts"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": text]
                    ]
                ]
            ],
            "generationConfig": [
                "response_modalities": ["AUDIO"],
                "speech_config": [
                    "voice_config": [
                        "prebuilt_voice_config": [
                            "voice_name": voice.rawValue
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[GeminiTTSService] Generating speech with voice: \(voice.rawValue)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiTTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[GeminiTTSService] Error: \(errorText)")
            }
            throw GeminiTTSError.apiError(statusCode: httpResponse.statusCode)
        }

        // Parse the response to extract audio data
        return try parseAudioResponse(data)
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
