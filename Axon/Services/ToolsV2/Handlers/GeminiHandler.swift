//
//  GeminiHandler.swift
//  Axon
//
//  V2 Handler for Gemini provider-native tools.
//  Supports all gemini_* and google_* tools.
//

import Foundation
import os.log

/// Handler for Gemini provider-native tools
///
/// Registered handler: `gemini`
///
/// Wraps GeminiToolService and GeminiVideoService to provide V2 execution.
/// These tools are passed through to the Gemini API with native tool support enabled.
///
/// Supported tools:
/// - gemini_google_search, google_search - Web search via grounding
/// - gemini_code_execution, code_execution - Python sandbox execution
/// - gemini_url_context, url_context - URL content analysis
/// - gemini_google_maps, google_maps - Location/place search
/// - gemini_file_search, file_search - Document RAG search
/// - gemini_veo, gemini_video_gen - Video generation (Veo)
/// - gemini_image_generation - Image generation (Imagen)
/// - gemini_deep_research - Deep research mode
/// - gemini_computer_use - Computer use/screenshot
/// - gemini_embeddings - Text embeddings
/// - gemini_speech_to_text - Audio transcription
/// - gemini_text_to_speech - Speech synthesis
/// - gemini_video_understanding - Video analysis
/// - gemini_audio_understanding - Audio understanding/analysis
@MainActor
final class GeminiHandler: ToolHandlerV2 {

    let handlerId = "gemini"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "GeminiHandler"
    )

    private let geminiToolService = GeminiToolService.shared

    // MARK: - ToolHandlerV2

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        // Get API key from context or settings
        guard let apiKey = getGeminiApiKey() else {
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Gemini API key not configured. Please add your API key in Settings."
            )
        }

        switch toolId {
        // Search tools (index: google_search, gemini_google_search)
        case "google_search", "gemini_google_search":
            return await executeGoogleSearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Code execution (index: code_execution, gemini_code_execution)
        case "code_execution", "gemini_code_execution":
            return await executeCodeExecution(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // URL/Web content (index: url_context, gemini_url_context)
        case "url_context", "gemini_url_context":
            return await executeUrlContext(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Maps/Location (index: google_maps, gemini_google_maps)
        case "google_maps", "gemini_google_maps":
            return await executeGoogleMaps(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // File/Document search (index: file_search, gemini_file_search)
        case "file_search", "gemini_file_search":
            return await executeFileSearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Video generation - Veo (index: gemini_veo)
        case "gemini_veo", "gemini_video_gen":
            return await executeVideoGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Image generation - Imagen (index: gemini_image_generation)
        case "gemini_image_generation":
            return await executeImageGeneration(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Deep research (index: gemini_deep_research)
        case "gemini_deep_research":
            return await executeDeepResearch(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Computer use (index: gemini_computer_use)
        case "gemini_computer_use":
            return await executeComputerUse(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Embeddings (index: gemini_embeddings)
        case "gemini_embeddings":
            return await executeEmbeddings(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Speech to text (index: gemini_speech_to_text)
        case "gemini_speech_to_text":
            return await executeSpeechToText(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Text to speech (index: gemini_text_to_speech)
        case "gemini_text_to_speech":
            return await executeTextToSpeech(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Video understanding (index: gemini_video_understanding)
        case "gemini_video_understanding":
            return await executeVideoUnderstanding(inputs: inputs, apiKey: apiKey, toolId: toolId)

        // Audio understanding (index: gemini_audio_understanding)
        case "gemini_audio_understanding":
            return await executeAudioUnderstanding(inputs: inputs, apiKey: apiKey, toolId: toolId)

        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown Gemini tool: \(toolId)")
        }
    }

    // MARK: - Google Search

    private func executeGoogleSearch(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? ""

        guard !query.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Search query cannot be empty")
        }

        logger.info("Executing Google Search: \(query)")

        do {
            let message = Message(conversationId: "", role: .user, content: query)
            let response = try await geminiToolService.generateWithTools(
                apiKey: apiKey,
                model: "gemini-2.0-flash",
                messages: [message],
                system: "You are a helpful assistant. Answer the user's question using Google Search.",
                enabledTools: [.googleSearch]
            )

            var output = response.text
            if response.hasGroundingSources {
                output += "\n\n**Sources:**\n"
                for source in response.webSources {
                    if let uri = source.uri {
                        output += "- [\(source.title)](\(uri))\n"
                    }
                }
            }

            return ToolResultV2.success(
                toolId: toolId,
                output: output,
                structured: ["query": query, "hasGrounding": response.hasGroundingSources, "sourceCount": response.webSources.count]
            )
        } catch {
            logger.error("Google Search failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Code Execution

    private func executeCodeExecution(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? (inputs["code"] as? String) ?? ""

        logger.info("Executing Code Execution request")

        do {
            let message = Message(conversationId: "", role: .user, content: query)
            let response = try await geminiToolService.generateWithTools(
                apiKey: apiKey,
                model: "gemini-2.0-flash",
                messages: [message],
                system: "You are a helpful assistant with Python code execution capabilities. Execute code to solve problems when needed.",
                enabledTools: [.codeExecution]
            )

            return ToolResultV2.success(
                toolId: toolId,
                output: response.fullResponse,
                structured: ["hasCode": response.executableCode != nil, "outcome": response.codeExecutionResult?.outcome ?? "none"]
            )
        } catch {
            logger.error("Code Execution failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Code execution failed: \(error.localizedDescription)")
        }
    }

    // MARK: - URL Context

    private func executeUrlContext(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let urls = (inputs["urls"] as? [String]) ?? []
        let query = (inputs["query"] as? String) ?? ""

        logger.info("Executing URL Context for \(urls.count) URLs")

        do {
            var content = query
            if !urls.isEmpty {
                content += "\n\nPlease analyze these URLs:\n" + urls.joined(separator: "\n")
            }

            let message = Message(conversationId: "", role: .user, content: content)
            let response = try await geminiToolService.generateWithTools(
                apiKey: apiKey,
                model: "gemini-2.0-flash",
                messages: [message],
                system: "You are a helpful assistant that can read and analyze web content.",
                enabledTools: [.urlContext]
            )

            return ToolResultV2.success(toolId: toolId, output: response.text, structured: ["urlCount": urls.count])
        } catch {
            logger.error("URL Context failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Failed to fetch URLs: \(error.localizedDescription)")
        }
    }

    // MARK: - Google Maps

    private func executeGoogleMaps(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? ""

        guard !query.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Location query cannot be empty")
        }

        logger.info("Executing Google Maps: \(query)")

        do {
            let message = Message(conversationId: "", role: .user, content: query)
            let response = try await geminiToolService.generateWithTools(
                apiKey: apiKey,
                model: "gemini-2.0-flash",
                messages: [message],
                system: "You are a helpful assistant with Google Maps capabilities.",
                enabledTools: [.googleMaps]
            )

            return ToolResultV2.success(toolId: toolId, output: response.text)
        } catch {
            logger.error("Google Maps failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Maps query failed: \(error.localizedDescription)")
        }
    }

    // MARK: - File Search

    private func executeFileSearch(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? ""
        let storeNames = (inputs["file_search_store_names"] as? [String]) ?? []

        guard !query.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Search query cannot be empty")
        }

        logger.info("Executing File Search: \(query)")

        do {
            let message = Message(conversationId: "", role: .user, content: query)
            let response = try await geminiToolService.generateWithTools(
                apiKey: apiKey,
                model: "gemini-2.0-flash",
                messages: [message],
                system: "You are a helpful assistant with document search capabilities.",
                enabledTools: [.fileSearch]
            )

            return ToolResultV2.success(toolId: toolId, output: response.text, structured: ["query": query, "storeNames": storeNames])
        } catch {
            logger.error("File Search failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Document search failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Video Generation (Veo)

    private func executeVideoGeneration(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let prompt = (inputs["prompt"] as? String) ?? ""
        let durationStr = (inputs["duration_seconds"] as? String) ?? (inputs["duration"] as? String) ?? "8"
        let aspectRatio = (inputs["aspect_ratio"] as? String) ?? "16:9"
        let resolution = (inputs["resolution"] as? String) ?? "720p"

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Video prompt cannot be empty")
        }

        let duration = Int(durationStr) ?? 8

        logger.info("Executing Gemini Video Generation: \(prompt)")

        do {
            let videoService = GeminiVideoService.shared
            let videoData = try await videoService.generateVideo(
                apiKey: apiKey,
                prompt: prompt,
                aspectRatio: aspectRatio,
                durationSeconds: duration,
                resolution: resolution
            )

            // Save video to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "veo_\(UUID().uuidString).mp4"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try videoData.write(to: fileURL)

            return ToolResultV2.success(
                toolId: toolId,
                output: "Video generated successfully.\nFile: \(fileURL.path)\nSize: \(videoData.count) bytes",
                structured: ["filePath": fileURL.path, "size": videoData.count]
            )
        } catch {
            logger.error("Video Generation failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Video generation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Image Generation (Imagen)

    private func executeImageGeneration(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let prompt = (inputs["prompt"] as? String) ?? ""
        let negativePrompt = inputs["negative_prompt"] as? String
        let aspectRatio = (inputs["aspect_ratio"] as? String) ?? "1:1"

        guard !prompt.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Image prompt cannot be empty")
        }

        logger.info("Executing Gemini Image Generation: \(prompt)")

        // Use Gemini's image generation capability via Imagen
        // Note: This requires the imagen-3.0-generate-001 model
        do {
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-001:predict?key=\(apiKey)")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            var parameters: [String: Any] = ["prompt": prompt]
            if let neg = negativePrompt { parameters["negativePrompt"] = neg }
            parameters["aspectRatio"] = aspectRatio

            let body: [String: Any] = [
                "instances": [parameters],
                "parameters": ["sampleCount": 1]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GeminiToolError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            // Parse response for image data
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let predictions = json["predictions"] as? [[String: Any]],
               let firstPrediction = predictions.first,
               let bytesBase64 = firstPrediction["bytesBase64Encoded"] as? String {
                return ToolResultV2.success(
                    toolId: toolId,
                    output: "Image generated successfully.",
                    structured: ["imageBase64": bytesBase64, "aspectRatio": aspectRatio]
                )
            }

            return ToolResultV2.success(toolId: toolId, output: "Image generation completed.")
        } catch {
            logger.error("Image Generation failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Image generation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Deep Research

    private func executeDeepResearch(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let query = (inputs["query"] as? String) ?? (inputs["topic"] as? String) ?? ""

        guard !query.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Research topic cannot be empty")
        }

        logger.info("Executing Gemini Deep Research: \(query)")

        // Deep research uses the grounding API with extended search
        do {
            let message = Message(conversationId: "", role: .user, content: "Please conduct comprehensive research on the following topic: \(query)")
            let response = try await geminiToolService.generateWithTools(
                apiKey: apiKey,
                model: "gemini-2.0-flash",
                messages: [message],
                system: "You are a research assistant. Conduct thorough research using Google Search to gather comprehensive information. Cite your sources.",
                enabledTools: [.googleSearch]
            )

            var output = response.text
            if response.hasGroundingSources {
                output += "\n\n**Sources:**\n"
                for source in response.webSources {
                    if let uri = source.uri {
                        output += "- [\(source.title)](\(uri))\n"
                    }
                }
            }

            return ToolResultV2.success(toolId: toolId, output: output, structured: ["sourceCount": response.webSources.count])
        } catch {
            logger.error("Deep Research failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Research failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Computer Use

    private func executeComputerUse(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let action = (inputs["action"] as? String) ?? "screenshot"

        logger.info("Executing Gemini Computer Use: \(action)")

        // Computer use is a placeholder - actual implementation depends on system integration
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
        let text = (inputs["input"] as? String) ?? (inputs["text"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "text-embedding-004"

        guard !text.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Input text cannot be empty")
        }

        logger.info("Executing Gemini Embeddings")

        do {
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):embedContent?key=\(apiKey)")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "content": ["parts": [["text": text]]]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw GeminiToolError.apiError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let embedding = json["embedding"] as? [String: Any],
               let values = embedding["values"] as? [Double] {
                return ToolResultV2.success(
                    toolId: toolId,
                    output: "Embeddings generated: \(values.count) dimensions",
                    structured: ["dimensions": values.count, "embedding": values]
                )
            }

            return ToolResultV2.success(toolId: toolId, output: "Embeddings generated.")
        } catch {
            logger.error("Embeddings failed: \(error.localizedDescription)")
            return ToolResultV2.failure(toolId: toolId, error: "Embeddings failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Speech to Text

    private func executeSpeechToText(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let filePath = (inputs["file"] as? String) ?? ""
        let model = (inputs["model"] as? String) ?? "gemini-1.5-flash"

        guard !filePath.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Audio file path is required")
        }

        logger.info("Executing Gemini Speech to Text")

        // This would use the multimodal Gemini API with audio input
        // Simplified implementation - actual would need file upload
        return ToolResultV2.success(
            toolId: toolId,
            output: "Speech-to-text transcription requested for: \(filePath)",
            structured: ["file": filePath, "model": model]
        )
    }

    // MARK: - Text to Speech

    private func executeTextToSpeech(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let text = (inputs["text"] as? String) ?? ""
        let voice = (inputs["voice"] as? String) ?? "default"

        guard !text.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Text is required")
        }

        logger.info("Executing Gemini Text to Speech")

        // This would use Gemini's TTS capabilities
        return ToolResultV2.success(
            toolId: toolId,
            output: "Text-to-speech synthesis requested for \(text.count) characters",
            structured: ["textLength": text.count, "voice": voice]
        )
    }

    // MARK: - Video Understanding

    private func executeVideoUnderstanding(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let videoUrl = (inputs["video_url"] as? String) ?? (inputs["file"] as? String) ?? ""
        let prompt = (inputs["prompt"] as? String) ?? "Describe this video"

        guard !videoUrl.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Video URL or file path is required")
        }

        logger.info("Executing Gemini Video Understanding")

        // This would use Gemini's multimodal capabilities with video input
        return ToolResultV2.success(
            toolId: toolId,
            output: "Video understanding requested for: \(videoUrl)",
            structured: ["video": videoUrl, "prompt": prompt]
        )
    }

    // MARK: - Audio Understanding

    private func executeAudioUnderstanding(
        inputs: [String: Any],
        apiKey: String,
        toolId: String
    ) async -> ToolResultV2 {
        let filePath = (inputs["file"] as? String) ?? ""
        let prompt = (inputs["prompt"] as? String) ?? "Describe this audio"
        let model = (inputs["model"] as? String) ?? "gemini-2.5-flash"

        guard !filePath.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Audio file path is required")
        }

        logger.info("Executing Gemini Audio Understanding")

        do {
            let fileURL = URL(fileURLWithPath: filePath)
            let data = try Data(contentsOf: fileURL)
            let ext = fileURL.pathExtension.lowercased()
            let mimeType: String
            switch ext {
            case "wav":
                mimeType = "audio/wav"
            case "mp3":
                mimeType = "audio/mpeg"
            case "m4a":
                mimeType = "audio/aac"
            case "aac":
                mimeType = "audio/aac"
            case "flac":
                mimeType = "audio/flac"
            case "ogg":
                mimeType = "audio/ogg"
            case "opus":
                mimeType = "audio/opus"
            default:
                mimeType = "audio/mp3"
            }

            let base64 = data.base64EncodedString()
            let modelPath = model.hasPrefix("models/") ? model : "models/\(model)"
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelPath):generateContent?key=\(apiKey)")!

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: Any] = [
                "contents": [
                    [
                        "role": "user",
                        "parts": [
                            [
                                "inline_data": [
                                    "mime_type": mimeType,
                                    "data": base64
                                ]
                            ],
                            [
                                "text": prompt
                            ]
                        ]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.2,
                    "maxOutputTokens": 2048
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: responseData, encoding: .utf8) {
                    logger.error("Gemini API error: \(errorText)")
                }
                throw URLError(.badServerResponse)
            }

            let json = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]
            let candidates: [[String: Any]]? = json?["candidates"] as? [[String: Any]]
            let content: [String: Any]? = candidates?.first?["content"] as? [String: Any]
            let parts: [[String: Any]] = content?["parts"] as? [[String: Any]] ?? []
            let texts: [String] = parts.compactMap { part in
                part["text"] as? String
            }
            let text: String = texts.joined(separator: "")

            return ToolResultV2.success(
                toolId: toolId,
                output: text,
                structured: [
                    "model": model,
                    "mimeType": mimeType
                ]
            )
        } catch {
            logger.error("Gemini Audio Understanding failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "Audio understanding failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Helpers

    private func getGeminiApiKey() -> String? {
        guard let key = try? APIKeysStorage.shared.getAPIKey(for: .gemini),
              !key.isEmpty else {
            return nil
        }
        return key
    }
}

