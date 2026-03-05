//
//  ElevenLabsService.swift
//  Axon
//
//  Direct ElevenLabs client (no NeurX proxy)
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class ElevenLabsService: ObservableObject {
    static let shared = ElevenLabsService()
    nonisolated let objectWillChange = ObservableObjectPublisher()

    private let session: URLSession = .shared

    private let baseURL = URL(string: "https://api.elevenlabs.io/v1")!

    struct ELVoice: Identifiable, Codable, Equatable {
        let id: String
        let name: String
        let category: String?
        let language: String?

        enum CodingKeys: String, CodingKey {
            case id = "voice_id"
            case name
            case category
            case language
        }
    }

    struct ELTTSModel: Identifiable, Codable, Equatable {
        let id: String
        let name: String

        var displayName: String { name.isEmpty ? id : name }

        enum CodingKeys: String, CodingKey {
            case id = "model_id"
            case name
        }
    }

    struct VoiceSettingsPayload: Codable {
        let stability: Double
        let similarityBoost: Double
        let style: Double
        let useSpeakerBoost: Bool

        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
            case style
            case useSpeakerBoost = "use_speaker_boost"
        }
    }

    private init() {}

    // MARK: - Errors

    enum ElevenLabsError: LocalizedError {
        case apiKeyMissing
        case badResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "ElevenLabs API key not configured. Please add it in Settings > API Keys."
            case .badResponse:
                return "Invalid response from ElevenLabs"
            case .httpError(let code, let message):
                return "ElevenLabs error (\(code)): \(message)"
            }
        }
    }

    // MARK: - Key access

    private func requireAPIKey() throws -> String {
        guard let key = try? APIKeysStorage.shared.getAPIKey(for: .elevenlabs),
              !key.isEmpty else {
            throw ElevenLabsError.apiKeyMissing
        }
        return key
    }

    private func makeRequest(url: URL, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let apiKey = try requireAPIKey()
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = body
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ElevenLabsError.httpError(http.statusCode, message)
        }
        return data
    }

    // MARK: - Public API

    func fetchVoices() async throws -> [ELVoice] {
        let url = baseURL.appendingPathComponent("voices")
        let request = try makeRequest(url: url)
        let data = try await validatedData(for: request)

        struct VoicesEnvelope: Codable {
            let voices: [ELVoice]
        }
        let env = try JSONDecoder().decode(VoicesEnvelope.self, from: data)
        return env.voices
    }

    func fetchTTSModels() async throws -> [ELTTSModel] {
        let url = baseURL.appendingPathComponent("models")
        let request = try makeRequest(url: url)
        let data = try await validatedData(for: request)

        // ElevenLabs returns an array of models
        return try JSONDecoder().decode([ELTTSModel].self, from: data)
    }

    /// Generate audio bytes from ElevenLabs.
    /// This returns raw audio bytes (mp3) rather than a data URL.
    func generateTTSBase64(
        text: String,
        voiceId: String,
        model: String,
        format: String,
        voiceSettings: VoiceSettingsPayload,
        optimizeStreamingLatency: Int? = nil,
        seed: Int? = nil,
        previousText: String? = nil,
        nextText: String? = nil
    ) async throws -> Data {
        // NOTE: despite the legacy name "generateTTSBase64", we now return raw audio bytes.
        // The call sites treat this as Data and hand it to AVAudioPlayer.

        // ElevenLabs TTS endpoint
        var url = baseURL
            .appendingPathComponent("text-to-speech")
            .appendingPathComponent(voiceId)

        if !format.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "output_format", value: format)]
            if let updated = components.url {
                url = updated
            }
        }

        struct Payload: Codable {
            struct VoiceSettings: Codable {
                let stability: Double
                let similarity_boost: Double
                let style: Double
                let use_speaker_boost: Bool
            }

            let text: String
            let model_id: String
            let voice_settings: VoiceSettings
            let optimize_streaming_latency: Int?
            let seed: Int?
            let previous_text: String?
            let next_text: String?
        }

        let payload = Payload(
            text: text,
            model_id: model,
            voice_settings: Payload.VoiceSettings(
                stability: voiceSettings.stability,
                similarity_boost: voiceSettings.similarityBoost,
                style: voiceSettings.style,
                use_speaker_boost: voiceSettings.useSpeakerBoost
            ),
            optimize_streaming_latency: optimizeStreamingLatency,
            seed: seed,
            previous_text: previousText,
            next_text: nextText
        )

        var request = try makeRequest(url: url, method: "POST", body: try JSONEncoder().encode(payload))

        // Request audio output (format controlled via output_format query param when supported).
        request.addValue("audio/*", forHTTPHeaderField: "Accept")

        let data = try await validatedData(for: request)
        return data
    }


    func transcribeSpeech(
        fileURL: URL?,
        cloudStorageUrl: String?,
        modelId: String,
        languageCode: String?,
        diarize: Bool?,
        tagAudioEvents: Bool?,
        numSpeakers: Int?,
        diarizationThreshold: Double?,
        useMultiChannel: Bool?,
        webhook: Bool?
    ) async throws -> String {
        let url = baseURL.appendingPathComponent("speech-to-text")

        if let cloudStorageUrl {
            var body: [String: Any] = [
                "cloud_storage_url": cloudStorageUrl,
                "model_id": modelId
            ]
            if let languageCode { body["language_code"] = languageCode }
            if let diarize { body["diarize"] = diarize }
            if let tagAudioEvents { body["tag_audio_events"] = tagAudioEvents }
            if let numSpeakers { body["num_speakers"] = numSpeakers }
            if let diarizationThreshold { body["diarization_threshold"] = diarizationThreshold }
            if let useMultiChannel { body["use_multi_channel"] = useMultiChannel }
            if let webhook { body["webhook"] = webhook }

            let request = try makeRequest(url: url, method: "POST", body: JSONSerialization.data(withJSONObject: body))
            let data = try await validatedData(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return text
            }
            throw ElevenLabsError.badResponse
        }

        guard let fileURL else {
            throw ElevenLabsError.badResponse
        }

        let apiKey = try requireAPIKey()
        let boundary = UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // File
        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        appendField("model_id", modelId)
        if let languageCode { appendField("language_code", languageCode) }
        if let diarize { appendField("diarize", diarize ? "true" : "false") }
        if let tagAudioEvents { appendField("tag_audio_events", tagAudioEvents ? "true" : "false") }
        if let numSpeakers { appendField("num_speakers", String(numSpeakers)) }
        if let diarizationThreshold { appendField("diarization_threshold", String(diarizationThreshold)) }
        if let useMultiChannel { appendField("use_multi_channel", useMultiChannel ? "true" : "false") }
        if let webhook { appendField("webhook", webhook ? "true" : "false") }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data = try await validatedData(for: request)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            return text
        }
        throw ElevenLabsError.badResponse
    }
}

