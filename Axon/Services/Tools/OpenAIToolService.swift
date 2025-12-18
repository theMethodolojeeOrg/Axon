//
//  OpenAIToolService.swift
//  Axon
//
//  Native OpenAI tool execution service for Web Search, Image Generation, and Deep Research.
//  Calls OpenAI API directly with tools enabled - no backend proxy needed.
//

import Foundation
import CoreLocation

// MARK: - OpenAI Tool Service

@MainActor
class OpenAIToolService {
    static let shared = OpenAIToolService()

    private init() {}

    // MARK: - Web Search

    /// Execute a web search query using OpenAI's search-enabled models
    /// Uses gpt-4o-search-preview or gpt-4o-mini-search-preview
    func webSearch(
        apiKey: String,
        query: String,
        model: String = "gpt-4o-search-preview",
        userLocation: UserLocationContext? = nil
    ) async throws -> OpenAIWebSearchResponse {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build web_search_options
        var webSearchOptions: [String: Any] = [:]
        if let location = userLocation {
            webSearchOptions["user_location"] = [
                "type": "approximate",
                "approximate": location.toDictionary()
            ]
        }

        // Build request body
        let body: [String: Any] = [
            "model": model,
            "web_search_options": webSearchOptions,
            "messages": [
                ["role": "user", "content": query]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[OpenAIToolService] Web search request with model: \(model)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIToolError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[OpenAIToolService] Error: \(errorText)")
            }
            throw OpenAIToolError.apiError(statusCode: httpResponse.statusCode)
        }

        // Decode response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let chatResponse = try decoder.decode(OpenAIChatResponse.self, from: data)

        return parseWebSearchResponse(chatResponse)
    }

    // MARK: - Image Generation

    /// Generate images using OpenAI's GPT Image models
    /// Supports gpt-image-1 (default), gpt-image-1.5, gpt-image-1-mini
    func generateImage(
        apiKey: String,
        prompt: String,
        model: String = "gpt-image-1",
        size: ImageSize = .square1024,
        quality: ImageQuality = .auto,
        outputFormat: ImageOutputFormat = .png,
        n: Int = 1
    ) async throws -> OpenAIImageResponse {
        let url = URL(string: "https://api.openai.com/v1/images/generations")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": n,
            "size": size.rawValue,
            "output_format": outputFormat.rawValue
        ]

        // Quality is only supported by certain models
        if model != "gpt-image-1-mini" {
            body["quality"] = quality.rawValue
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[OpenAIToolService] Image generation request with model: \(model)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIToolError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[OpenAIToolService] Error: \(errorText)")
            }
            throw OpenAIToolError.apiError(statusCode: httpResponse.statusCode)
        }

        // Decode response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenAIImageResponse.self, from: data)
    }

    // MARK: - Deep Research

    /// Execute deep research using OpenAI's Responses API with o3-deep-research or o4-mini-deep-research
    /// This is an async operation that may take several minutes
    func deepResearch(
        apiKey: String,
        query: String,
        model: String = "o3-deep-research",
        reasoningEffort: ReasoningEffort = .medium
    ) async throws -> OpenAIDeepResearchResponse {
        let url = URL(string: "https://api.openai.com/v1/responses")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        // Deep research can take a while - extend timeout
        request.timeoutInterval = 600 // 10 minutes

        // Build request body with web_search tool enabled
        let body: [String: Any] = [
            "model": model,
            "input": query,
            "tools": [
                ["type": "web_search"]
            ],
            "reasoning": [
                "effort": reasoningEffort.rawValue
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[OpenAIToolService] Deep research request with model: \(model), effort: \(reasoningEffort.rawValue)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIToolError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[OpenAIToolService] Error: \(errorText)")
            }
            throw OpenAIToolError.apiError(statusCode: httpResponse.statusCode)
        }

        // Decode response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OpenAIDeepResearchResponse.self, from: data)
    }

    // MARK: - Private Helpers

    private func parseWebSearchResponse(_ response: OpenAIChatResponse) -> OpenAIWebSearchResponse {
        guard let choice = response.choices.first else {
            return OpenAIWebSearchResponse(
                text: "",
                citations: [],
                model: response.model
            )
        }

        let citations = choice.message.annotations?.compactMap { annotation -> OpenAICitation? in
            guard case .urlCitation(let citation) = annotation else { return nil }
            return citation
        } ?? []

        return OpenAIWebSearchResponse(
            text: choice.message.content ?? "",
            citations: citations,
            model: response.model
        )
    }
}

// MARK: - Response Types

struct OpenAIWebSearchResponse {
    let text: String
    let citations: [OpenAICitation]
    let model: String

    var hasCitations: Bool {
        !citations.isEmpty
    }

    /// Format citations as markdown for display
    var formattedCitations: String {
        guard !citations.isEmpty else { return "" }

        var result = "\n\n**Sources:**\n"
        for citation in citations {
            result += "- [\(citation.title ?? citation.url)](\(citation.url))\n"
        }
        return result
    }
}

struct OpenAIImageResponse: Decodable {
    let created: Int
    let data: [ImageData]

    struct ImageData: Decodable {
        let b64Json: String?
        let url: String?
        let revisedPrompt: String?
    }

    /// Get the first image URL or base64 data
    var firstImage: ImageData? {
        data.first
    }
}

struct OpenAIDeepResearchResponse: Decodable {
    let id: String
    let status: String
    let output: [OutputItem]?
    let usage: UsageInfo?

    struct OutputItem: Decodable {
        let type: String
        let text: String?
        let annotations: [AnnotationWrapper]?
    }

    struct AnnotationWrapper: Decodable {
        let type: String
        let urlCitation: URLCitationInfo?

        enum CodingKeys: String, CodingKey {
            case type
            case urlCitation = "url_citation"
        }
    }

    struct URLCitationInfo: Decodable {
        let url: String
        let title: String?
        let startIndex: Int?
        let endIndex: Int?
    }

    struct UsageInfo: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?
    }

    /// Get the main text content from the response
    var text: String {
        output?.first(where: { $0.type == "message" })?.text ?? ""
    }

    /// Get all citations from the response
    var citations: [OpenAICitation] {
        output?.flatMap { item in
            item.annotations?.compactMap { wrapper -> OpenAICitation? in
                guard wrapper.type == "url_citation",
                      let citation = wrapper.urlCitation else { return nil }
                return OpenAICitation(
                    url: citation.url,
                    title: citation.title,
                    startIndex: citation.startIndex,
                    endIndex: citation.endIndex
                )
            } ?? []
        } ?? []
    }
}

// MARK: - Chat Completions Response Models

struct OpenAIChatResponse: Decodable {
    let id: String
    let model: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let index: Int
        let message: Message
        let finishReason: String?
    }

    struct Message: Decodable {
        let role: String
        let content: String?
        let annotations: [Annotation]?
    }

    enum Annotation: Decodable {
        case urlCitation(OpenAICitation)
        case unknown

        enum CodingKeys: String, CodingKey {
            case type
            case urlCitation = "url_citation"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "url_citation":
                let citation = try container.decode(OpenAICitation.self, forKey: .urlCitation)
                self = .urlCitation(citation)
            default:
                self = .unknown
            }
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?
    }
}

struct OpenAICitation: Decodable {
    let url: String
    let title: String?
    let startIndex: Int?
    let endIndex: Int?
}

// MARK: - User Location Context

struct UserLocationContext {
    let country: String?  // ISO 3166-1 two-letter code (e.g., "US")
    let city: String?
    let region: String?
    let timezone: String?  // IANA timezone (e.g., "America/Chicago")

    func toDictionary() -> [String: String] {
        var dict: [String: String] = [:]
        if let country = country { dict["country"] = country }
        if let city = city { dict["city"] = city }
        if let region = region { dict["region"] = region }
        if let timezone = timezone { dict["timezone"] = timezone }
        return dict
    }

    /// Create from CLLocationCoordinate2D (requires reverse geocoding externally)
    static func from(coordinate: CLLocationCoordinate2D) -> UserLocationContext {
        // Note: In a real implementation, you'd reverse geocode the coordinate
        // For now, return a minimal context
        return UserLocationContext(
            country: nil,
            city: nil,
            region: nil,
            timezone: TimeZone.current.identifier
        )
    }
}

// MARK: - Enums for Image Generation

enum ImageSize: String {
    case square1024 = "1024x1024"
    case landscape1792 = "1792x1024"
    case portrait1024 = "1024x1792"
    case auto = "auto"
}

enum ImageQuality: String {
    case auto = "auto"
    case low = "low"
    case medium = "medium"
    case high = "high"
}

enum ImageOutputFormat: String {
    case png = "png"
    case jpeg = "jpeg"
    case webp = "webp"
}

enum ReasoningEffort: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

// MARK: - Errors

enum OpenAIToolError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case toolNotSupported(String)
    case missingApiKey
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let statusCode):
            return "OpenAI API error (status \(statusCode))"
        case .toolNotSupported(let tool):
            return "Tool '\(tool)' is not supported"
        case .missingApiKey:
            return "OpenAI API key is required for tool use"
        case .timeout:
            return "Request timed out"
        }
    }
}
