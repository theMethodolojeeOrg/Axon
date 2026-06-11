//
//  OnDeviceTextGenerator.swift
//  Axon
//
//  Shared on-device text generation for Apple Intelligence (FoundationModels)
//  and local MLX models. Used by the chat orchestrator and background workers
//  (e.g. subconscious memory logging) so on-device backends behave identically
//  everywhere.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum OnDeviceTextGenerator {

    // MARK: - Apple Intelligence (Foundation Models)

    static func appleFoundation(system: String?, messages: [Message]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await appleFoundationImpl(system: system, messages: messages)
        } else {
            throw APIError.networkError("Apple Intelligence requires iOS 26.0+ or macOS 26.0+")
        }
        #else
        throw APIError.networkError("Apple Intelligence is not available on this platform")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func appleFoundationImpl(system: String?, messages: [Message]) async throws -> String {
        // Check model availability
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            let reasonText: String
            switch reason {
            case .deviceNotEligible:
                reasonText = "This device doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                reasonText = "Apple Intelligence is not enabled. Enable it in Settings > Apple Intelligence & Siri"
            case .modelNotReady:
                reasonText = "Apple Intelligence model is still downloading or preparing"
            @unknown default:
                reasonText = "Apple Intelligence is unavailable"
            }
            throw APIError.networkError(reasonText)
        }

        // Build conversation history for multi-turn context
        // The FoundationModels API uses a simple prompt string, so we format the conversation
        var conversationLines: [String] = []

        for msg in messages where msg.role != .system {
            let role = msg.role == .user ? "User" : "Assistant"
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                conversationLines.append("\(role): \(content)")
            }
        }

        // Get the last user message as the main prompt
        let lastUserMessage = messages.last(where: { $0.role == .user })?.content ?? ""

        // Create session with system instructions
        let session: LanguageModelSession
        if let system = system, !system.isEmpty {
            session = LanguageModelSession(instructions: system)
        } else {
            session = LanguageModelSession()
        }

        // If we have conversation history, include it for context
        let prompt: String
        if conversationLines.count > 1 {
            // Multi-turn: include context but let the model respond to the last message
            let context = conversationLines.dropLast().joined(separator: "\n\n")
            prompt = """
            Previous conversation:
            \(context)

            Now respond to: \(lastUserMessage)
            """
        } else {
            // Single turn: just use the user message directly
            prompt = lastUserMessage
        }

        // Generate response
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    // MARK: - Local MLX Models

    /// Call a local MLX model (downloads from HuggingFace on first use)
    /// - Parameter modelId: HuggingFace model ID (e.g., "mlx-community/SmolLM2-1.7B-Instruct-4bit")
    static func localMLX(
        modelId: String,
        system: String?,
        messages: [Message],
        modelParams: ModelGenerationSettings?
    ) async throws -> String {
        #if targetEnvironment(simulator)
        throw APIError.networkError("MLX models require a physical device (Metal GPU)")
        #else
        do {
            // Load the specific model (will download if not cached)
            try await MLXModelService.shared.loadModel(modelId: modelId)

            // Use resolved runtime model parameters for this request.
            let genSettings = modelParams ?? ModelGenerationSettings()

            // Apply user settings with sensible defaults for Qwen3
            let temperature = genSettings.temperatureEnabled ? genSettings.temperature : 0.7
            let topP = genSettings.topPEnabled ? genSettings.topP : 0.8
            let repetitionPenalty = genSettings.repetitionPenaltyEnabled ? genSettings.repetitionPenalty : 1.0
            let repetitionContextSize = genSettings.repetitionPenaltyEnabled ? genSettings.repetitionContextSize : 64
            let maxTokens = genSettings.maxResponseTokensEnabled ? genSettings.maxResponseTokens : 2048

            let response = try await MLXModelService.shared.generate(
                systemPrompt: system,
                messages: messages,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                repetitionContextSize: repetitionContextSize
            )
            return response
        } catch let error as MLXModelError {
            throw APIError.networkError(error.localizedDescription)
        } catch {
            throw APIError.networkError("MLX inference failed: \(error.localizedDescription)")
        }
        #endif
    }
}
