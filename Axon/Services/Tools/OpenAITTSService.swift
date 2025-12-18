//
//  OpenAITTSService.swift
//  Axon
//
//  OpenAI TTS service using gpt-4o-mini-tts and tts-1/tts-1-hd models
//  Supports 11 built-in voices with optional voice instructions
//

import Foundation
import Combine

@MainActor
class OpenAITTSService: ObservableObject {
    static let shared = OpenAITTSService()

    private let baseURL = URL(string: "https://api.openai.com/v1/audio/speech")!

    private init() {}

    // MARK: - Errors

    enum OpenAITTSError: LocalizedError {
        case apiKeyMissing
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "OpenAI API key not configured. Please add it in Settings > API Keys."
            case .invalidResponse:
                return "Invalid response from OpenAI TTS API"
            case .apiError(let statusCode, let message):
                return "OpenAI TTS API error (\(statusCode)): \(message)"
            }
        }
    }

    // MARK: - TTS Generation

    /// Generate speech audio from text using OpenAI TTS
    /// - Parameters:
    ///   - text: The text to convert to speech (max 4096 characters)
    ///   - voice: The voice to use
    ///   - model: The TTS model to use
    ///   - speed: Speech speed multiplier (0.25 to 4.0)
    ///   - instructions: Voice instructions (only for gpt-4o-mini-tts)
    ///   - apiKey: OpenAI API key
    /// - Returns: Audio data (MP3 format by default)
    func generateSpeech(
        text: String,
        voice: OpenAITTSVoice,
        model: OpenAITTSModel,
        speed: Double = 1.0,
        instructions: String? = nil,
        apiKey: String
    ) async throws -> Data {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        var body: [String: Any] = [
            "model": model.rawValue,
            "input": text,
            "voice": voice.rawValue,
            "response_format": "mp3"
        ]

        // Add speed if not default
        if speed != 1.0 {
            // Clamp to valid range
            let clampedSpeed = min(max(speed, 0.25), 4.0)
            body["speed"] = clampedSpeed
        }

        // Add instructions for gpt-4o-mini-tts only
        if model.supportsInstructions, let instructions = instructions, !instructions.isEmpty {
            body["instructions"] = instructions
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[OpenAITTSService] Generating speech with voice: \(voice.rawValue), model: \(model.rawValue)")
        if let instructions = instructions, !instructions.isEmpty, model.supportsInstructions {
            print("[OpenAITTSService] Instructions: \(instructions)")
        }
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITTSError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            #if DEBUG
            print("[OpenAITTSService] Error: \(errorMessage)")
            #endif
            throw OpenAITTSError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        #if DEBUG
        print("[OpenAITTSService] Received audio data: \(data.count) bytes")
        #endif

        // OpenAI returns raw audio bytes directly (not JSON wrapped)
        return data
    }
}
