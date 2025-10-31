//
//  ElevenLabsService.swift
//  Axon
//
//  Service to talk to NeurX Cloud Function that proxies ElevenLabs API
//

import Foundation

@MainActor
final class ElevenLabsService: ObservableObject {
    static let shared = ElevenLabsService()

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
}
