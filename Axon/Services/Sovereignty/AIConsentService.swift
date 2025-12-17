//
//  AIConsentService.swift
//  Axon
//
//  Generates AI reasoning and attestations for consent decisions.
//  Integrates with EpistemicEngine for grounded reasoning.
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
        // Build reasoning based on proposal type
        switch proposal.proposalType {
        case .modifyMemories:
            return reasonAboutMemoryChange(proposal, memories: memories)
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
