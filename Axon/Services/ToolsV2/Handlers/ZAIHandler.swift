//
//  ZAIHandler.swift
//  Axon
//
//  V2 Handler for zAI/GLM provider-native tools.
//  Supports all zai_* and glm_* tools.
//

import Foundation
import os.log

/// Handler for zAI/GLM provider-native tools
///
/// Registered handler: `zai`
///
/// Implements zAI/GLM native tool execution with web search, image generation,
/// video generation, and speech-to-text capabilities.
///
/// Supported tools:
/// - zai_web_search, glm_web_search - Web search
/// - glm_cogview_4 - Image generation with CogView-4
/// - glm_cogvideo_3 - Video generation with CogVideoX-3
/// - glm_speech_to_text - Speech transcription with GLM-ASR
@MainActor
final class ZAIHandler: ToolHandlerV2 {

    let handlerId = "zai"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ZAIHandler"
    )

    // MARK: - ToolHandlerV2

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        // Get API key from settings
        guard let apiKey = getZAIApiKey() else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "zAI API key not configured. Please add your API key in Settings."
            )
        }

        switch toolId {
        // Web search
        case "zai_web_search", "glm_web_search", "web_search":
            return await executeWebSearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Image generation
        case "glm_cogview_4":
            return await executeImageGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Video generation
        case "glm_cogvideo_3":
            return await executeVideoGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Speech to text
        case "glm_speech_to_text":
            return await executeSpeechToText(inputs: inputs, apiKey: apiKey, toolId: toolId)

        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown zAI tool: \(toolId)")
        }
    }

    // MARK: - Web Search

    private func executeWebSearch(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? ""

        guard !query.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Search query cannot be empty"
            )
        }

        logger.info("Executing zAI Web Search: \(query)")

        do {
            // zAI/GLM API endpoint
            let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": "glm-4-plus",
                "messages": [
                    ["role": "user", "content": query]
                ],
                "tools": [
                    ["type": "web_search", "web_search": ["enable": true]]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("zAI API error: \(errorText)")
                }
                throw ZAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            // Parse response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let chatResponse = try decoder.decode(ZAIChatResponse.self, from: data)

            let text = chatResponse.choices.first?.message.content ?? ""

            return ToolResultV2.success(
                toolId: toolId,
                output: text,
                structured: [
                    "query": query,
                    "model": chatResponse.model
                ]
            )
        } catch {
            logger.error("zAI Web Search failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Search failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Image Generation (CogView-4)

    private func executeImageGeneration(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let prompt = (inputs["prompt"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "cogView-4-250304"
        let size = (inputs["size"] as? String) ?? "1024x1024"

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Image prompt cannot be empty"
            )
        }

        logger.info("Executing GLM CogView-4 Image Generation: \(prompt)")

        do {
            let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/images/generations")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": model,
                "prompt": prompt,
                "size": size
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("zAI API error: \(errorText)")
                }
                throw ZAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let imageResponse = try decoder.decode(ZAIImageResponse.self, from: data)

            var output = "Image generated successfully.\n"
            if let firstImage = imageResponse.data.first {
                if let url = firstImage.url {
                    output += "URL: \(url)\n"
                }
            }

            return ToolResultV2.success(
                toolId: toolId,
                output: output,
                structured: [
                    "imageCount": imageResponse.data.count,
                    "imageUrl": imageResponse.data.first?.url ?? ""
                ]
            )
        } catch {
            logger.error("GLM CogView-4 failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Image generation failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Video Generation (CogVideoX-3)

    private func executeVideoGeneration(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let prompt = (inputs["prompt"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "cogvideox-3"
        let quality = (inputs["quality"] as? String) ?? "quality"
        let withAudio = (inputs["with_audio"] as? Bool) ?? true
        let size = (inputs["size"] as? String) ?? "1920x1080"
        let fps = (inputs["fps"] as? Int) ?? 30
        let imageUrl = inputs["image_url"] as? String

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Video prompt cannot be empty"
            )
        }

        logger.info("Executing GLM CogVideoX-3 Video Generation: \(prompt)")

        do {
            let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/videos/generations")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            var body: [String: Any] = [
                "model": model,
                "prompt": prompt,
                "quality": quality,
                "with_audio": withAudio,
                "size": size,
                "fps": fps
            ]

            if let imageUrl = imageUrl {
                body["image_url"] = imageUrl
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("zAI API error: \(errorText)")
                }
                throw ZAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let videoResponse = try decoder.decode(ZAIVideoResponse.self, from: data)

            var output = "Video generation initiated.\n"
            output += "Task ID: \(videoResponse.id ?? "unknown")\n"
            if let status = videoResponse.taskStatus {
                output += "Status: \(status)\n"
            }

            return ToolResultV2.success(
                toolId: toolId,
                output: output,
                structured: [
                    "taskId": videoResponse.id ?? "",
                    "status": videoResponse.taskStatus ?? "pending"
                ]
            )
        } catch {
            logger.error("GLM CogVideoX-3 failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Video generation failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Speech to Text (GLM-ASR)

    private func executeSpeechToText(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let filePath = (inputs["file"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "glm-asr-2512"
        let stream = (inputs["stream"] as? Bool) ?? false

        guard !filePath.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Audio file path is required"
            )
        }

        logger.info("Executing GLM Speech to Text: \(filePath)")

        do {
            // Read audio file
            let fileURL = URL(fileURLWithPath: filePath)
            let audioData = try Data(contentsOf: fileURL)
            let base64Audio = audioData.base64EncodedString()

            let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": model,
                "file": base64Audio,
                "stream": stream
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("zAI API error: \(errorText)")
                }
                throw ZAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let transcriptionResponse = try decoder.decode(ZAITranscriptionResponse.self, from: data)

            return ToolResultV2.success(
                toolId: toolId,
                output: transcriptionResponse.text,
                structured: [
                    "text": transcriptionResponse.text,
                    "duration": transcriptionResponse.duration ?? 0
                ]
            )
        } catch {
            logger.error("GLM Speech to Text failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Transcription failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private func getZAIApiKey() -> String? {
        guard let key = try? APIKeysStorage.shared.getAPIKey(for: .zai),
              !key.isEmpty else {
            return nil
        }
        return key
    }
}

// MARK: - Response Types

private struct ZAIChatResponse: Decodable {
    let id: String
    let model: String
    let choices: [Choice]

    struct Choice: Decodable {
        let index: Int
        let message: Message
        let finishReason: String?
    }

    struct Message: Decodable {
        let role: String
        let content: String?
    }
}

private struct ZAIImageResponse: Decodable {
    let created: Int?
    let data: [ImageData]

    struct ImageData: Decodable {
        let url: String?
        let b64Json: String?
    }
}

private struct ZAIVideoResponse: Decodable {
    let id: String?
    let taskStatus: String?
    let videoResult: [VideoData]?

    struct VideoData: Decodable {
        let url: String?
        let coverImageUrl: String?
    }
}

private struct ZAITranscriptionResponse: Decodable {
    let text: String
    let duration: Double?
}

// MARK: - Errors

private enum ZAIToolError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from zAI API"
        case .apiError(let statusCode):
            return "zAI API error (status \(statusCode))"
        case .missingApiKey:
            return "zAI API key is required"
        }
    }
}
