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
        // Web search
        case "openai_web_search", "web_search":
            return await executeWebSearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Image generation
        case "openai_image_gen", "openai_image_generation", "image_generation":
            return await executeImageGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Deep research
        case "openai_deep_research", "deep_research":
            return await executeDeepResearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Video generation
        case "openai_video_gen", "openai_video_generation", "video_generation":
            return await executeVideoGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Computer use
        case "openai_computer_use":
            return await executeComputerUse(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Embeddings
        case "openai_embeddings":
            return await executeEmbeddings(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Speech to text
        case "openai_speech_to_text":
            return await executeSpeechToText(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Text to speech
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

            let result = try await videoService.generateVideo(
                prompt: prompt,
                model: model,
                size: size,
                durationSeconds: seconds,
                apiKey: apiKey
            )

            return ToolResultV2.success(
                toolId: toolId,
                output: "Video generated successfully.\nURL: \(result.videoUrl ?? "pending")",
                structured: [
                    "videoUrl": result.videoUrl ?? "",
                    "status": result.status
                ]
            )
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
        let coordinate = inputs["coordinate"] as? [Int]
        let text = inputs["text"] as? String

        guard !action.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Action is required for computer use"
            )
        }

        logger.info("Executing OpenAI Computer Use: \(action)")

        do {
            let response = try await openaiToolService.computerUse(
                apiKey: apiKey,
                action: action,
                coordinate: coordinate,
                text: text
            )

            return ToolResultV2.success(
                toolId: toolId,
                output: response.output ?? "Action completed",
                structured: [
                    "action": action,
                    "success": response.success
                ]
            )
        } catch {
            logger.error("OpenAI Computer Use failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Computer use failed: \(error.localizedDescription)"
            )
        }
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
            let response = try await openaiToolService.embeddings(
                apiKey: apiKey,
                input: input,
                model: model
            )

            return ToolResultV2.success(
                toolId: toolId,
                output: "Generated embedding with \(response.embedding.count) dimensions",
                structured: [
                    "dimensions": response.embedding.count,
                    "model": response.model
                ]
            )
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
        let prompt = inputs["prompt"] as? String

        guard !file.isEmpty else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Audio file path is required"
            )
        }

        logger.info("Executing OpenAI Speech to Text: \(file)")

        do {
            let response = try await openaiToolService.speechToText(
                apiKey: apiKey,
                filePath: file,
                model: model,
                language: language,
                prompt: prompt
            )

            return ToolResultV2.success(
                toolId: toolId,
                output: response.text,
                structured: [
                    "duration": response.duration ?? 0,
                    "language": response.language ?? "unknown"
                ]
            )
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
            let response = try await openaiToolService.textToSpeech(
                apiKey: apiKey,
                input: input,
                voice: voice,
                model: model,
                speed: speed
            )

            return ToolResultV2.success(
                toolId: toolId,
                output: "Speech generated successfully.\nFile: \(response.filePath)",
                structured: [
                    "filePath": response.filePath,
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
        let settings = AppSettings.shared
        let key = settings.openaiApiKey
        return key.isEmpty ? nil : key
    }
}
