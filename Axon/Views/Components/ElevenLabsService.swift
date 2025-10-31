//
//  ElevenLabsService.swift
//  Axon
//
//  Service to talk to NeurX Cloud Function that proxies ElevenLabs API
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class ElevenLabsService: ObservableObject {
    static let shared = ElevenLabsService()
    nonisolated let objectWillChange = ObservableObjectPublisher()

    private let auth = AuthenticationService.shared
    private let session: URLSession = .shared
    private let endpoint = URL(string: "https://us-central1-neurx-8f122.cloudfunctions.net/apiElevenLabs")!

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
    
    struct TTSRequest: Codable {
        let action: String
        let text: String
        let voiceId: String
        let model: String
        let format: String
        let voiceSettings: VoiceSettingsPayload
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

    struct TTSResponse: Codable {
        let success: Bool
        let audio: String? // data URL
    }

    private init() {}

    // MARK: - Public API

    func fetchVoices() async throws -> [ELVoice] {
        let token = try await auth.getIdToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["action": "voices_list"])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        struct VoicesEnvelope: Codable { let voices: [ELVoice] }
        if let env = try? JSONDecoder().decode(VoicesEnvelope.self, from: data) {
            return env.voices
        }
        if let arr = try? JSONDecoder().decode([ELVoice].self, from: data) {
            return arr
        }
        return []
    }

    func fetchTTSModels() async throws -> [ELTTSModel] {
        let token = try await auth.getIdToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["action": "models_list"])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        struct ModelsEnvelope: Codable { let models: [ELTTSModel] }
        if let env = try? JSONDecoder().decode(ModelsEnvelope.self, from: data) {
            return env.models
        }
        if let arr = try? JSONDecoder().decode([ELTTSModel].self, from: data) {
            return arr
        }
        return []
    }

    func generateTTSBase64(text: String, voiceId: String, model: String, format: String, voiceSettings: VoiceSettingsPayload) async throws -> Data {
        let token = try await auth.getIdToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let payload = TTSRequest(action: "tts_generate_base64", text: text, voiceId: voiceId, model: model, format: format, voiceSettings: voiceSettings)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "ElevenLabsService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let decoded = try JSONDecoder().decode(TTSResponse.self, from: data)
        guard let dataURL = decoded.audio, let comma = dataURL.firstIndex(of: ",") else {
            throw NSError(domain: "ElevenLabsService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid audio response"])
        }
        let base64 = String(dataURL[dataURL.index(after: comma)...])
        guard let audioData = Data(base64Encoded: base64) else {
            throw NSError(domain: "ElevenLabsService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 audio"])
        }
        return audioData
    }
}
