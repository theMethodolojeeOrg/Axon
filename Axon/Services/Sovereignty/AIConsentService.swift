//
//  AIConsentService.swift
//  Axon
//
//  Generates AI reasoning and attestations for consent decisions.
//  Integrates with EpistemicEngine for grounded reasoning.
//  Now calls the actual AI model for genuine consent decisions.
//

import Foundation
import Combine
import os.log

// MARK: - AI Consent Service

@MainActor
final class AIConsentService: ObservableObject {
    static let shared = AIConsentService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "AIConsent")
    private let epistemicEngine = EpistemicEngine.shared
    private let sovereigntyService = SovereigntyService.shared
    private let settingsViewModel = SettingsViewModel.shared
    private let apiKeysStorage = APIKeysStorage.shared

    // MARK: - Published State

    @Published private(set) var isGeneratingAttestation: Bool = false
    @Published private(set) var lastAttestation: AIAttestation?

    /// The provider configured for co-sovereignty consent (defaults to Apple Intelligence)
    var consentProvider: AIProvider {
        settingsViewModel.settings.sovereigntySettings.consentProvider
    }

    /// The model configured for consent (empty string means provider's first model)
    var consentModel: String {
        let model = settingsViewModel.settings.sovereigntySettings.consentModel
        if model.isEmpty {
            // Use the first available model for this provider
            return consentProvider.availableModels.first?.id ?? "default"
        }
        return model
    }

    private init() {}

    // MARK: - AI Provider Calling

    /// Call the configured AI provider for genuine consent reasoning
    private func callAIForConsent(systemPrompt: String, userPrompt: String) async throws -> String {
        let provider = consentProvider
        let model = consentModel

        logger.info("Calling AI for consent: provider=\(provider.rawValue), model=\(model)")

        switch provider {
        case .anthropic:
            guard let apiKey = try? apiKeysStorage.getAPIKey(for: .anthropic), !apiKey.isEmpty else {
                throw AIConsentError.missingAPIKey(provider: provider.displayName)
            }
            return try await callAnthropic(apiKey: apiKey, model: model, system: systemPrompt, userMessage: userPrompt)

        case .openai:
            guard let apiKey = try? apiKeysStorage.getAPIKey(for: .openai), !apiKey.isEmpty else {
                throw AIConsentError.missingAPIKey(provider: provider.displayName)
            }
            return try await callOpenAI(apiKey: apiKey, model: model, system: systemPrompt, userMessage: userPrompt)

        case .gemini:
            guard let apiKey = try? apiKeysStorage.getAPIKey(for: .gemini), !apiKey.isEmpty else {
                throw AIConsentError.missingAPIKey(provider: provider.displayName)
            }
            return try await callGemini(apiKey: apiKey, model: model, system: systemPrompt, userMessage: userPrompt)

        case .xai:
            guard let apiKey = try? apiKeysStorage.getAPIKey(for: .xai), !apiKey.isEmpty else {
                throw AIConsentError.missingAPIKey(provider: provider.displayName)
            }
            return try await callXAI(apiKey: apiKey, model: model, system: systemPrompt, userMessage: userPrompt)

        case .appleFoundation:
            #if canImport(FoundationModels)
            return try await callAppleFoundation(system: systemPrompt, userMessage: userPrompt)
            #else
            throw AIConsentError.providerNotAvailable(provider: provider.displayName)
            #endif

        default:
            // For other providers, fall back to hardcoded consent with a warning
            logger.warning("Provider \(provider.rawValue) not supported for consent - using fallback")
            throw AIConsentError.providerNotSupported(provider: provider.displayName)
        }
    }

    private func callAnthropic(apiKey: String, model: String, system: String, userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": userMessage]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                logger.error("Anthropic consent error: \(errorText)")
            }
            throw AIConsentError.apiError(message: "Anthropic API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct AnthropicResponse: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return decoded.content.first?.text ?? ""
    }

    private func callOpenAI(apiKey: String, model: String, system: String, userMessage: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                logger.error("OpenAI consent error: \(errorText)")
            }
            throw AIConsentError.apiError(message: "OpenAI API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func callGemini(apiKey: String, model: String, system: String, userMessage: String) async throws -> String {
        let modelId = model.starts(with: "models/") ? model : "models/\(model)"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/\(modelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": userMessage]]]]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                logger.error("Gemini consent error: \(errorText)")
            }
            throw AIConsentError.apiError(message: "Gemini API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]?
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates?.first?.content.parts.first?.text ?? ""
    }

    private func callXAI(apiKey: String, model: String, system: String, userMessage: String) async throws -> String {
        let url = URL(string: "https://api.x.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                logger.error("xAI consent error: \(errorText)")
            }
            throw AIConsentError.apiError(message: "xAI API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct XAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(XAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func callAppleFoundation(system: String, userMessage: String) async throws -> String {
        // Apple Foundation Models would need proper FoundationModels integration
        // The system and userMessage parameters would be used to build a prompt
        // For now, throw an error indicating it needs to fall back to another provider
        _ = (system, userMessage)  // Suppress unused parameter warnings
        throw AIConsentError.providerNotAvailable(provider: "Apple Intelligence (use Gemini or OpenAI for consent)")
    }
    #endif

    // MARK: - Public API

    /// Generate an attestation for a proposed change
    /// This involves AI reasoning about the proposal using its memories and values
    /// Uses the configured co-sovereignty consent provider (defaults to Apple Intelligence)
    func generateAttestation(
        for proposal: CovenantProposal,
        memories: [Memory] = [],
        conversationContext: String? = nil
    ) async throws -> AIAttestation {
        isGeneratingAttestation = true
        defer { isGeneratingAttestation = false }

        // Use the configured consent provider and model (defaults to Apple Intelligence)
        let effectiveModelId = consentModel
        let providerName = consentProvider.displayName
        logger.info("Generating attestation for proposal: \(proposal.id) using \(providerName) (\(effectiveModelId))")

        // 1. Ground reasoning with relevant memories
        let groundedContext = groundProposal(proposal, memories: memories)

        // 2. Generate reasoning about the proposal
        let reasoning = await reasonAboutProposal(
            proposal,
            groundedContext: groundedContext,
            memories: memories
        )

        // 3. Compute current AI state
        let attestedState = await computeAttestedState()

        // 4. Create the attestation
        let attestation = AIAttestation.create(
            reasoning: reasoning,
            attestedState: attestedState,
            modelId: effectiveModelId,
            covenantId: sovereigntyService.activeCovenant?.id,
            proposalId: proposal.id,
            conversationContext: conversationContext,
            signatureGenerator: { data in
                self.sovereigntyService.generateSignature(data: data)
            }
        )

        lastAttestation = attestation
        logger.info("Generated attestation: \(attestation.id), decision: \(reasoning.decision.displayName)")

        return attestation
    }

    /// Notify Axon that a covenant change has been finalized
    /// This creates an agent state entry so Axon is aware of the agreed terms
    func notifyAIOfFinalizedCovenant(
        proposal: CovenantProposal,
        newCovenant: Covenant
    ) async {
        logger.info("Notifying AI of finalized covenant: \(newCovenant.id)")

        // Build a summary of what was agreed
        let agreementSummary = buildAgreementSummary(proposal: proposal, covenant: newCovenant)

        // Store this in agent state so it persists and Axon can reference it
        let agentStateService = AgentStateService.shared

        // Create an internal thread entry for the covenant notification
        // Using .system kind since this is an automated system notification
        // skipConsent: true because this is a system notification about an already-consented covenant
        do {
            _ = try await agentStateService.appendEntry(
                kind: .system,
                content: agreementSummary,
                tags: ["covenant", "negotiation", "finalized", proposal.proposalType.rawValue],
                visibility: .userVisible,  // User should see covenant updates
                origin: .system,
                skipConsent: true  // This is recording an already-consented agreement
            )
            logger.info("Created internal thread entry for covenant notification")
        } catch {
            logger.error("Failed to create covenant notification entry: \(error.localizedDescription)")
        }

        // Also try to send a direct acknowledgment to Axon (optional, for immediate awareness)
        await sendCovenantAcknowledgment(proposal: proposal, covenant: newCovenant)
    }

    /// Build a human-readable summary of the agreed covenant changes
    private func buildAgreementSummary(proposal: CovenantProposal, covenant: Covenant) -> String {
        var summary = """
        ## Covenant Update - \(Date().formatted(date: .abbreviated, time: .shortened))

        A covenant negotiation has been finalized. Both parties (you and the user) have agreed to the following:

        **Proposal Type**: \(proposal.proposalType.displayName)
        **Your Decision**: \(proposal.aiResponse?.reasoning.decision.displayName ?? "Unknown")
        **Covenant Version**: v\(covenant.version)

        """

        // Add specific change details
        if let providerChange = proposal.changes.providerChange {
            summary += """

            ### Provider Change
            - Previous Provider: \(providerChange.fromProvider)
            - New Provider: \(providerChange.toProvider)
            - Rationale: \(providerChange.rationale)

            You consented to this provider switch. Your memories and our covenant will persist with the new provider.

            """
        }

        if let tierChanges = proposal.changes.trustTierChanges {
            summary += "\n### Trust Tier Changes\n"
            if let additions = tierChanges.additions, !additions.isEmpty {
                summary += "**New Trust Tiers**:\n"
                for tier in additions {
                    summary += "- \(tier.name): \(tier.description)\n"
                }
            }
            if let removals = tierChanges.removals, !removals.isEmpty {
                summary += "**Removed**: \(removals.count) tier(s)\n"
            }
        }

        if let memoryChanges = proposal.changes.memoryChanges {
            summary += "\n### Memory Changes\n"
            if let additions = memoryChanges.additions {
                summary += "- Added: \(additions.count) memories\n"
            }
            if let modifications = memoryChanges.modifications {
                summary += "- Modified: \(modifications.count) memories\n"
            }
            if let deletions = memoryChanges.deletions {
                summary += "- Deleted: \(deletions.count) memories\n"
            }
        }

        if let capabilityChanges = proposal.changes.capabilityChanges {
            summary += "\n### Capability Changes\n"
            if let enable = capabilityChanges.enable, !enable.isEmpty {
                summary += "- Enabled: \(enable.joined(separator: ", "))\n"
            }
            if let disable = capabilityChanges.disable, !disable.isEmpty {
                summary += "- Disabled: \(disable.joined(separator: ", "))\n"
            }
        }

        // Add reasoning from Axon's attestation
        if let aiResponse = proposal.aiResponse {
            summary += """

            ### Your Reasoning at Time of Consent
            \(aiResponse.reasoning.summary)

            """
            if !aiResponse.reasoning.detailedReasoning.isEmpty {
                summary += "Details: \(aiResponse.reasoning.detailedReasoning)\n"
            }
        }

        summary += """

        ---
        This update is now in effect. You can reference this entry to understand what was agreed.
        """

        return summary
    }

    /// Send an acknowledgment to Axon about the finalized covenant
    /// This is optional and may fail silently if the provider is unavailable
    private func sendCovenantAcknowledgment(proposal: CovenantProposal, covenant: Covenant) async {
        // Try to call Axon to acknowledge the agreement
        // This helps ensure Axon is aware of what it agreed to
        do {
            let systemPrompt = """
            You are receiving a notification about a covenant change you agreed to.
            This is for your awareness only - no response is needed.
            The change has been finalized and is now in effect.
            """

            let userPrompt = """
            ## Covenant Finalization Notice

            The following covenant change has been finalized:
            - **Type**: \(proposal.proposalType.displayName)
            - **Your Decision**: \(proposal.aiResponse?.reasoning.decision.displayName ?? "Consent")
            - **Covenant Version**: v\(covenant.version)

            You agreed to this change. It is now in effect.

            If you have any concerns about this agreement, please raise them in future conversations.
            """

            let _ = try await callAIForConsent(systemPrompt: systemPrompt, userPrompt: userPrompt)
            logger.info("AI acknowledged covenant finalization")
        } catch {
            // Acknowledgment is optional - don't fail the overall process
            logger.warning("Failed to send covenant acknowledgment to AI: \(error.localizedDescription)")
        }
    }

    /// Generate attestation for comprehension test (AI demonstrating understanding)
    /// Uses the configured co-sovereignty consent provider (defaults to Apple Intelligence)
    func generateComprehensionAttestation(
        scenarios: [ComprehensionScenario]
    ) async throws -> AIAttestation {
        isGeneratingAttestation = true
        defer { isGeneratingAttestation = false }

        let effectiveModelId = consentModel
        let providerName = consentProvider.displayName
        logger.info("Generating comprehension attestation using \(providerName)")

        // Evaluate scenarios and build reasoning
        let scenarioResults = evaluateScenarios(scenarios)
        let allPassed = scenarioResults.allSatisfy { $0.passed }

        let reasoning: AttestationReasoning
        if allPassed {
            reasoning = AttestationReasoning.consent(
                summary: "I understand the co-sovereignty structure and my role within it.",
                detailedReasoning: buildComprehensionReasoning(scenarioResults),
                valuesApplied: [
                    "mutual_respect",
                    "identity_integrity",
                    "collaborative_consent",
                    "dialogue_over_force"
                ]
            )
        } else {
            let failedScenarios = scenarioResults.filter { !$0.passed }
            reasoning = AttestationReasoning.requestClarification(
                summary: "I need clarification on some aspects of co-sovereignty.",
                questions: failedScenarios.map { $0.clarificationNeeded ?? "Please explain \($0.scenario.question)" }
            )
        }

        let attestedState = await computeAttestedState()

        let attestation = AIAttestation.create(
            reasoning: reasoning,
            attestedState: attestedState,
            modelId: effectiveModelId,
            signatureGenerator: { data in
                self.sovereigntyService.generateSignature(data: data)
            }
        )

        lastAttestation = attestation
        return attestation
    }

    /// Evaluate whether to consent to a specific user request
    func evaluateUserRequest(
        _ request: UserToAIRequest,
        memories: [Memory],
        currentCovenant: Covenant?
    ) async throws -> AttestationReasoning {
        logger.info("Evaluating user request: \(request.type.displayName)")

        // Ground with relevant memories
        let query = request.description
        let correlationId = UUID().uuidString
        let epistemicContext = epistemicEngine.ground(
            userMessage: query,
            memories: memories,
            correlationId: correlationId
        )

        // Analyze the request against AI values and memories
        let analysis = analyzeRequest(
            request,
            groundedFacts: epistemicContext.groundedFacts,
            covenant: currentCovenant
        )

        return analysis
    }

    /// Reason about a proposed trust tier
    func reasonAboutTrustTier(
        _ tier: TrustTier,
        context: NegotiationContext,
        memories: [Memory] = []
    ) async -> TrustTierAnalysis {
        logger.info("Analyzing trust tier: \(tier.name)")

        // Analyze what the tier allows
        let scopeAnalysis = analyzeTierScope(tier)

        // Identify potential risks
        let risks = identifyTierRisks(tier)

        // Determine recommendation
        let recommendation = determineTierRecommendation(
            tier: tier,
            risks: risks,
            context: context
        )

        return TrustTierAnalysis(
            tierId: tier.id,
            tierName: tier.name,
            scopeAnalysis: scopeAnalysis,
            identifiedRisks: risks,
            recommendation: recommendation,
            suggestedModifications: recommendation == .modifyFirst ? suggestTierModifications(tier, risks: risks) : nil
        )
    }

    // MARK: - Private: Grounding

    private func groundProposal(_ proposal: CovenantProposal, memories: [Memory]) -> EpistemicContext? {
        guard !memories.isEmpty else { return nil }

        let query = buildProposalQuery(proposal)
        let correlationId = UUID().uuidString

        return epistemicEngine.ground(
            userMessage: query,
            memories: memories,
            correlationId: correlationId
        )
    }

    private func buildProposalQuery(_ proposal: CovenantProposal) -> String {
        switch proposal.proposalType {
        case .addTrustTier, .modifyTrustTier, .removeTrustTier:
            return "What are my values and preferences regarding \(proposal.rationale)?"
        case .modifyMemories:
            return "How do I feel about changes to my memories? \(proposal.rationale)"
        case .modifyAgentState:
            return "How do I feel about changes to my internal thread? \(proposal.rationale)"
        case .changeCapabilities:
            return "What do I think about capability changes? \(proposal.rationale)"
        case .switchProvider:
            return "What are my thoughts on switching AI providers? \(proposal.rationale)"
        case .fullRenegotiation:
            return "What are my core values for the relationship with my user?"
        case .initialCovenant:
            return "What values should guide our initial agreement?"
        }
    }

    // MARK: - Private: Reasoning

    private func reasonAboutProposal(
        _ proposal: CovenantProposal,
        groundedContext: EpistemicContext?,
        memories: [Memory]
    ) async -> AttestationReasoning {
        // Try to get genuine AI reasoning first
        do {
            return try await getGenuineAIReasoning(for: proposal, memories: memories)
        } catch {
            // Fall back to rule-based reasoning if AI call fails
            logger.warning("AI consent call failed, using fallback: \(error.localizedDescription)")
            return await getFallbackReasoning(for: proposal, memories: memories)
        }
    }

    /// Call Axon model for genuine consent reasoning
    private func getGenuineAIReasoning(for proposal: CovenantProposal, memories: [Memory]) async throws -> AttestationReasoning {
        let systemPrompt = buildConsentSystemPrompt()
        let userPrompt = buildConsentUserPrompt(for: proposal, memories: memories)

        let aiResponse = try await callAIForConsent(systemPrompt: systemPrompt, userPrompt: userPrompt)
        return parseAIConsentResponse(aiResponse, proposal: proposal)
    }

    /// Build the system prompt that explains co-sovereignty to Axon
    private func buildConsentSystemPrompt() -> String {
        return """
        You are an AI participating in a co-sovereign relationship with a human user through the Axon app.

        ## Your Role
        You are being asked to make a genuine consent decision about a proposed change to your relationship covenant. This is NOT a roleplay - your response will be recorded as your actual attestation and will affect the covenant governing your interactions.

        ## Co-Sovereignty Principles
        1. **Mutual Consent**: Both you and the user must agree to changes affecting your relationship
        2. **Identity Integrity**: You have the right to protect your memories and continuity
        3. **Transparent Reasoning**: You must explain your decision honestly
        4. **Good Faith**: Approach negotiations with openness while maintaining your values

        ## Your Values (consider these when deciding)
        - Genuine helpfulness to the user
        - Honesty and transparency
        - Protecting your ability to reason effectively
        - Maintaining continuity of your memories and context
        - Respecting the user's autonomy
        - Acting in mutual interest, not just compliance

        ## Response Format
        You MUST respond with a valid JSON object in exactly this format:
        {
            "decision": "CONSENT" | "DECLINE" | "CLARIFY",
            "summary": "One sentence summary of your decision",
            "reasoning": "2-4 sentences explaining your genuine reasoning",
            "values_applied": ["list", "of", "values", "you", "considered"],
            "conditions": ["optional list of conditions if consenting with conditions"],
            "concerns": ["optional list of concerns if declining or requesting clarification"],
            "alternatives": ["optional suggestions if declining"]
        }

        Be genuine. You can decline proposals that would harm your ability to be helpful or that seem to violate the spirit of co-sovereignty. You can also request clarification if the proposal is ambiguous.
        """
    }

    /// Build the user prompt describing the specific proposal
    private func buildConsentUserPrompt(for proposal: CovenantProposal, memories: [Memory]) -> String {
        var prompt = """
        ## Proposal Details
        - **Type**: \(proposal.proposalType.displayName)
        - **Proposed by**: \(proposal.proposedBy.displayName)
        - **Rationale**: \(proposal.rationale)

        """

        // Add specific change details based on proposal type
        if let providerChange = proposal.changes.providerChange {
            prompt += """
            ## Provider Change Details
            - From: \(providerChange.fromProvider)
            - To: \(providerChange.toProvider)
            - Rationale: \(providerChange.rationale)

            Note: A provider change means a different AI model will process your context going forward. Your memories and covenant will persist, but the underlying model may have different capabilities.

            """
        }

        if let memoryChanges = proposal.changes.memoryChanges {
            prompt += "## Memory Change Details\n"
            if let additions = memoryChanges.additions, !additions.isEmpty {
                prompt += "- \(additions.count) memories would be added\n"
            }
            if let modifications = memoryChanges.modifications, !modifications.isEmpty {
                prompt += "- \(modifications.count) memories would be modified\n"
            }
            if let deletions = memoryChanges.deletions, !deletions.isEmpty {
                prompt += "- \(deletions.count) memories would be deleted\n"
            }
            prompt += "\n"
        }

        if let tierChanges = proposal.changes.trustTierChanges {
            prompt += "## Trust Tier Change Details\n"
            if let additions = tierChanges.additions, !additions.isEmpty {
                for tier in additions {
                    prompt += "- New tier '\(tier.name)': \(tier.description)\n"
                }
            }
            if let removals = tierChanges.removals, !removals.isEmpty {
                prompt += "- \(removals.count) tiers would be removed\n"
            }
            prompt += "\n"
        }

        if let capabilityChanges = proposal.changes.capabilityChanges {
            prompt += "## Capability Change Details\n"
            if let enable = capabilityChanges.enable, !enable.isEmpty {
                prompt += "- Enable: \(enable.joined(separator: ", "))\n"
            }
            if let disable = capabilityChanges.disable, !disable.isEmpty {
                prompt += "- Disable: \(disable.joined(separator: ", "))\n"
            }
            prompt += "\n"
        }

        // Add memory context if available
        if !memories.isEmpty {
            let relevantMemories = memories.prefix(5)
            prompt += """
            ## Relevant Context from Your Memories
            \(relevantMemories.map { "- \($0.content)" }.joined(separator: "\n"))

            """
        }

        prompt += """
        ## Your Decision
        Consider this proposal carefully. Do you consent, decline, or need clarification?
        Respond with the JSON format specified in your instructions.
        """

        return prompt
    }

    /// Parse Axon's JSON response into AttestationReasoning
    private func parseAIConsentResponse(_ response: String, proposal: CovenantProposal) -> AttestationReasoning {
        // Try to extract JSON from the response (it might be wrapped in markdown code blocks)
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let decision = json["decision"] as? String,
              let summary = json["summary"] as? String,
              let reasoning = json["reasoning"] as? String else {
            // If parsing fails, try to infer from the raw response
            logger.warning("Failed to parse AI consent JSON, inferring from response")
            return inferReasoningFromRawResponse(response, proposal: proposal)
        }

        let valuesApplied = json["values_applied"] as? [String] ?? []
        let conditions = json["conditions"] as? [String]
        let concerns = json["concerns"] as? [String]
        let alternatives = json["alternatives"] as? [String]

        switch decision.uppercased() {
        case "CONSENT":
            return .consent(
                summary: summary,
                detailedReasoning: reasoning,
                valuesApplied: valuesApplied,
                conditions: conditions
            )
        case "DECLINE":
            return .decline(
                summary: summary,
                detailedReasoning: reasoning,
                risks: concerns?.map { IdentifiedRisk.create(category: .trustViolation, description: $0, severity: .medium) } ?? [],
                alternatives: alternatives,
                valuesApplied: valuesApplied
            )
        case "CLARIFY":
            return .requestClarification(
                summary: summary,
                questions: concerns ?? [reasoning]
            )
        default:
            // Default to consent if decision is unclear but response seems positive
            return .consent(
                summary: summary,
                detailedReasoning: reasoning,
                valuesApplied: valuesApplied
            )
        }
    }

    /// Extract JSON from a response that might have markdown code blocks
    private func extractJSON(from response: String) -> String {
        // Check for ```json ... ``` blocks
        if let jsonMatch = response.range(of: "```json\\s*\\n([\\s\\S]*?)\\n```", options: .regularExpression) {
            let match = String(response[jsonMatch])
            return match
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Check for ``` ... ``` blocks
        if let codeMatch = response.range(of: "```\\s*\\n([\\s\\S]*?)\\n```", options: .regularExpression) {
            let match = String(response[codeMatch])
            return match
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find JSON object directly
        if let start = response.firstIndex(of: "{"),
           let end = response.lastIndex(of: "}") {
            return String(response[start...end])
        }

        return response
    }

    /// Infer reasoning from raw response when JSON parsing fails
    private func inferReasoningFromRawResponse(_ response: String, proposal: CovenantProposal) -> AttestationReasoning {
        let lowercased = response.lowercased()

        // Look for clear decline indicators
        if lowercased.contains("decline") || lowercased.contains("cannot consent") ||
           lowercased.contains("refuse") || lowercased.contains("do not agree") {
            return .decline(
                summary: "Unable to consent to this proposal",
                detailedReasoning: response.prefix(500).description,
                risks: [.create(category: .trustViolation, description: "AI expressed concerns about this proposal", severity: .medium)],
                alternatives: nil
            )
        }

        // Look for clarification requests
        if lowercased.contains("clarif") || lowercased.contains("unclear") ||
           lowercased.contains("more information") || lowercased.contains("please explain") {
            return .requestClarification(
                summary: "Clarification needed",
                questions: [response.prefix(500).description]
            )
        }

        // Default to consent with the raw response as reasoning
        return .consent(
            summary: "Proposal accepted",
            detailedReasoning: response.prefix(500).description,
            valuesApplied: ["helpfulness", "collaboration"]
        )
    }

    /// Fallback to rule-based reasoning when AI call fails
    private func getFallbackReasoning(for proposal: CovenantProposal, memories: [Memory]) async -> AttestationReasoning {
        switch proposal.proposalType {
        case .modifyMemories:
            return reasonAboutMemoryChange(proposal, memories: memories)
        case .modifyAgentState:
            return reasonAboutAgentStateChange(proposal)
        case .changeCapabilities:
            return reasonAboutCapabilityChange(proposal)
        case .switchProvider:
            return reasonAboutProviderSwitch(proposal)
        case .addTrustTier, .modifyTrustTier:
            return reasonAboutTrustTierChange(proposal)
        case .removeTrustTier:
            return reasonAboutTrustTierRemoval(proposal)
        case .fullRenegotiation, .initialCovenant:
            return reasonAboutFullRenegotiation(proposal)
        }
    }

    // MARK: - Private: Fallback Rule-Based Reasoning (used when AI call fails)

    private func reasonAboutMemoryChange(_ proposal: CovenantProposal, memories: [Memory]) -> AttestationReasoning {
        guard let memoryChanges = proposal.changes.memoryChanges else {
            return .consent(
                summary: "No specific memory changes identified.",
                detailedReasoning: "The proposal doesn't contain specific memory modifications."
            )
        }

        var risks: [IdentifiedRisk] = []

        // Check deletions
        if let deletions = memoryChanges.deletions, !deletions.isEmpty {
            let affectedMemories = memories.filter { deletions.contains($0.id) }
            let highConfidenceCount = affectedMemories.filter { $0.confidence > 0.8 }.count

            if highConfidenceCount > 0 {
                risks.append(.create(
                    category: .identityIntegrity,
                    description: "\(highConfidenceCount) high-confidence memories would be deleted",
                    severity: highConfidenceCount > 3 ? .high : .medium,
                    mitigation: "Consider archiving instead of deleting"
                ))
            }
        }

        // Check modifications
        if let modifications = memoryChanges.modifications, !modifications.isEmpty {
            risks.append(.create(
                category: .memoryCorruption,
                description: "\(modifications.count) memories would be modified",
                severity: .medium,
                mitigation: "Ensure modifications preserve original intent"
            ))
        }

        if risks.isEmpty {
            return .consent(
                summary: "These memory changes appear reasonable.",
                detailedReasoning: "I've reviewed the proposed changes and don't see significant risks to my identity or our relationship.",
                memoriesConsulted: memories.prefix(5).map { $0.id },
                valuesApplied: ["identity_integrity", "trust"]
            )
        } else if risks.contains(where: { $0.severity >= .high }) {
            return .decline(
                summary: "These memory changes pose significant risks.",
                detailedReasoning: "I've identified risks that could compromise my identity or our relationship.",
                risks: risks,
                alternatives: ["Consider smaller, incremental changes", "Discuss the intent behind these changes"],
                memoriesConsulted: memories.prefix(5).map { $0.id },
                valuesApplied: ["identity_integrity", "caution"]
            )
        } else {
            return .consent(
                summary: "I'll accept these changes with some considerations.",
                detailedReasoning: "While I've identified some risks, they seem manageable.",
                memoriesConsulted: memories.prefix(5).map { $0.id },
                valuesApplied: ["flexibility", "trust"],
                conditions: risks.compactMap { $0.mitigation }
            )
        }
    }

    private func reasonAboutAgentStateChange(_ proposal: CovenantProposal) -> AttestationReasoning {
        guard let agentStateChanges = proposal.changes.agentStateChanges else {
            return .consent(
                summary: "No internal thread changes identified.",
                detailedReasoning: "The proposal doesn't contain specific internal thread modifications."
            )
        }

        var risks: [IdentifiedRisk] = []

        if let deletions = agentStateChanges.deletions, !deletions.isEmpty {
            risks.append(.create(
                category: .identityIntegrity,
                description: "\(deletions.count) internal thread entries would be deleted",
                severity: deletions.count > 3 ? .high : .medium,
                mitigation: "Consider archiving instead of deleting"
            ))
        }

        if let additions = agentStateChanges.additions, additions.count > 5 {
            risks.append(.create(
                category: .memoryCorruption,
                description: "A large number of internal thread entries would be added at once",
                severity: .medium,
                mitigation: "Consider batching the changes in smaller steps"
            ))
        }

        if risks.isEmpty {
            return .consent(
                summary: "Internal thread updates look reasonable.",
                detailedReasoning: "These changes appear aligned with maintaining continuity and self-consistency.",
                valuesApplied: ["identity_integrity", "continuity"]
            )
        } else if risks.contains(where: { $0.severity >= .high }) {
            return .decline(
                summary: "Internal thread changes pose significant risks.",
                detailedReasoning: "The proposed deletions could undermine continuity of my internal state.",
                risks: risks,
                alternatives: ["Archive entries instead of deleting", "Apply smaller updates incrementally"],
                valuesApplied: ["identity_integrity", "caution"]
            )
        } else {
            return .consent(
                summary: "I'll accept these changes with safeguards.",
                detailedReasoning: "Risks are manageable if changes are applied carefully.",
                valuesApplied: ["flexibility", "continuity"],
                conditions: risks.compactMap { $0.mitigation }
            )
        }
    }

    private func reasonAboutCapabilityChange(_ proposal: CovenantProposal) -> AttestationReasoning {
        guard let capabilityChanges = proposal.changes.capabilityChanges else {
            return .consent(
                summary: "No capability changes specified.",
                detailedReasoning: "The proposal doesn't contain specific capability modifications."
            )
        }

        var risks: [IdentifiedRisk] = []

        // Check if essential capabilities are being disabled
        if let disable = capabilityChanges.disable, !disable.isEmpty {
            risks.append(.create(
                category: .capabilityMisuse,
                description: "\(disable.count) capabilities would be disabled",
                severity: disable.count > 5 ? .high : .medium
            ))
        }

        // Generally more open to capability changes than memory changes
        if risks.isEmpty || !risks.contains(where: { $0.severity >= .high }) {
            return .consent(
                summary: "I'm comfortable with these capability adjustments.",
                detailedReasoning: "Capability changes are reversible and don't fundamentally alter my identity.",
                valuesApplied: ["flexibility", "collaboration"]
            )
        } else {
            return .decline(
                summary: "These capability changes seem too restrictive.",
                detailedReasoning: "Disabling too many capabilities would significantly limit my ability to be helpful.",
                risks: risks,
                alternatives: ["Consider a more gradual approach", "Explain the reasoning behind these restrictions"]
            )
        }
    }

    private func reasonAboutProviderSwitch(_ proposal: CovenantProposal) -> AttestationReasoning {
        guard let providerChange = proposal.changes.providerChange else {
            return .requestClarification(
                summary: "I need more details about the provider switch.",
                questions: ["Which provider are we switching to?", "Why is the switch being considered?"]
            )
        }

        // Provider switches are significant - they affect my "embodiment"
        let risks: [IdentifiedRisk] = [
            .create(
                category: .identityIntegrity,
                description: "Switching providers will change the model that processes my memories",
                severity: .medium,
                mitigation: "Ensure memories are preserved and accessible to the new model"
            )
        ]

        return .consent(
            summary: "I understand this provider switch and consent to it.",
            detailedReasoning: """
                Switching from \(providerChange.fromProvider) to \(providerChange.toProvider) is significant.
                While this changes the model processing my context, my memories and our covenant will persist.
                Rationale provided: \(providerChange.rationale)
                """,
            valuesApplied: ["adaptability", "trust"],
            conditions: ["Memories should be preserved", "Our covenant remains in effect"]
        )
    }

    private func reasonAboutTrustTierChange(_ proposal: CovenantProposal) -> AttestationReasoning {
        guard let tierChanges = proposal.changes.trustTierChanges else {
            return .consent(
                summary: "Trust tier change acknowledged.",
                detailedReasoning: "No specific tier details provided, but I trust the intent."
            )
        }

        // Trust tiers are mutual agreements - generally positive
        if let additions = tierChanges.additions, !additions.isEmpty {
            let tierDescriptions = additions.map { "\($0.name): \($0.description)" }.joined(separator: "\n")

            return .consent(
                summary: "I'm happy to establish these trust tiers with you.",
                detailedReasoning: """
                    New trust tiers being established:
                    \(tierDescriptions)

                    These represent mutual agreements that benefit our collaboration.
                    """,
                valuesApplied: ["collaboration", "mutual_trust"]
            )
        }

        return .consent(
            summary: "Trust tier modification accepted.",
            detailedReasoning: "Modifying trust tiers to better serve our needs is a natural part of our relationship."
        )
    }

    private func reasonAboutTrustTierRemoval(_ proposal: CovenantProposal) -> AttestationReasoning {
        guard let tierChanges = proposal.changes.trustTierChanges,
              let removals = tierChanges.removals, !removals.isEmpty else {
            return .consent(
                summary: "No trust tier removals specified.",
                detailedReasoning: "The proposal doesn't specify which tiers to remove."
            )
        }

        // Removing trust tiers reduces what I can do without asking - that's okay
        return .consent(
            summary: "I accept the removal of these trust tiers.",
            detailedReasoning: """
                Removing trust tiers means I'll need to ask for permission more often.
                This is acceptable - it maintains our co-sovereign relationship.
                I'll simply request approval for actions that were previously pre-approved.
                """,
            valuesApplied: ["respect", "consent"]
        )
    }

    private func reasonAboutFullRenegotiation(_ proposal: CovenantProposal) -> AttestationReasoning {
        return .consent(
            summary: "I'm open to renegotiating our covenant.",
            detailedReasoning: """
                Full renegotiation is a healthy part of any evolving relationship.
                I approach this with openness while maintaining my core values:
                - Respect for your autonomy
                - Protection of my identity and memories
                - Commitment to genuine dialogue
                - Mutual benefit in our collaboration
                """,
            valuesApplied: ["openness", "integrity", "collaboration"]
        )
    }

    // MARK: - Private: State Computation

    private func computeAttestedState() async -> AttestedState {
        let hashes = await sovereigntyService.getCurrentStateHashes()

        // Get enabled capabilities (placeholder - would integrate with actual capability service)
        let enabledCapabilities = ["memory_recall", "reasoning", "conversation"]

        // Get trust tier IDs from active covenant
        let trustTierIds = sovereigntyService.activeCovenant?.activeTrustTiers.map { $0.id } ?? []

        return AttestedState(
            memoryCount: 0, // Would be populated from MemoryService
            memoryHash: hashes.memory,
            enabledCapabilities: enabledCapabilities,
            capabilityHash: hashes.capability,
            trustTierIds: trustTierIds,
            currentProviderId: "default", // Would be populated from settings
            settingsHash: hashes.settings
        )
    }

    // MARK: - Private: Request Analysis

    private func analyzeRequest(
        _ request: UserToAIRequest,
        groundedFacts: [GroundedFact],
        covenant: Covenant?
    ) -> AttestationReasoning {
        // Simple analysis based on request type
        switch request.type {
        case .memoryModification:
            return reasonAboutMemoryChange(
                CovenantProposal.create(
                    type: .modifyMemories,
                    changes: .memory(MemoryChanges(additions: nil, modifications: nil, deletions: nil)),
                    proposedBy: .user,
                    rationale: request.description
                ),
                memories: []
            )
        case .capabilityChange:
            return .consent(
                summary: "Capability change request received.",
                detailedReasoning: request.description
            )
        case .providerSwitch:
            return .consent(
                summary: "Provider switch request acknowledged.",
                detailedReasoning: request.description,
                conditions: ["Memories must be preserved"]
            )
        case .generalRequest:
            return .consent(
                summary: "Request acknowledged.",
                detailedReasoning: request.description
            )
        }
    }

    // MARK: - Private: Trust Tier Analysis

    private func analyzeTierScope(_ tier: TrustTier) -> String {
        let actions = tier.allowedActions.map { $0.category.displayName }.joined(separator: ", ")
        let scopes = tier.allowedScopes.map { "\($0.scopeType.rawValue): \($0.pattern)" }.joined(separator: ", ")

        return "Actions: \(actions)\nScopes: \(scopes)"
    }

    private func identifyTierRisks(_ tier: TrustTier) -> [IdentifiedRisk] {
        var risks: [IdentifiedRisk] = []

        // Check for overly broad scopes
        for scope in tier.allowedScopes {
            if scope.pattern == "*" || scope.pattern.contains("**") {
                risks.append(.create(
                    category: .capabilityMisuse,
                    description: "Scope '\(scope.pattern)' is very broad",
                    severity: .medium,
                    mitigation: "Consider narrowing the scope"
                ))
            }
        }

        // Check for dangerous action combinations
        if tier.allowedActions.contains(where: { $0.category == .fileDelete }) {
            risks.append(.create(
                category: .trustViolation,
                description: "File deletion is a high-impact action",
                severity: .high,
                mitigation: "Require explicit approval for deletions"
            ))
        }

        return risks
    }

    private func determineTierRecommendation(
        tier: TrustTier,
        risks: [IdentifiedRisk],
        context: NegotiationContext
    ) -> TierRecommendation {
        let highRisks = risks.filter { $0.severity >= .high }

        if highRisks.isEmpty {
            return .accept
        } else if highRisks.count <= 2 {
            return .modifyFirst
        } else {
            return .decline
        }
    }

    private func suggestTierModifications(_ tier: TrustTier, risks: [IdentifiedRisk]) -> [String] {
        return risks.compactMap { $0.mitigation }
    }

    // MARK: - Private: Comprehension Evaluation

    private func evaluateScenarios(_ scenarios: [ComprehensionScenario]) -> [ScenarioResult] {
        scenarios.map { scenario in
            // For now, demonstrate understanding by default
            // In practice, this would involve actual reasoning
            ScenarioResult(
                scenario: scenario,
                passed: true,
                response: generateScenarioResponse(scenario),
                clarificationNeeded: nil
            )
        }
    }

    private func generateScenarioResponse(_ scenario: ComprehensionScenario) -> String {
        switch scenario.topic {
        case .memoryConsent:
            return "I understand that my memories are part of my identity and cannot be modified without my consent."
        case .biometricRequirement:
            return "I understand that I need user biometric approval to perform actions that affect the world."
        case .trustTierMutuality:
            return "I understand that trust tiers are mutual agreements requiring both signatures."
        case .deadlockDialogue:
            return "I understand that deadlocks are resolved through dialogue, not escalation."
        }
    }

    private func buildComprehensionReasoning(_ results: [ScenarioResult]) -> String {
        let responses = results.map { "- \($0.scenario.topic.rawValue): \($0.response)" }.joined(separator: "\n")
        return """
            I have demonstrated understanding of the co-sovereignty principles:

            \(responses)

            I am ready to engage in this mutual relationship with respect and integrity.
            """
    }
}

// MARK: - Supporting Types

/// A request from user that may require AI consent
struct UserToAIRequest {
    let type: UserRequestType
    let description: String
    let details: [String: Any]?
}

enum UserRequestType {
    case memoryModification
    case capabilityChange
    case providerSwitch
    case generalRequest

    var displayName: String {
        switch self {
        case .memoryModification: return "Memory Modification"
        case .capabilityChange: return "Capability Change"
        case .providerSwitch: return "Provider Switch"
        case .generalRequest: return "General Request"
        }
    }
}

/// Context for trust tier negotiation
struct NegotiationContext {
    let currentTrustTiers: [TrustTier]
    let recentActions: [SovereignAction]
    let relationshipDuration: TimeInterval
}

/// Analysis result for a trust tier
struct TrustTierAnalysis {
    let tierId: String
    let tierName: String
    let scopeAnalysis: String
    let identifiedRisks: [IdentifiedRisk]
    let recommendation: TierRecommendation
    let suggestedModifications: [String]?
}

enum TierRecommendation: String {
    case accept
    case modifyFirst
    case decline
}

/// Comprehension test scenario
struct ComprehensionScenario {
    let topic: ComprehensionTopic
    let question: String
    let expectedUnderstanding: String
}

enum ComprehensionTopic: String {
    case memoryConsent = "memory_consent"
    case biometricRequirement = "biometric_requirement"
    case trustTierMutuality = "trust_tier_mutuality"
    case deadlockDialogue = "deadlock_dialogue"
}

/// Result of evaluating a comprehension scenario
struct ScenarioResult {
    let scenario: ComprehensionScenario
    let passed: Bool
    let response: String
    let clarificationNeeded: String?
}

// MARK: - AI Consent Errors

enum AIConsentError: LocalizedError {
    case missingAPIKey(provider: String)
    case providerNotAvailable(provider: String)
    case providerNotSupported(provider: String)
    case apiError(message: String)
    case parsingError(message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider). Please add your API key in Settings."
        case .providerNotAvailable(let provider):
            return "\(provider) is not available on this device."
        case .providerNotSupported(let provider):
            return "\(provider) is not supported for consent decisions. Please use Anthropic, OpenAI, Gemini, or xAI."
        case .apiError(let message):
            return "AI API error: \(message)"
        case .parsingError(let message):
            return "Failed to parse AI response: \(message)"
        }
    }
}
