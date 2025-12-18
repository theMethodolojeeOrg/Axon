//
//  GeminiMediaProxyService.swift
//  Axon
//
//  Proxy service that uses Gemini to understand video/audio attachments
//  when the primary model doesn't support them (Claude, GPT, Grok).
//
//  Flow:
//  1. Detect video/audio attachments in user message
//  2. Send to Gemini for understanding/transcription
//  3. Replace attachment with text description
//  4. Forward to primary model with enriched context
//

import Foundation
import Combine

@MainActor
class GeminiMediaProxyService: ObservableObject {
    static let shared = GeminiMediaProxyService()

    private init() {}

    // MARK: - Media Processing

    /// Process attachments that the target model doesn't support
    /// Returns modified attachments array and additional context text
    func processUnsupportedMedia(
        attachments: [MessageAttachment],
        targetProvider: String,
        geminiApiKey: String,
        userPrompt: String
    ) async throws -> MediaProxyResult {
        // Determine what the target provider supports
        let unsupportedTypes = getUnsupportedTypes(for: targetProvider)

        // Filter attachments that need proxying
        let toProxy = attachments.filter { unsupportedTypes.contains($0.type) }
        let supported = attachments.filter { !unsupportedTypes.contains($0.type) }

        guard !toProxy.isEmpty else {
            // Nothing to proxy
            return MediaProxyResult(
                processedAttachments: attachments,
                additionalContext: nil,
                proxiedCount: 0
            )
        }

        print("[GeminiMediaProxy] Processing \(toProxy.count) unsupported attachments for \(targetProvider)")

        // Process each unsupported attachment through Gemini
        var contextParts: [String] = []

        for attachment in toProxy {
            let description = try await processAttachment(
                attachment,
                geminiApiKey: geminiApiKey,
                userPrompt: userPrompt
            )
            contextParts.append(description)
        }

        // Build context block
        let context = buildContextBlock(contextParts, originalPrompt: userPrompt)

        return MediaProxyResult(
            processedAttachments: supported,
            additionalContext: context,
            proxiedCount: toProxy.count
        )
    }

    // MARK: - Provider Capability Detection

    private func getUnsupportedTypes(for provider: String) -> Set<MessageAttachment.AttachmentType> {
        switch provider {
        case "anthropic":
            // Claude: no video, no audio
            return [.video, .audio]

        case "openai":
            // GPT-4o: supports audio input, no video
            return [.video]

        case "grok":
            // Grok: images only
            return [.video, .audio]

        case "gemini":
            // Gemini supports everything
            return []

        default:
            // Conservative: assume only images
            return [.video, .audio]
        }
    }

    // MARK: - Gemini Processing

    private func processAttachment(
        _ attachment: MessageAttachment,
        geminiApiKey: String,
        userPrompt: String
    ) async throws -> String {
        let model = "gemini-2.5-flash"
        let modelId = "models/\(model)"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelId):generateContent?key=\(geminiApiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the prompt based on attachment type
        let analysisPrompt = buildAnalysisPrompt(for: attachment, userPrompt: userPrompt)

        // Build parts array
        var parts: [[String: Any]] = []

        // Add the media
        if let base64 = attachment.base64 {
            let mimeType = attachment.mimeType ?? defaultMimeType(for: attachment.type)
            
            // Check file size for inline data (Gemini limit is 20MB)
            if let data = Data(base64Encoded: base64) {
                let fileSizeMB = Double(data.count) / (1024 * 1024)
                if fileSizeMB > 20 {
                    print("[GeminiMediaProxy] Warning: Attachment '\(attachment.name ?? "unknown")' is \(String(format: "%.1f", fileSizeMB))MB, which exceeds Gemini's 20MB inline limit.")
                }
            }

            parts.append([
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64
                ]
            ])
        } else if let fileUrl = attachment.url {
            var fileData: [String: Any] = ["file_uri": fileUrl]
            
            // Always include mime_type for file_data to be safe
            let mimeType = attachment.mimeType ?? defaultMimeType(for: attachment.type)
            fileData["mime_type"] = mimeType
            
            parts.append(["file_data": fileData])
        }

        // Add the analysis prompt
        parts.append(["text": analysisPrompt])

        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 2048
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("[GeminiMediaProxy] Sending \(attachment.type.rawValue) to Gemini for analysis")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("[GeminiMediaProxy] Error: \(errorText)")
            }
            throw GeminiMediaProxyError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        // Parse response
        let decoded = try JSONDecoder().decode(GeminiProxyResponse.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?.first?.text ?? ""

        print("[GeminiMediaProxy] Received analysis: \(text.prefix(100))...")

        return text
    }

    private func buildAnalysisPrompt(for attachment: MessageAttachment, userPrompt: String) -> String {
        let fileName = attachment.name ?? "media file"

        switch attachment.type {
        case .video:
            return """
            Analyze this video file "\(fileName)" thoroughly. The user's question is: "\(userPrompt)"

            Provide:
            1. A detailed description of what happens in the video
            2. Any text, speech, or dialogue (with timestamps if relevant)
            3. Key visual elements, people, objects, or scenes
            4. Any information relevant to the user's question

            Format your response as a clear, detailed description that another AI can use to answer the user's question about this video.
            """

        case .audio:
            return """
            Analyze this audio file "\(fileName)" thoroughly. The user's question is: "\(userPrompt)"

            Provide:
            1. A complete transcription of any speech
            2. Description of music, sounds, or audio elements
            3. Speaker identification if multiple speakers
            4. Any information relevant to the user's question

            Format your response as a clear transcription and description that another AI can use to answer the user's question about this audio.
            """

        default:
            return "Describe the contents of this file in detail."
        }
    }

    private func buildContextBlock(_ descriptions: [String], originalPrompt: String) -> String {
        if descriptions.count == 1 {
            return """
            [Media Analysis from Gemini]
            The user attached media that has been analyzed. Here is the analysis:

            \(descriptions[0])

            [End of Media Analysis]
            """
        } else {
            var block = "[Media Analysis from Gemini]\nThe user attached \(descriptions.count) media files that have been analyzed:\n\n"
            for (index, desc) in descriptions.enumerated() {
                block += "--- Media \(index + 1) ---\n\(desc)\n\n"
            }
            block += "[End of Media Analysis]"
            return block
        }
    }

    private func defaultMimeType(for type: MessageAttachment.AttachmentType) -> String {
        switch type {
        case .video: return "video/mp4"
        case .audio: return "audio/mp3"
        case .image: return "image/jpeg"
        case .document: return "application/pdf"
        }
    }
}

// MARK: - Result Types

struct MediaProxyResult {
    /// Attachments that the target model can handle (unsupported ones removed)
    let processedAttachments: [MessageAttachment]

    /// Text context from Gemini analysis of unsupported media
    let additionalContext: String?

    /// Number of attachments that were proxied through Gemini
    let proxiedCount: Int

    var hadProxiedMedia: Bool {
        proxiedCount > 0
    }
}

// MARK: - Response Models

private struct GeminiProxyResponse: Decodable {
    let candidates: [GeminiProxyCandidate]?
}

private struct GeminiProxyCandidate: Decodable {
    let content: GeminiProxyContent?
}

private struct GeminiProxyContent: Decodable {
    let parts: [GeminiProxyPart]?
}

private struct GeminiProxyPart: Decodable {
    let text: String?
}

// MARK: - Errors

enum GeminiMediaProxyError: LocalizedError {
    case apiError(statusCode: Int)
    case noGeminiKey
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let statusCode):
            return "Gemini media proxy error (status \(statusCode))"
        case .noGeminiKey:
            return "Gemini API key required for media proxy"
        case .processingFailed(let reason):
            return "Media processing failed: \(reason)"
        }
    }
}
