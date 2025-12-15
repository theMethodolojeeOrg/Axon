//
//  GeminiToolService.swift
//  Axon
//
//  Native Gemini tool execution service for Google Search, Code Execution, URL Context, and Maps
//  Calls Gemini API directly with tools enabled - no backend proxy needed
//

import Foundation
import CoreLocation
import Combine

// MARK: - Gemini Tool Service

@MainActor
class GeminiToolService: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    
    static let shared = GeminiToolService()

    private init() {}

    // MARK: - Tool-Enabled Generation

    /// Execute a Gemini request with tools enabled
    func generateWithTools(
        apiKey: String,
        model: String,
        messages: [Message],
        system: String?,
        enabledTools: Set<ToolId>,
        userLocation: CLLocationCoordinate2D? = nil
    ) async throws -> GeminiToolResponse {
        let modelId = model.starts(with: "models/") ? model : "models/\(model)"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build contents array
        var contents: [[String: Any]] = []
        for msg in messages where msg.role != .system {
            let role = msg.role == .user ? "user" : "model"
            let parts = buildGeminiParts(for: msg)
            contents.append([
                "role": role,
                "parts": parts
            ])
        }

        // Build tools array
        let tools = buildToolsArray(enabledTools: enabledTools)

        // Build tool config (for location context with Maps)
        var toolConfig: [String: Any]? = nil
        if enabledTools.contains(.googleMaps), let location = userLocation {
            toolConfig = [
                "retrievalConfig": [
                    "latLng": [
                        "latitude": location.latitude,
                        "longitude": location.longitude
                    ]
                ]
            ]
        }

        // Build request body
        var body: [String: Any] = [
            "contents": contents
        ]

        if !tools.isEmpty {
            body["tools"] = tools
        }

        if let system = system {
            body["system_instruction"] = ["parts": [["text": system]]]
        }

        if let toolConfig = toolConfig {
            body["toolConfig"] = toolConfig
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        #if DEBUG
        print("[GeminiToolService] Sending request with tools: \(enabledTools.map { $0.rawValue })")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiToolError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[GeminiToolService] Error: \(errorText)")
            }
            throw GeminiToolError.apiError(statusCode: httpResponse.statusCode)
        }

        // Decode response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let geminiResponse = try decoder.decode(GeminiAPIResponse.self, from: data)

        return parseToolResponse(geminiResponse)
    }

    // MARK: - Private Helpers

    private func buildToolsArray(enabledTools: Set<ToolId>) -> [[String: Any]] {
        var tools: [[String: Any]] = []

        // Google Search (Grounding)
        if enabledTools.contains(.googleSearch) {
            tools.append(["google_search": [:]])
        }

        // Code Execution
        if enabledTools.contains(.codeExecution) {
            tools.append(["code_execution": [:]])
        }

        // URL Context
        if enabledTools.contains(.urlContext) {
            tools.append(["url_context": [:]])
        }

        // Google Maps (not supported in Gemini 3)
        if enabledTools.contains(.googleMaps) {
            tools.append(["google_maps": [:]])
        }

        // File Search (RAG-based document search)
        // Note: Requires a FileSearchStore to be created and files imported
        // For now, we include it as an empty config - the store names would need to be passed
        if enabledTools.contains(.fileSearch) {
            // File search requires file_search_store_names to be useful
            // This is a placeholder - full implementation would need store management
            tools.append(["file_search": [:]])
        }

        return tools
    }

    private func buildGeminiParts(for message: Message) -> [[String: Any]] {
        var parts: [[String: Any]] = []
        let trimmedText = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
            parts.append(["text": trimmedText])
        }

        for attachment in message.attachments ?? [] {
            let mimeType = resolvedMimeType(for: attachment)

            if let base64 = attachment.base64 {
                // Inline data for base64 encoded content (files <20MB)
                parts.append([
                    "inline_data": [
                        "mime_type": mimeType,
                        "data": base64
                    ]
                ])
            } else if let url = attachment.url {
                // File data for URLs - include mime_type for all media types
                // Per Gemini docs: mime_type is crucial for PDFs, audio, and video
                var fileData: [String: Any] = ["file_uri": url]

                if attachment.type == .document || attachment.type == .audio || attachment.type == .video {
                    fileData["mime_type"] = mimeType
                }

                parts.append(["file_data": fileData])
            }
        }

        if parts.isEmpty {
            parts.append(["text": ""])
        }

        return parts
    }

    /// Resolve MIME type for attachment
    /// Supports all Gemini-compatible formats:
    /// - Video: MP4, MPEG, MOV, AVI, FLV, MPG, WEBM, WMV, 3GPP
    /// - Audio: WAV, MP3, AIFF, AAC, OGG, FLAC
    /// - Images: JPEG, PNG, GIF, WEBP
    /// - Documents: PDF, TXT
    private func resolvedMimeType(for attachment: MessageAttachment) -> String {
        // Already a valid MIME type
        if let mime = attachment.mimeType, mime.contains("/") {
            return mime
        }

        // Try to resolve from short format identifier
        if let mime = attachment.mimeType?.lowercased() {
            if let resolved = Self.mimeTypeMap[mime] {
                return resolved
            }
        }

        // Try to resolve from filename extension
        if let name = attachment.name?.lowercased() {
            let ext = (name as NSString).pathExtension
            if let resolved = Self.mimeTypeMap[ext] {
                return resolved
            }
        }

        // Fall back to default based on attachment type
        switch attachment.type {
        case .image: return "image/jpeg"
        case .document: return "application/pdf"
        case .audio: return "audio/mp3"
        case .video: return "video/mp4"
        }
    }

    /// MIME type mapping for common file extensions and format identifiers
    /// Based on Gemini API supported formats documentation
    private static let mimeTypeMap: [String: String] = [
        // Images
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "gif": "image/gif",
        "webp": "image/webp",

        // Video formats (Gemini supported)
        "mp4": "video/mp4",
        "m4v": "video/mp4",
        "mpeg": "video/mpeg",
        "mpg": "video/mpg",
        "mov": "video/mov",
        "avi": "video/avi",
        "flv": "video/x-flv",
        "webm": "video/webm",
        "wmv": "video/wmv",
        "3gp": "video/3gpp",
        "3gpp": "video/3gpp",

        // Audio formats (Gemini supported)
        "wav": "audio/wav",
        "mp3": "audio/mp3",
        "aiff": "audio/aiff",
        "aif": "audio/aiff",
        "aac": "audio/aac",
        "ogg": "audio/ogg",
        "flac": "audio/flac",
        "m4a": "audio/aac",
        "mpga": "audio/mpeg",

        // Documents
        "pdf": "application/pdf",
        "txt": "text/plain",
        "text": "text/plain",
    ]

    private func parseToolResponse(_ response: GeminiAPIResponse) -> GeminiToolResponse {
        guard let candidate = response.candidates?.first,
              let content = candidate.content else {
            return GeminiToolResponse(
                text: "",
                groundingMetadata: nil,
                executableCode: nil,
                codeExecutionResult: nil,
                urlContextMetadata: nil
            )
        }

        var textParts: [String] = []
        var executableCode: ExecutableCode? = nil
        var codeResult: CodeExecutionResult? = nil

        for part in content.parts {
            if let text = part.text {
                textParts.append(text)
            }
            if let code = part.executableCode {
                executableCode = code
            }
            if let result = part.codeExecutionResult {
                codeResult = result
            }
        }

        return GeminiToolResponse(
            text: textParts.joined(),
            groundingMetadata: candidate.groundingMetadata,
            executableCode: executableCode,
            codeExecutionResult: codeResult,
            urlContextMetadata: candidate.urlContextMetadata
        )
    }
}

// MARK: - Gemini Tool Response Types

struct GeminiToolResponse {
    let text: String
    let groundingMetadata: GroundingMetadata?
    let executableCode: ExecutableCode?
    let codeExecutionResult: CodeExecutionResult?
    let urlContextMetadata: URLContextMetadata?

    /// Combined text including code execution output if present
    var fullResponse: String {
        var result = text

        if let code = executableCode {
            result += "\n\n```\(code.language.lowercased())\n\(code.code)\n```"
        }

        if let codeResult = codeExecutionResult {
            if codeResult.outcome == "OUTCOME_OK" {
                result += "\n\nOutput:\n```\n\(codeResult.output ?? "")\n```"
            } else {
                result += "\n\nExecution failed: \(codeResult.outcome)"
            }
        }

        return result
    }

    /// Whether grounding sources are available
    var hasGroundingSources: Bool {
        groundingMetadata?.groundingChunks?.isEmpty == false
    }

    /// Get web sources for attribution
    var webSources: [GroundingChunk] {
        groundingMetadata?.groundingChunks ?? []
    }
}

// MARK: - Gemini API Response Models

struct GeminiAPIResponse: Decodable {
    let candidates: [GeminiCandidate]?
    let usageMetadata: UsageMetadata?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContent?
    let groundingMetadata: GroundingMetadata?
    let urlContextMetadata: URLContextMetadata?
}

struct GeminiContent: Decodable {
    let parts: [GeminiPart]
    let role: String?
}

struct GeminiPart: Decodable {
    let text: String?
    let executableCode: ExecutableCode?
    let codeExecutionResult: CodeExecutionResult?
    let inlineData: InlineData?
}

struct ExecutableCode: Decodable {
    let language: String
    let code: String
}

struct CodeExecutionResult: Decodable {
    let outcome: String
    let output: String?
}

struct InlineData: Decodable {
    let mimeType: String
    let data: String
}

struct UsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let toolUsePromptTokenCount: Int?
}

// MARK: - Grounding Metadata

struct GroundingMetadata: Decodable {
    let webSearchQueries: [String]?
    let searchEntryPoint: SearchEntryPoint?
    let groundingChunks: [GroundingChunk]?
    let groundingSupports: [GroundingSupport]?
    let googleMapsWidgetContextToken: String?
}

struct SearchEntryPoint: Decodable {
    let renderedContent: String?
}

struct GroundingChunk: Decodable, Identifiable {
    let web: WebChunk?
    let maps: MapsChunk?

    var id: String {
        web?.uri ?? maps?.uri ?? UUID().uuidString
    }

    var title: String {
        web?.title ?? maps?.title ?? "Source"
    }

    var uri: String? {
        web?.uri ?? maps?.uri
    }
}

struct WebChunk: Decodable {
    let uri: String?
    let title: String?
}

struct MapsChunk: Decodable {
    let uri: String?
    let title: String?
    let placeId: String?
}

struct GroundingSupport: Decodable {
    let segment: GroundingSegment?
    let groundingChunkIndices: [Int]?
}

struct GroundingSegment: Decodable {
    let startIndex: Int?
    let endIndex: Int?
    let text: String?
}

// MARK: - URL Context Metadata

struct URLContextMetadata: Decodable {
    let urlMetadata: [URLMetadataEntry]?
}

struct URLMetadataEntry: Decodable {
    let retrievedUrl: String?
    let urlRetrievalStatus: String?
}

// MARK: - Errors

enum GeminiToolError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case toolNotSupported(String)
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .apiError(let statusCode):
            return "Gemini API error (status \(statusCode))"
        case .toolNotSupported(let tool):
            return "Tool '\(tool)' is not supported"
        case .missingApiKey:
            return "Gemini API key is required for tool use"
        }
    }
}

