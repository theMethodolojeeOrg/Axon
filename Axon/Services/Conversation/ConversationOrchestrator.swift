//
//  ConversationOrchestrator.swift
//  Axon
//
//  Protocol for abstracting conversation orchestration (Cloud vs On-Device)
//

import Foundation

protocol ConversationOrchestrator {
    func sendMessage(
        conversationId: String,
        content: String,
        attachments: [MessageAttachment],
        enabledTools: [String],
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> (assistantMessage: Message, memories: [Memory]?)

    func regenerateAssistantMessage(
        conversationId: String,
        messageId: String,
        messages: [Message],
        config: OrchestrationConfig
    ) async throws -> Message
}

struct OrchestrationConfig {
    let provider: String
    let model: String
    let providerName: String
    let contextWindowLimit: Int  // Model's context window size
    // API Keys
    let anthropicKey: String?
    let openaiKey: String?
    let geminiKey: String?
    let grokKey: String?
    let perplexityKey: String?
    let deepseekKey: String?
    let zaiKey: String?
    let minimaxKey: String?
    let mistralKey: String?
    // Custom Provider
    let customBaseUrl: String?
    let customApiKey: String?
    // Model Generation Parameters
    let modelParams: ModelGenerationSettings?
}

// MARK: - Shared Types

struct OrchestrateRequest: Encodable {
    let conversationId: String
    let content: AnyCodable
    let provider: String
    let options: OrchestrateOptions
    // API keys at top level to match backend expectations
    let anthropic: String?
    let openai: String?
    let gemini: String?
    let grok: String?
    let openaiCompatible: OpenAICompatible?
}

struct OpenAICompatible: Encodable {
    let apiKey: String
    let baseUrl: String
}

struct OrchestrateOptions: Encodable {
    let createArtifacts: Bool
    let saveMemories: Bool
    let executeTools: Bool
    let model: String?
    let geminiTools: Bool?
    let enabledTools: [String]?  // List of specific tool IDs to enable
}

struct OrchestrateResponse: Decodable {
    let userMessage: Message
    let assistantMessage: Message
    let artifacts: [AnyCodable]?
    let memories: [Memory]?
    let tools: [AnyCodable]?
    let conversationUpdated: Bool?
    let metadata: AnyCodable?
}

struct RegenerateRequest: Encodable {
    let provider: String
    let options: Options
    let anthropic: String?
    let openai: String?
    let gemini: String?
    let grok: String?

    struct Options: Encodable {
        let model: String?
        let temperature: Double?
        let maxTokens: Int?
        let includeMemories: Bool
        let replaceLastMessage: Bool
        let projectId: String?
    }
}

struct RegenerateResponse: Decodable {
    let userMessage: Message?
    let assistantMessage: Message
    let conversationUpdated: Bool?
    let metadata: AnyCodable?
    let replacedMessageId: String?
}
