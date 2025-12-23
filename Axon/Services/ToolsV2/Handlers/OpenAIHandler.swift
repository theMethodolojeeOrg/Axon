//
//  OpenAIHandler.swift
//  Axon
//
//  V2 Handler for OpenAI provider-native tools.
//  Supports all openai_* tools.
//

import Foundation
import os.log

/// Handler for OpenAI provider-native tools
///
/// Registered handler: `openai`
///
/// Wraps OpenAIToolService and OpenAIVideoService to provide V2 execution.
///
/// Supported tools:
/// - openai_web_search - Web search via search-preview models
/// - openai_image_gen, openai_image_generation - Image generation (GPT Image/DALL-E)
/// - openai_deep_research - Deep research with reasoning models
/// - openai_video_gen, openai_video_generation - Video generation (Sora)
/// - openai_computer_use - Computer use capabilities
/// - openai_embeddings - Text embeddings
/// - openai_speech_to_text - Audio transcription (Whisper)
/// - openai_text_to_speech - Speech synthesis (TTS)
@MainActor
final class OpenAIHandler: ToolHandlerV2 {

    let handlerId = "openai"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "OpenAIHandler"
    )

    private let openaiToolService = OpenAIToolService.shared

    // MARK: - ToolHandlerV2

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        // Get API key from context or settings
        guard let apiKey = getOpenAIApiKey() else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "OpenAI API key not configured. Please add your API key in Settings."
            )
        }

        switch toolId {
        // Web search (index: openai_web_search)
        case "openai_web_search":
            return await executeWebSearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Image generation (index: openai_image_gen, openai_image_generation)
        case "openai_image_gen", "openai_image_generation":
            return await executeImageGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Deep research (index: openai_deep_research)
        case "openai_deep_research":
            return await executeDeepResearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Video generation (index: openai_video_gen, openai_video_generation)
        case "openai_video_gen", "openai_video_generation":
            return await executeVideoGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Computer use (index: openai_computer_use)
        case "openai_computer_use":
            return await executeComputerUse(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Embeddings (index: openai_embeddings)
        case "openai_embeddings":
            return await executeEmbeddings(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Speech to text (index: openai_speech_to_text)
        case "openai_speech_to_text":
            return await executeSpeechToText(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Text to speech (index: openai_text_to_speech)
        case "openai_text_to_speech":
            return await executeTextToSpeech(inputs: inputs, apiKey: apiKey, toolId: toolId)

        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown OpenAI tool: \(toolId)")
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

        logger.info("Executing OpenAI Web Search: \(query)")

        do {
            // Get user location context if available
            let locationContext = UserLocationContext(
                country: nil,
                city: nil,
                region: nil,
                timezone: TimeZone.current.identifier
            )

            let response = try await openaiToolService.webSearch(
                apiKey: apiKey,
                query: query,
                model: "gpt-4o-search-preview",
                userLocation: locationContext
            )

            var output = response.text
            output += response.formattedCitations

            return ToolResultV2.success(
                toolId: toolId,
                output: output,
                structured: [
                    "query": query,
                    "hasCitations": response.hasCitations,
                    "citationCount": response.citations.count,
                    "model": response.model
                ]
            )
        } catch {
            logger.error("OpenAI Web Search failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Search failed: \(error.localizedDescription)"
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
        let sizeStr = (inputs["size"] as? String) ?? "1024x1024"
        let qualityStr = (inputs["quality"] as? String) ?? "standard"

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Image prompt cannot be empty"
            )
        }

        let size = ImageSize(rawValue: sizeStr) ?? .square1024
        let quality = ImageQuality(rawValue: qualityStr) ?? .auto

        logger.info("Executing OpenAI Image Generation: \(prompt)")

        do {
            let response = try await openaiToolService.generateImage(
                apiKey: apiKey,
                prompt: prompt,
                model: "gpt-image-1",
                size: size,
                quality: quality,
                n: n
            )

            var output = "Image generated successfully.\n"
            if let firstImage = response.firstImage {
                if let url = firstImage.url {
                    output += "URL: \(url)\n"
                }
                if let revised = firstImage.revisedPrompt {
                    output += "Revised prompt: \(revised)\n"
                }
            }

            return ToolResultV2.success(
                toolId: toolId,
                output: output,
                structured: [
                    "imageCount": response.data.count,
                    "imageUrl": response.firstImage?.url ?? ""
                ]
            )
        } catch {
            logger.error("OpenAI Image Generation failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Image generation failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Deep Research

    private func executeDeepResearch(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let topic = (inputs["topic"] as? String) ?? (inputs["query"] as? String) ?? ""
        let effortStr = (inputs["effort"] as? String) ?? "medium"

        guard !topic.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Research topic cannot be empty"
            )
        }

        let effort = ReasoningEffort(rawValue: effortStr) ?? .medium

        logger.info("Executing OpenAI Deep Research: \(topic) (effort: \(effort.rawValue))")

        do {
            let response = try await openaiToolService.deepResearch(
                apiKey: apiKey,
                query: topic,
                model: "o3-deep-research",
                reasoningEffort: effort
            )

            var output = response.text

            // Append citations if available
            if !response.citations.isEmpty {
                output += "\n\n**Sources:**\n"
                for citation in response.citations {
                    output += "- [\(citation.title ?? citation.url)](\(citation.url))\n"
                }
            }

            return ToolResultV2.success(
                toolId: toolId,
                output: output,
                structured: [
                    "status": response.status,
                    "citationCount": response.citations.count,
                    "inputTokens": response.usage?.inputTokens ?? 0,
                    "outputTokens": response.usage?.outputTokens ?? 0
                ]
            )
        } catch {
            logger.error("OpenAI Deep Research failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Research failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Video Generation

    private func executeVideoGeneration(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let prompt = (inputs["prompt"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "sora-2"
        let size = (inputs["size"] as? String) ?? "1280x720"
        let seconds = (inputs["seconds"] as? Int) ?? 8

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Video prompt cannot be empty"
            )
        }

        logger.info("Executing OpenAI Video Generation: \(prompt)")

        do {
            let videoService = OpenAIVideoService.shared

            // Start generation and get video ID
            let videoId = try await videoService.startGeneration(
                apiKey: apiKey,
                prompt: prompt,
                model: model,
                size: size,
                seconds: seconds
            )

            // Poll for completion (with timeout)
            var status: SoraJobStatus
            var attempts = 0
            let maxAttempts = 120 // ~10 minutes with 5s intervals

            repeat {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                status = try await videoService.pollJobStatus(apiKey: apiKey, videoId: videoId)
                attempts += 1
            } while !status.status.isTerminal && attempts < maxAttempts

            if status.status == .completed {
                return ToolResultV2.success(
                    toolId: toolId,
                    output: "Video generated successfully.\nVideo ID: \(videoId)",
                    structured: [
                        "videoId": videoId,
                        "status": status.status.rawValue
                    ]
                )
            } else if let error = status.error {
                return ToolResultV2.failure(toolId: toolId, error: "Video generation failed: \(error)")
            } else {
                return ToolResultV2.failure(toolId: toolId, error: "Video generation timed out or failed")
            }
        } catch {
            logger.error("OpenAI Video Generation failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Video generation failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Computer Use

    private func executeComputerUse(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let action = (inputs["action"] as? String) ?? ""

        guard !action.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Action is required for computer use"
            )
        }

        logger.info("Executing OpenAI Computer Use: \(action)")

        // Computer use requires system integration - placeholder implementation
        return ToolResultV2.success(
            toolId: toolId,
            output: "Computer use action '\(action)' noted. Implementation pending system integration.",
            structured: ["action": action]
        )
    }

    // MARK: - Embeddings

    private func executeEmbeddings(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let input = (inputs["input"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "text-embedding-3-small"

        guard !input.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Input text is required for embeddings"
            )
        }

        logger.info("Executing OpenAI Embeddings")

        do {
            let url = URL(string: "https://api.openai.com/v1/embeddings")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": model,
                "input": input
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw OpenAIToolError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]],
               let first = dataArray.first,
               let embedding = first["embedding"] as? [Double] {
                return ToolResultV2.success(
                    toolId: toolId,
                    output: "Generated embedding with \(embedding.count) dimensions",
                    structured: [
                        "dimensions": embedding.count,
                        "model": model
                    ]
                )
            }

            return ToolResultV2.success(toolId: toolId, output: "Embeddings generated.")
        } catch {
            logger.error("OpenAI Embeddings failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Embeddings failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Speech to Text

    private func executeSpeechToText(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let file = (inputs["file"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "whisper-1"
        let language = inputs["language"] as? String

        guard !file.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Audio file path is required"
            )
        }

        logger.info("Executing OpenAI Speech to Text: \(file)")

        do {
            let fileURL = URL(fileURLWithPath: file)
            let audioData = try Data(contentsOf: fileURL)
            let fileName = fileURL.lastPathComponent

            let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
            let boundary = UUID().uuidString

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()

            // Add file
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/mpeg\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)

            // Add model
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(model)\r\n".data(using: .utf8)!)

            // Add language if provided
            if let lang = language {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(lang)\r\n".data(using: .utf8)!)
            }

            body.append("--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw OpenAIToolError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return ToolResultV2.success(
                    toolId: toolId,
                    output: text,
                    structured: [
                        "model": model,
                        "language": language ?? "auto"
                    ]
                )
            }

            return ToolResultV2.failure(toolId: toolId, error: "Failed to parse transcription response")
        } catch {
            logger.error("OpenAI Speech to Text failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Transcription failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Text to Speech

    private func executeTextToSpeech(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let input = (inputs["input"] as? String) ?? ""
        let voice = (inputs["voice"] as? String) ?? "alloy"
        let model = (inputs["model"] as? String) ?? "tts-1"
        let speed = (inputs["speed"] as? Double) ?? 1.0

        guard !input.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Input text is required for text to speech"
            )
        }

        logger.info("Executing OpenAI Text to Speech")

        do {
            let url = URL(string: "https://api.openai.com/v1/audio/speech")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "model": model,
                "input": input,
                "voice": voice,
                "speed": speed
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw OpenAIToolError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            // Save audio to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "tts_\(UUID().uuidString).mp3"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try data.write(to: fileURL)

            return ToolResultV2.success(
                toolId: toolId,
                output: "Speech generated successfully.\nFile: \(fileURL.path)",
                structured: [
                    "filePath": fileURL.path,
                    "voice": voice,
                    "model": model
                ]
            )
        } catch {
            logger.error("OpenAI Text to Speech failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Text to speech failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private func getOpenAIApiKey() -> String? {
        guard let key = try? APIKeysStorage.shared.getAPIKey(for: .openai),
              !key.isEmpty else {
            return nil
        }
        return key
    }
}
