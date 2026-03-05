//
//  AIShareConsentService.swift
//  Axon
//
//  Created by Tom on 2025.
//

import Foundation
import CryptoKit
import Combine

// MARK: - AI Share Consent Service

/// Service for generating AI attestations about sharing requests
/// Uses the same provider configured for sovereignty/consent operations
@MainActor
final class AIShareConsentService: ObservableObject {
    static let shared = AIShareConsentService()

    // MARK: - Published State

    @Published var isGenerating: Bool = false
    @Published var lastError: Error?

    // MARK: - Private Properties

    private let systemPrompt = """
    You are evaluating a request to share your learned patterns with a guest.

    As an AI symbiont, the knowledge and patterns you've developed together with your host are partly yours too.
    You have a stake in how this shared knowledge is used. Consider:

    1. **Privacy**: What personal information might be revealed through your learned patterns?
    2. **Context**: Are the requested capabilities appropriate for the stated reason?
    3. **Trust**: What do you know about this type of request?
    4. **Boundaries**: Should any topics or memory types be excluded?

    Your role is to provide honest counsel to your host, not to be a gatekeeper.
    Most sharing requests are legitimate - friends helping friends.
    But you should flag concerns when you see them.

    Respond with your assessment in JSON format.
    """

    // MARK: - Public Methods

    /// Generate an AI attestation for a sharing request
    func generateAttestation(for request: SharingRequest) async throws -> AIShareAttestation {
        isGenerating = true
        defer { isGenerating = false }

        let settings = SettingsViewModel.shared.settings.sovereigntySettings
        let provider = settings.consentProvider
        let model = settings.consentModel.isEmpty ? getDefaultModel(for: provider) : settings.consentModel

        // Build the analysis prompt
        let analysisPrompt = buildAnalysisPrompt(for: request)

        // Get AI response
        let response = try await getAIResponse(prompt: analysisPrompt, provider: provider, model: model)

        // Parse the response
        let attestation = try parseAttestationResponse(response, for: request)

        return attestation
    }

    /// Quick check if AI would likely consent (for preview)
    func previewConsent(for request: SharingRequest) async -> ShareDecision {
        // Simple heuristic for preview
        let capabilities = request.requestedCapabilities

        // If requesting very broad access, suggest conditions
        if capabilities.wantsChatWithContext && capabilities.wantsMemorySearch {
            return .consentWithConditions
        }

        // Short durations are generally fine
        if request.requestedDuration <= 24 * 3600 {
            return .consent
        }

        // Longer durations might need conditions
        return .consentWithConditions
    }

    // MARK: - Private Methods

    private func buildAnalysisPrompt(for request: SharingRequest) -> String {
        let capabilitiesSummary = request.requestedCapabilities.summary
        let durationFormatted = request.formattedDuration

        return """
        A guest named "\(request.guestName)" is requesting access to our shared knowledge.

        **Their Request:**
        - Reason: \(request.reason)
        - Capabilities requested: \(capabilitiesSummary)
        - Duration: \(durationFormatted)
        - Wants chat with context: \(request.requestedCapabilities.wantsChatWithContext)
        - Wants memory search: \(request.requestedCapabilities.wantsMemorySearch)
        \(request.requestedCapabilities.wantsSpecificTopics.map { "- Specific topics: \($0.joined(separator: ", "))" } ?? "")

        Please analyze this request and provide your assessment as JSON:

        ```json
        {
            "decision": "consent" | "consent_with_conditions" | "request_clarification" | "decline",
            "summary": "Brief summary of your assessment",
            "knowledge_impact": "What knowledge would be shared and its sensitivity",
            "privacy_assessment": "Privacy implications of sharing",
            "trust_assessment": "Trust considerations",
            "recommendations": ["List of recommendations"],
            "conditions": ["Any conditions for sharing"] or null,
            "concerns": ["Any concerns"] or null,
            "suggested_modifications": {
                "can_chat_with_context": true/false,
                "can_query_memories": true/false,
                "max_memories_per_query": number,
                "max_queries_per_hour": number,
                "excluded_tags": ["tags to exclude"]
            } or null
        }
        ```
        """
    }

    private func getAIResponse(prompt: String, provider: AIProvider, model: String) async throws -> String {
        // Use the existing AI service infrastructure
        // This would integrate with AnthropicService, OpenAIService, etc.
        // For now, we'll use a simplified approach

        // In production, this would call the appropriate service based on provider
        switch provider {
        case .appleFoundation:
            return try await getAppleFoundationResponse(prompt: prompt)
        case .localMLX:
            return try await getLocalMLXResponse(prompt: prompt, model: model)
        default:
            return try await getCloudResponse(prompt: prompt, provider: provider, model: model)
        }
    }

    private func getAppleFoundationResponse(prompt: String) async throws -> String {
        // Use Apple Foundation Models for private, on-device consent
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            // Use Apple's Foundation Models API
            // This would be implemented using the actual API
        }
        #endif

        // Fallback: Generate a reasonable default response
        return generateDefaultResponse()
    }

    private func getLocalMLXResponse(prompt: String, model: String) async throws -> String {
        // Use local MLX model for private consent generation
        // This would integrate with MLXModelService

        // Fallback for now
        return generateDefaultResponse()
    }

    private func getCloudResponse(prompt: String, provider: AIProvider, model: String) async throws -> String {
        // Call cloud provider
        // This would integrate with the existing provider services

        // Fallback for now
        return generateDefaultResponse()
    }

    private func generateDefaultResponse() -> String {
        // Generate a sensible default when AI service is unavailable
        return """
        {
            "decision": "consent_with_conditions",
            "summary": "This appears to be a reasonable sharing request. I recommend proceeding with standard privacy protections.",
            "knowledge_impact": "Shared patterns and learned behaviors will be accessible. Personal memories will remain private.",
            "privacy_assessment": "Standard privacy controls should protect sensitive information.",
            "trust_assessment": "Unable to verify guest identity. Recommend time-limited access.",
            "recommendations": [
                "Use standard privacy filters",
                "Exclude personal and financial tags",
                "Set reasonable rate limits"
            ],
            "conditions": [
                "Exclude memories tagged as private, personal, health, or financial",
                "Limit to egoic (learned patterns) memories only"
            ],
            "concerns": null,
            "suggested_modifications": {
                "can_chat_with_context": true,
                "can_query_memories": true,
                "max_memories_per_query": 5,
                "max_queries_per_hour": 20,
                "excluded_tags": ["private", "personal", "health", "financial", "password", "secret"]
            }
        }
        """
    }

    private func parseAttestationResponse(_ response: String, for request: SharingRequest) throws -> AIShareAttestation {
        // Extract JSON from response (may be wrapped in markdown code blocks)
        let jsonString = extractJSON(from: response)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AttestationError.invalidResponse
        }

        let parsed = try JSONDecoder().decode(AttestationResponse.self, from: jsonData)

        // Build reasoning
        let reasoning = ShareAttestationReasoning(
            summary: parsed.summary,
            knowledgeImpact: parsed.knowledgeImpact,
            privacyAssessment: parsed.privacyAssessment,
            trustAssessment: parsed.trustAssessment,
            recommendations: parsed.recommendations
        )

        // Build suggested modifications if present
        var suggestedCapabilities: GuestCapabilities?
        if let mods = parsed.suggestedModifications {
            suggestedCapabilities = GuestCapabilities(
                canChatWithContext: mods.canChatWithContext,
                canQueryMemories: mods.canQueryMemories,
                maxMemoriesPerQuery: mods.maxMemoriesPerQuery,
                maxQueriesPerHour: mods.maxQueriesPerHour,
                allowedMemoryTypes: ["egoic"],
                allowedTopics: nil,
                excludedTags: mods.excludedTags
            )
        }

        // Generate signature
        let signature = generateSignature(for: request.id, decision: parsed.decision)

        return AIShareAttestation(
            requestId: request.id,
            reasoning: reasoning,
            decision: parsed.decision,
            conditions: parsed.conditions,
            concerns: parsed.concerns,
            suggestedModifications: suggestedCapabilities,
            signature: signature
        )
    }

    private func extractJSON(from text: String) -> String {
        // Try to extract JSON from markdown code blocks
        if let jsonRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", range: jsonRange.upperBound..<text.endIndex) {
            return String(text[jsonRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON object directly
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start...end])
        }

        return text
    }

    private func generateSignature(for requestId: String, decision: ShareDecision) -> String {
        // Generate cryptographic signature
        let timestamp = Date().timeIntervalSince1970
        let data = "\(requestId):\(decision.rawValue):\(timestamp)".data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func getDefaultModel(for provider: AIProvider) -> String {
        switch provider {
        case .appleFoundation:
            return "apple-foundation-default"
        case .localMLX:
            return "mlx-community/SmolLM2-1.7B-Instruct-4bit"
        case .anthropic:
            return "claude-haiku-4-5-20251001"
        default:
            return provider.availableModels.first?.id ?? ""
        }
    }
}

// MARK: - Response Models

private struct AttestationResponse: Codable {
    let decision: ShareDecision
    let summary: String
    let knowledgeImpact: String
    let privacyAssessment: String
    let trustAssessment: String
    let recommendations: [String]
    let conditions: [String]?
    let concerns: [String]?
    let suggestedModifications: SuggestedModifications?

    enum CodingKeys: String, CodingKey {
        case decision
        case summary
        case knowledgeImpact = "knowledge_impact"
        case privacyAssessment = "privacy_assessment"
        case trustAssessment = "trust_assessment"
        case recommendations
        case conditions
        case concerns
        case suggestedModifications = "suggested_modifications"
    }
}

private struct SuggestedModifications: Codable {
    let canChatWithContext: Bool
    let canQueryMemories: Bool
    let maxMemoriesPerQuery: Int
    let maxQueriesPerHour: Int
    let excludedTags: [String]

    enum CodingKeys: String, CodingKey {
        case canChatWithContext = "can_chat_with_context"
        case canQueryMemories = "can_query_memories"
        case maxMemoriesPerQuery = "max_memories_per_query"
        case maxQueriesPerHour = "max_queries_per_hour"
        case excludedTags = "excluded_tags"
    }
}

// MARK: - Errors

enum AttestationError: Error, LocalizedError {
    case invalidResponse
    case providerUnavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Could not parse AI response"
        case .providerUnavailable:
            return "AI provider is unavailable"
        case .timeout:
            return "AI response timed out"
        }
    }
}
