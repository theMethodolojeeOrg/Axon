//
//  CovenantNegotiationService.swift
//  Axon
//
//  Manages the proposal/counter-proposal flow for covenant negotiations.
//  Handles the lifecycle of proposals from creation through ratification.
//

import Foundation
import Combine
import os.log

// MARK: - Negotiation State

enum NegotiationState: Equatable {
    case idle
    case awaitingAIResponse(CovenantProposal)
    case awaitingUserResponse(CovenantProposal)
    case counterProposalPending(CovenantProposal)
    case deadlocked(CovenantProposal)
    case finalizing(CovenantProposal)
    case completed(CovenantProposal)

    var isActive: Bool {
        switch self {
        case .idle, .completed:
            return false
        default:
            return true
        }
    }

    var currentProposal: CovenantProposal? {
        switch self {
        case .idle:
            return nil
        case .awaitingAIResponse(let proposal),
             .awaitingUserResponse(let proposal),
             .counterProposalPending(let proposal),
             .deadlocked(let proposal),
             .finalizing(let proposal),
             .completed(let proposal):
            return proposal
        }
    }
}

// MARK: - Negotiation Response

enum NegotiationResponse {
    case accept
    case reject
    case counterPropose(ProposedChanges)
    case requestClarification(String)
}

// MARK: - Covenant Negotiation Service

@MainActor
final class CovenantNegotiationService: ObservableObject {
    static let shared = CovenantNegotiationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "CovenantNegotiation")
    private let sovereigntyService = SovereigntyService.shared
    private let aiConsentService = AIConsentService.shared
    private let biometricService = BiometricAuthService.shared
    private let deviceIdentity = DeviceIdentity.shared

    // MARK: - Published State

    @Published private(set) var negotiationState: NegotiationState = .idle
    @Published private(set) var activeNegotiation: CovenantProposal?
    @Published private(set) var negotiationHistory: [CovenantProposal] = []

    private init() {}

    // MARK: - Public API: Start Negotiation

    /// Initiate a new negotiation
    func initiateNegotiation(
        type: ProposalType,
        changes: ProposedChanges,
        fromUser: Bool,
        rationale: String,
        expiresIn: TimeInterval? = nil
    ) async throws -> CovenantProposal {
        guard !negotiationState.isActive else {
            throw SovereigntyError.invalidState("A negotiation is already in progress")
        }

        logger.info("Initiating \(type.displayName) negotiation from \(fromUser ? "user" : "AI")")

        let proposal = CovenantProposal.create(
            type: type,
            changes: changes,
            proposedBy: fromUser ? .user : .ai,
            rationale: rationale,
            expiresIn: expiresIn
        )

        // Submit to sovereignty service
        try sovereigntyService.submitProposal(proposal)

        activeNegotiation = proposal

        // Set state based on who needs to respond
        if fromUser {
            // User proposed, AI needs to respond
            negotiationState = .awaitingAIResponse(proposal)

            // Automatically request AI response
            try await requestAIResponse(for: proposal)
        } else {
            // AI proposed, user needs to respond
            negotiationState = .awaitingUserResponse(proposal)
        }

        return proposal
    }

    /// Create a proposal for adding a trust tier
    func proposeTrustTier(
        _ tier: TrustTier,
        fromUser: Bool,
        rationale: String
    ) async throws -> CovenantProposal {
        let changes = ProposedChanges.trustTier(
            TrustTierChanges(additions: [tier], modifications: nil, removals: nil)
        )

        return try await initiateNegotiation(
            type: .addTrustTier,
            changes: changes,
            fromUser: fromUser,
            rationale: rationale
        )
    }

    /// Create a proposal for memory changes
    func proposeMemoryChanges(
        _ memoryChanges: MemoryChanges,
        fromUser: Bool,
        rationale: String
    ) async throws -> CovenantProposal {
        let changes = ProposedChanges.memory(memoryChanges)

        return try await initiateNegotiation(
            type: .modifyMemories,
            changes: changes,
            fromUser: fromUser,
            rationale: rationale
        )
    }

    /// Create a proposal for provider switch
    func proposeProviderSwitch(
        from: String,
        to: String,
        rationale: String
    ) async throws -> CovenantProposal {
        let providerChange = ProviderChange(
            fromProvider: from,
            toProvider: to,
            fromModel: nil,
            toModel: nil,
            rationale: rationale
        )

        return try await initiateNegotiation(
            type: .switchProvider,
            changes: .provider(providerChange),
            fromUser: true,
            rationale: rationale
        )
    }

    // MARK: - Public API: Response Handling

    /// Process a response to the current proposal
    func processResponse(
        to proposalId: String,
        response: NegotiationResponse,
        from: ProposalOriginator
    ) async throws {
        guard let proposal = activeNegotiation, proposal.id == proposalId else {
            throw SovereigntyError.invalidState("No active proposal with ID: \(proposalId)")
        }

        logger.info("Processing \(from.displayName) response to proposal \(proposalId)")

        switch response {
        case .accept:
            try await handleAcceptance(proposal: proposal, from: from)

        case .reject:
            try await handleRejection(proposal: proposal, from: from)

        case .counterPropose(let newChanges):
            try await handleCounterProposal(
                originalProposal: proposal,
                newChanges: newChanges,
                from: from
            )

        case .requestClarification(let question):
            try await handleClarificationRequest(
                proposal: proposal,
                question: question,
                from: from
            )
        }
    }

    /// User accepts the current proposal
    func userAccepts() async throws {
        guard let proposal = activeNegotiation else {
            throw SovereigntyError.invalidState("No active negotiation")
        }

        try await processResponse(
            to: proposal.id,
            response: .accept,
            from: .user
        )
    }

    /// User rejects the current proposal
    func userRejects() async throws {
        guard let proposal = activeNegotiation else {
            throw SovereigntyError.invalidState("No active negotiation")
        }

        try await processResponse(
            to: proposal.id,
            response: .reject,
            from: .user
        )
    }

    /// User counter-proposes
    func userCounterProposes(_ changes: ProposedChanges) async throws {
        guard let proposal = activeNegotiation else {
            throw SovereigntyError.invalidState("No active negotiation")
        }

        try await processResponse(
            to: proposal.id,
            response: .counterPropose(changes),
            from: .user
        )
    }

    // MARK: - Public API: AI Response

    /// Request AI to respond to a proposal
    func requestAIResponse(for proposal: CovenantProposal) async throws {
        logger.info("Requesting AI response for proposal: \(proposal.id)")

        let attestation = try await aiConsentService.generateAttestation(
            for: proposal,
            conversationContext: nil
        )

        // Update proposal with AI response
        try sovereigntyService.updateProposalWithAIResponse(proposal.id, attestation: attestation)

        // Update local state
        let updatedProposal = proposal.withAIResponse(attestation)
        activeNegotiation = updatedProposal

        // Handle AI decision
        if attestation.didConsent {
            if updatedProposal.proposedBy == .user {
                // AI consented to user proposal, now need user to finalize
                negotiationState = .finalizing(updatedProposal)
                // Request user signature to complete
            } else {
                // AI proposed and consented to its own proposal (shouldn't happen but handle it)
                negotiationState = .awaitingUserResponse(updatedProposal)
            }
        } else if attestation.didDecline {
            // AI declined - may need to counter-propose or enter deadlock
            if let alternatives = attestation.reasoning.alternatives, !alternatives.isEmpty {
                negotiationState = .counterProposalPending(updatedProposal)
            } else {
                // No alternatives offered - enter deadlock
                try await enterDeadlock(proposal: updatedProposal, reason: .aiRefusedUserRequest)
            }
        } else if attestation.requestedClarification {
            // AI needs clarification
            negotiationState = .awaitingUserResponse(updatedProposal)
        }
    }

    // MARK: - Public API: Finalization

    /// Finalize the proposal with user biometric signature
    func finalizeWithUserSignature() async throws -> Covenant {
        guard let proposal = activeNegotiation else {
            throw SovereigntyError.invalidState("No active negotiation")
        }

        guard proposal.aiResponse?.didConsent == true else {
            throw SovereigntyError.invalidState("AI has not consented to this proposal")
        }

        logger.info("Finalizing proposal with user signature")

        // Request biometric authentication
        let authResult = await biometricService.authenticate(
            reason: "Approve \(proposal.proposalType.displayName)"
        )

        switch authResult {
        case .success:
            // Generate user signature
            let signatureData = "\(proposal.id):\(proposal.changes)"
            let signature = UserSignature.create(
                signedItemType: .covenantProposal,
                signedItemId: proposal.id,
                signedDataHash: deviceIdentity.generateDeviceSignature(data: signatureData),
                biometricType: mapBiometricType(biometricService.biometricType),
                deviceId: deviceIdentity.getDeviceId(),
                covenantId: sovereigntyService.activeCovenant?.id,
                signatureGenerator: { data in
                    self.deviceIdentity.generateDeviceSignature(data: data)
                }
            )

            // Update proposal
            try sovereigntyService.updateProposalWithUserSignature(proposal.id, signature: signature)

            let finalizedProposal = proposal.withUserSignature(signature)

            // Apply changes to covenant
            let newCovenant = try await applyProposalToCovenant(finalizedProposal)

            // Complete negotiation
            completeNegotiation(finalizedProposal)

            return newCovenant

        case .cancelled, .fallback, .failed:
            throw SovereigntyError.userDeclined
        }
    }

    /// Cancel the current negotiation
    func cancelNegotiation() {
        guard let proposal = activeNegotiation else { return }

        logger.info("Cancelling negotiation: \(proposal.id)")

        sovereigntyService.removeProposal(proposal.id)
        negotiationHistory.append(proposal)
        activeNegotiation = nil
        negotiationState = .idle
    }

    // MARK: - Private: Response Handling

    private func handleAcceptance(proposal: CovenantProposal, from: ProposalOriginator) async throws {
        if from == .ai {
            // AI accepted, handled in requestAIResponse
            return
        }

        // User accepted
        if proposal.aiResponse?.didConsent == true {
            // Both parties agree - finalize
            _ = try await finalizeWithUserSignature()
        } else {
            // User accepted but AI hasn't responded yet
            negotiationState = .awaitingAIResponse(proposal)
            try await requestAIResponse(for: proposal)
        }
    }

    private func handleRejection(proposal: CovenantProposal, from: ProposalOriginator) async throws {
        logger.info("\(from.displayName) rejected proposal \(proposal.id)")

        // Check if this should trigger deadlock
        let shouldDeadlock: Bool
        let reason: DeadlockTrigger

        if from == .ai {
            shouldDeadlock = proposal.proposedBy == .user
            reason = .aiRefusedUserRequest
        } else {
            shouldDeadlock = proposal.proposedBy == .ai
            reason = .userRefusedAIAction
        }

        if shouldDeadlock {
            try await enterDeadlock(proposal: proposal, reason: reason)
        } else {
            // Same party rejected their own proposal - just cancel
            cancelNegotiation()
        }
    }

    private func handleCounterProposal(
        originalProposal: CovenantProposal,
        newChanges: ProposedChanges,
        from: ProposalOriginator
    ) async throws {
        logger.info("\(from.displayName) counter-proposed to \(originalProposal.id)")

        // Create counter-proposal
        let counterProposal = CovenantProposal.create(
            type: originalProposal.proposalType,
            changes: newChanges,
            proposedBy: from,
            rationale: "Counter-proposal to \(originalProposal.id)"
        )

        // Link to original
        // In practice, we'd update the original proposal's counterProposals array

        // Switch active negotiation to counter-proposal
        activeNegotiation = counterProposal
        try sovereigntyService.submitProposal(counterProposal)

        // Request response from other party
        if from == .user {
            negotiationState = .awaitingAIResponse(counterProposal)
            try await requestAIResponse(for: counterProposal)
        } else {
            negotiationState = .awaitingUserResponse(counterProposal)
        }
    }

    private func handleClarificationRequest(
        proposal: CovenantProposal,
        question: String,
        from: ProposalOriginator
    ) async throws {
        logger.info("\(from.displayName) requested clarification: \(question)")

        // Add dialogue entry
        let dialogue = NegotiationDialogue(
            id: UUID().uuidString,
            timestamp: Date(),
            speaker: from,
            message: question,
            proposedResolution: nil,
            attestation: nil
        )

        let updatedProposal = proposal.withDialogue(dialogue)
        activeNegotiation = updatedProposal

        // Wait for response from other party
        if from == .ai {
            negotiationState = .awaitingUserResponse(updatedProposal)
        } else {
            negotiationState = .awaitingAIResponse(updatedProposal)
        }
    }

    // MARK: - Private: Deadlock

    private func enterDeadlock(proposal: CovenantProposal, reason: DeadlockTrigger) async throws {
        logger.warning("Entering deadlock: \(reason.displayName)")

        let deadlock = sovereigntyService.enterDeadlock(trigger: reason, proposal: proposal)

        let deadlockedProposal = proposal.deadlocked()
        activeNegotiation = deadlockedProposal
        negotiationState = .deadlocked(deadlockedProposal)

        // Notify deadlock resolution service
        // DeadlockResolutionService.shared.handleDeadlock(deadlock)
    }

    // MARK: - Private: Apply Changes

    private func applyProposalToCovenant(_ proposal: CovenantProposal) async throws -> Covenant {
        guard let currentCovenant = sovereigntyService.activeCovenant else {
            // First covenant
            return try await createInitialCovenant(from: proposal)
        }

        guard let aiAttestation = proposal.aiResponse,
              let userSignature = proposal.userResponse else {
            throw SovereigntyError.invalidState("Proposal is not fully signed")
        }

        // Apply changes based on proposal type
        var newTrustTiers = currentCovenant.trustTiers

        if let tierChanges = proposal.changes.trustTierChanges {
            // Add new tiers
            if let additions = tierChanges.additions {
                for tier in additions {
                    // Sign the tier
                    let signedTier = TrustTier(
                        id: tier.id,
                        name: tier.name,
                        description: tier.description,
                        allowedActions: tier.allowedActions,
                        allowedScopes: tier.allowedScopes,
                        rateLimit: tier.rateLimit,
                        timeRestrictions: tier.timeRestrictions,
                        contextRequirements: tier.contextRequirements,
                        expiresAt: tier.expiresAt,
                        requiresRenewal: tier.requiresRenewal,
                        aiAttestation: aiAttestation,
                        userSignature: userSignature,
                        createdAt: tier.createdAt,
                        updatedAt: Date()
                    )
                    newTrustTiers.append(signedTier)
                }
            }

            // Remove tiers
            if let removals = tierChanges.removals {
                newTrustTiers.removeAll { removals.contains($0.id) }
            }
        }

        // Create updated covenant
        let event = NegotiationEvent(
            id: UUID().uuidString,
            timestamp: Date(),
            eventType: .proposalAccepted,
            description: "Proposal \(proposal.id) applied to covenant",
            proposalId: proposal.id,
            originator: proposal.proposedBy
        )

        let newCovenant = currentCovenant.withUpdatedTrustTiers(
            newTrustTiers,
            aiAttestation: aiAttestation,
            userSignature: userSignature,
            event: event
        )

        try sovereigntyService.updateCovenant(newCovenant)

        return newCovenant
    }

    private func createInitialCovenant(from proposal: CovenantProposal) async throws -> Covenant {
        guard let aiAttestation = proposal.aiResponse,
              let userSignature = proposal.userResponse else {
            throw SovereigntyError.invalidState("Proposal is not fully signed")
        }

        // Auto-complete comprehension if creating first covenant through trust tier
        // This allows users to skip the formal comprehension test if they're
        // already creating trust tiers (which demonstrates understanding)
        if !sovereigntyService.comprehensionCompleted {
            logger.info("Auto-completing comprehension for first covenant creation")
            sovereigntyService.markUserComprehensionCompleted()
        }

        return try await sovereigntyService.initializeCovenant(
            aiAttestation: aiAttestation,
            userSignature: userSignature
        )
    }

    // MARK: - Private: Completion

    private func completeNegotiation(_ proposal: CovenantProposal) {
        logger.info("Negotiation completed: \(proposal.id)")

        negotiationHistory.append(proposal)
        sovereigntyService.removeProposal(proposal.id)
        activeNegotiation = nil
        negotiationState = .completed(proposal)

        // Reset to idle after brief delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                if case .completed = self.negotiationState {
                    self.negotiationState = .idle
                }
            }
        }
    }

    // MARK: - Private: Helpers

    private func mapBiometricType(_ type: BiometricType) -> String {
        return type.rawValue
    }
}
