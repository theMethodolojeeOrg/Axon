//
//  XAIHandler.swift
//  Axon
//
//  V2 Handler for xAI/Grok provider-native tools.
//  Supports all grok_* and xai_* tools.
//

import Foundation
import os.log

/// Handler for xAI/Grok provider-native tools
///
/// Registered handler: `xai`
///
/// Implements xAI/Grok native tool execution with live search, X search,
/// image generation, and code execution capabilities.
///
/// Supported tools:
/// - xai_web_search, grok_web_search - Web search with live data
/// - grok_x_search - X (Twitter) search
/// - grok_image_generation - Image generation with Grok-2 Image
/// - grok_image_understanding - Image understanding/vision
/// - grok_code_execution - Python code execution
@MainActor
final class XAIHandler: ToolHandlerV2 {

    let handlerId = "xai"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "XAIHandler"
    )

    // MARK: - ToolHandlerV2

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        // Get API key from settings
        guard let apiKey = getXAIApiKey() else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "xAI API key not configured. Please add your API key in Settings."
            )
        }

        switch toolId {
        // Web search
        case "xai_web_search", "grok_web_search", "web_search":
            return await executeWebSearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // X (Twitter) search
        case "grok_x_search":
            return await executeXSearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Image generation
        case "grok_image_generation":
            return await executeImageGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Image understanding
        case "grok_image_understanding":
            return await executeImageUnderstanding(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Code execution
        case "grok_code_execution":
            return await executeCodeExecution(inputs: inputs, apiKey: apiKey, toolId: toolId)

        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown xAI tool: \(toolId)")
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

        logger.info("Executing xAI Web Search: \(query)")

        do {
            // xAI API endpoint (compatible with OpenAI format)
            let url = URL(string: "https://api.x.ai/v1/chat/completions")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            // Build request with live search enabled
            let body: [String: Any] = [
                "model": "grok-3",
                "messages": [
                    ["role": "user", "content": query]
                ],
                "search": [
                    "mode": "auto"
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("xAI API error: \(errorText)")
                }
                throw XAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            // Parse response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let chatResponse = try decoder.decode(XAIChatResponse.self, from: data)

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
            logger.error("xAI Web Search failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Search failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - X Search

    private func executeXSearch(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? ""
        let allowedHandles = inputs["allowed_x_handles"] as? [String]
        let excludedHandles = inputs["excluded_x_handles"] as? [String]
        let fromDate = inputs["from_date"] as? String
        let toDate = inputs["to_date"] as? String
        let enableImageUnderstanding = (inputs["enable_image_understanding"] as? Bool) ?? false
        let enableVideoUnderstanding = (inputs["enable_video_understanding"] as? Bool) ?? false

        guard !query.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Search query cannot be empty"
            )
        }

        logger.info("Executing Grok X Search: \(query)")

        do {
            let url = URL(string: "https://api.x.ai/v1/chat/completions")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            // Build X search configuration
            var xSearchConfig: [String: Any] = [
                "mode": "on"
            ]

            if let allowed = allowedHandles, !allowed.isEmpty {
                xSearchConfig["allowed_x_handles"] = allowed
            }
            if let excluded = excludedHandles, !excluded.isEmpty {
                xSearchConfig["excluded_x_handles"] = excluded
            }
            if let from = fromDate {
                xSearchConfig["from_date"] = from
            }
            if let to = toDate {
                xSearchConfig["to_date"] = to
            }
            if enableImageUnderstanding {
                xSearchConfig["enable_image_understanding"] = true
            }
            if enableVideoUnderstanding {
                xSearchConfig["enable_video_understanding"] = true
            }

            let body: [String: Any] = [
                "model": "grok-3",
                "messages": [
                    ["role": "user", "content": query]
                ],
                "search": xSearchConfig
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("xAI API error: \(errorText)")
                }
                throw XAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let chatResponse = try decoder.decode(XAIChatResponse.self, from: data)

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
            logger.error("Grok X Search failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "X search failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Image Generation

    private func executeImageGeneration(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let prompt = (inputs["prompt"] as? String) ?? ""
        let n = (inputs["n"] as? Int) ?? 1
        let responseFormat = (inputs["response_format"] as? String) ?? "url"

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Image prompt cannot be empty"
            )
        }

        logger.info("Executing Grok Image Generation: \(prompt)")

        do {
            let url = URL(string: "https://api.x.ai/v1/images/generations")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": "grok-2-image",
                "prompt": prompt,
                "n": n,
                "response_format": responseFormat
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("xAI API error: \(errorText)")
                }
                throw XAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let imageResponse = try decoder.decode(XAIImageResponse.self, from: data)

            var output = "Generated \(imageResponse.data.count) image(s).\n"
            for (index, image) in imageResponse.data.enumerated() {
                if let url = image.url {
                    output += "Image \(index + 1): \(url)\n"
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
            logger.error("Grok Image Generation failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Image generation failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Image Understanding

    private func executeImageUnderstanding(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let imageRef = (inputs["image_url"] as? String) ?? (inputs["file"] as? String) ?? ""
        let prompt = (inputs["prompt"] as? String) ?? ""
        let detail = (inputs["detail"] as? String) ?? "auto"
        let model = (inputs["model"] as? String) ?? "grok-4"

        guard !imageRef.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Image URL or file path is required")
        }

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Prompt is required")
        }

        logger.info("Executing Grok Image Understanding")

        do {
            let resolvedUrl: String
            if imageRef.hasPrefix("http://") || imageRef.hasPrefix("https://") || imageRef.hasPrefix("data:") {
                resolvedUrl = imageRef
            } else if FileManager.default.fileExists(atPath: imageRef) {
                let fileURL = URL(fileURLWithPath: imageRef)
                let data = try Data(contentsOf: fileURL)
                let ext = fileURL.pathExtension.lowercased()
                let mimeType: String
                switch ext {
                case "png":
                    mimeType = "image/png"
                case "jpg", "jpeg":
                    mimeType = "image/jpeg"
                default:
                    mimeType = "image/jpeg"
                }
                let base64 = data.base64EncodedString()
                resolvedUrl = "data:\(mimeType);base64,\(base64)"
            } else {
                return ToolResultV2.failure(toolId: toolId, error: "Image URL or file path is invalid")
            }

            let url = URL(string: "https://api.x.ai/v1/chat/completions")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": model,
                "messages": [
                    [
                        "role": "user",
                        "content": [
                            [
                                "type": "image_url",
                                "image_url": [
                                    "url": resolvedUrl,
                                    "detail": detail
                                ]
                            ],
                            [
                                "type": "text",
                                "text": prompt
                            ]
                        ]
                    ]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("xAI API error: \(errorText)")
                }
                throw XAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let chatResponse = try decoder.decode(XAIChatResponse.self, from: data)
            let text = chatResponse.choices.first?.message.content ?? ""

            return ToolResultV2.success(
                toolId: toolId,
                output: text,
                structured: [
                    "model": chatResponse.model,
                    "detail": detail
                ]
            )
        } catch {
            logger.error("Grok Image Understanding failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Image understanding failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Code Execution

    private func executeCodeExecution(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let code = (inputs["code"] as? String) ?? ""

        // Code execution is typically handled by the model itself via tool use
        // We send a request indicating code execution is enabled
        logger.info("Executing Grok Code Execution")

        do {
            let url = URL(string: "https://api.x.ai/v1/chat/completions")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            var body: [String: Any] = [
                "model": "grok-3",
                "tools": [
                    ["type": "code_execution"]
                ]
            ]

            if !code.isEmpty {
                body["messages"] = [
                    ["role": "user", "content": "Execute this Python code:\n```python\n\(code)\n```"]
                ]
            } else {
                body["messages"] = [
                    ["role": "user", "content": "Code execution is now enabled."]
                ]
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw XAIToolError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    logger.error("xAI API error: \(errorText)")
                }
                throw XAIToolError.apiError(statusCode: httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let chatResponse = try decoder.decode(XAIChatResponse.self, from: data)

            let text = chatResponse.choices.first?.message.content ?? "Code execution completed"

            return ToolResultV2.success(
                toolId: toolId,
                output: text,
                structured: [
                    "model": chatResponse.model
                ]
            )
        } catch {
            logger.error("Grok Code Execution failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Code execution failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private func getXAIApiKey() -> String? {
        guard let key = try? APIKeysStorage.shared.getAPIKey(for: .xai),
              !key.isEmpty else {
            return nil
        }
        return key
    }
}

// MARK: - Response Types

private struct XAIChatResponse: Decodable {
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

private struct XAIImageResponse: Decodable {
    let created: Int?
    let data: [ImageData]

    struct ImageData: Decodable {
        let url: String?
        let b64Json: String?
        let revisedPrompt: String?
    }
}

// MARK: - Errors

private enum XAIToolError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int)
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from xAI API"
        case .apiError(let statusCode):
            return "xAI API error (status \(statusCode))"
        case .missingApiKey:
            return "xAI API key is required"
        }
    }
}
