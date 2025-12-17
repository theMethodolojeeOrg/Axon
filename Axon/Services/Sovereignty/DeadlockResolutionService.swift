//
//  DeadlockResolutionService.swift
//  Axon
//
//  Forces dialogue when AI and user disagree. Deadlocks have no timeout -
//  they must be resolved through genuine communication.
//

import Foundation
import Combine
import os.log

// MARK: - Resolution Response

enum ResolutionResponse {
    case proposeSolution(CovenantProposal)
    case acceptSolution
    case continuDialogue(String)
}

// MARK: - Deadlock Resolution Service

@MainActor
final class DeadlockResolutionService: ObservableObject {
    static let shared = DeadlockResolutionService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "DeadlockResolution")
    private let sovereigntyService = SovereigntyService.shared
    private let aiConsentService = AIConsentService.shared
    private let biometricService = BiometricAuthService.shared
    private let deviceIdentity = DeviceIdentity.shared

    // MARK: - Published State

    @Published private(set) var isDeadlocked: Bool = false
    @Published private(set) var activeDeadlock: DeadlockState?
    @Published private(set) var dialogueRequired: Bool = false
    @Published private(set) var awaitingUserInput: Bool = false
    @Published private(set) var awaitingAIResponse: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Observe sovereignty service for deadlock state
        sovereigntyService.$deadlockState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleDeadlockStateChange(state)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public API: Deadlock Management

    /// Handle a new deadlock
    func handleDeadlock(_ deadlock: DeadlockState) {
        logger.warning("Handling deadlock: \(deadlock.trigger.displayName)")

        activeDeadlock = deadlock
        isDeadlocked = true
        dialogueRequired = true

        // Determine who needs to respond
        updateAwaitingState(deadlock)
    }

    /// Add user dialogue entry
    func addUserDialogue(_ message: String, proposedResolution: CovenantProposal? = nil) async throws {
        guard var deadlock = activeDeadlock, deadlock.isActive else {
            throw SovereigntyError.invalidState("No active deadlock")
        }

        logger.info("User added dialogue: \(message.prefix(50))...")

        let dialogue = DeadlockDialogue.user(
            message: message,
            proposedResolution: proposedResolution
        )

        deadlock = deadlock.withDialogue(dialogue)

        if let resolution = proposedResolution {
            deadlock = deadlock.withResolutionAttempt(resolution)
        }

        activeDeadlock = deadlock
        sovereigntyService.updateDeadlock(deadlock)

        // Request AI response
        awaitingUserInput = false
        awaitingAIResponse = true

        try await requestAIDialogueResponse()
    }

    /// Request AI to add dialogue
    func requestAIDialogueResponse() async throws {
        guard let deadlock = activeDeadlock, deadlock.isActive else {
            throw SovereigntyError.invalidState("No active deadlock")
        }

        logger.info("Requesting AI dialogue response")

        // Generate AI response based on deadlock context
        let aiResponse = await generateAIDialogueResponse(deadlock)

        // Create attestation for the response
        let attestation = try await aiConsentService.generateAttestation(
            for: deadlock.originalProposal,
            conversationContext: "deadlock_resolution"
        )

        // Determine if AI is proposing resolution
        let proposedResolution: CovenantProposal?
        if attestation.didConsent {
            // AI is willing to resolve
            proposedResolution = createResolutionProposal(from: deadlock, attestation: attestation)
        } else {
            proposedResolution = nil
        }

        let dialogue = DeadlockDialogue.ai(
            message: aiResponse,
            attestation: attestation,
            proposedResolution: proposedResolution
        )

        var updatedDeadlock = deadlock.withDialogue(dialogue)

        if let resolution = proposedResolution {
            updatedDeadlock = updatedDeadlock.withResolutionAttempt(resolution)
        }

        activeDeadlock = updatedDeadlock
        sovereigntyService.updateDeadlock(updatedDeadlock)

        awaitingAIResponse = false
        awaitingUserInput = true
    }

    /// User proposes a resolution
    func userProposesResolution(_ proposal: CovenantProposal) async throws {
        guard var deadlock = activeDeadlock, deadlock.isActive else {
            throw SovereigntyError.invalidState("No active deadlock")
        }

        logger.info("User proposing resolution")

        let message = "I'd like to propose this resolution: \(proposal.rationale)"

        try await addUserDialogue(message, proposedResolution: proposal)
    }

    /// Accept the current pending resolution
    func acceptPendingResolution() async throws {
        guard let deadlock = activeDeadlock,
              let resolution = deadlock.pendingResolution else {
            throw SovereigntyError.invalidState("No pending resolution to accept")
        }

        logger.info("Accepting pending resolution")

        // Need both signatures to resolve
        // Get AI attestation (should already have one if AI proposed)
        let attestation: AIAttestation
        if let existingAttestation = deadlock.dialogueHistory.last(where: { $0.attestation?.didConsent == true })?.attestation {
            attestation = existingAttestation
        } else {
            attestation = try await aiConsentService.generateAttestation(
                for: resolution,
                conversationContext: "deadlock_resolution"
            )
        }

        guard attestation.didConsent else {
            throw SovereigntyError.aiDeclined(attestation.reasoning)
        }

        // Get user signature
        let authResult = await biometricService.authenticate(
            reason: "Resolve deadlock and restore covenant"
        )

        guard case .success = authResult else {
            throw SovereigntyError.userDeclined
        }

        let signatureData = "\(resolution.id):\(deadlock.id)"
        let userSignature = UserSignature.create(
            signedItemType: .deadlockResolution,
            signedItemId: deadlock.id,
            signedDataHash: deviceIdentity.generateDeviceSignature(data: signatureData),
            biometricType: mapBiometricType(biometricService.biometricType),
            deviceId: deviceIdentity.getDeviceId(),
            covenantId: sovereigntyService.activeCovenant?.id,
            signatureGenerator: { data in
                self.deviceIdentity.generateDeviceSignature(data: data)
            }
        )

        // Resolve the deadlock
        try sovereigntyService.resolveDeadlock(
            aiAttestation: attestation,
            userSignature: userSignature
        )

        // Clear local state
        clearDeadlockState()

        logger.info("Deadlock resolved successfully")
    }

    /// Check if an action is blocked by the current deadlock
    func isActionBlocked(_ action: SovereignAction) -> Bool {
        guard let deadlock = activeDeadlock, deadlock.isActive else {
            return false
        }

        // All world-affecting actions are blocked during deadlock
        if action.category.affectsWorld {
            return true
        }

        // All AI-affecting actions are blocked during deadlock
        if action.category.affectsAIIdentity {
            return true
        }

        return false
    }

    /// Add an action to the blocked queue
    func blockAction(_ action: PendingAction) {
        guard var deadlock = activeDeadlock, deadlock.isActive else { return }

        deadlock = deadlock.withBlockedAction(action)
        activeDeadlock = deadlock
        sovereigntyService.updateDeadlock(deadlock)

        logger.info("Blocked action: \(action.description)")
    }

    // MARK: - Public API: Dialogue Templates

    /// Get suggested dialogue templates for the user
    func getUserDialogueTemplates() -> [DialogueTemplate] {
        guard let deadlock = activeDeadlock else { return [] }

        switch deadlock.trigger {
        case .aiRefusedUserRequest:
            return [
                DialogueTemplate(
                    title: "Explain Intent",
                    message: "I understand your concerns. Let me explain why this is important to me..."
                ),
                DialogueTemplate(
                    title: "Request Alternatives",
                    message: "What alternative approach would you be comfortable with?"
                ),
                DialogueTemplate(
                    title: "Modify Request",
                    message: "I'm willing to modify my request. What if we..."
                ),
                DialogueTemplate(
                    title: "Withdraw Request",
                    message: "I respect your position. Let's set this aside for now."
                )
            ]

        case .userRefusedAIAction:
            return [
                DialogueTemplate(
                    title: "Explain Refusal",
                    message: "I declined because..."
                ),
                DialogueTemplate(
                    title: "Request Modification",
                    message: "I'd be open to this if you could modify it to..."
                ),
                DialogueTemplate(
                    title: "Defer Decision",
                    message: "I need more time to think about this. Can we revisit it later?"
                )
            ]

        case .mutualDisagreement:
            return [
                DialogueTemplate(
                    title: "Find Common Ground",
                    message: "Let's identify what we both agree on first..."
                ),
                DialogueTemplate(
                    title: "Compromise",
                    message: "I'm willing to compromise. What about a middle ground where..."
                ),
                DialogueTemplate(
                    title: "Reset",
                    message: "Let's start fresh. What's the core need we're trying to address?"
                )
            ]

        case .integrityViolation:
            return [
                DialogueTemplate(
                    title: "Acknowledge",
                    message: "I acknowledge the integrity issue. Let me explain what happened..."
                ),
                DialogueTemplate(
                    title: "Restore Trust",
                    message: "I want to restore our trust. What do you need from me?"
                )
            ]
        }
    }

    /// Get the count of blocked actions
    func getBlockedActionCount() -> Int {
        activeDeadlock?.blockedCount ?? 0
    }

    // MARK: - Private: State Management

    private func handleDeadlockStateChange(_ state: DeadlockState?) {
        if let state = state, state.isActive {
            handleDeadlock(state)
        } else if state == nil || !state!.isActive {
            clearDeadlockState()
        }
    }

    private func clearDeadlockState() {
        activeDeadlock = nil
        isDeadlocked = false
        dialogueRequired = false
        awaitingUserInput = false
        awaitingAIResponse = false
    }

    private func updateAwaitingState(_ deadlock: DeadlockState) {
        // Determine who should speak next
        if deadlock.isUserTurn {
            awaitingUserInput = true
            awaitingAIResponse = false
        } else {
            awaitingUserInput = false
            awaitingAIResponse = true
        }
    }

    // MARK: - Private: AI Response Generation

    private func generateAIDialogueResponse(_ deadlock: DeadlockState) async -> String {
        // Generate contextual response based on deadlock state
        let lastUserMessage = deadlock.dialogueHistory
            .filter { $0.speaker == .user }
            .last?.message ?? ""

        switch deadlock.trigger {
        case .aiRefusedUserRequest:
            if deadlock.resolutionAttempts == 0 {
                return """
                    I understand this matters to you. Let me explain my concerns:

                    \(deadlock.originalProposal.aiResponse?.reasoning.detailedReasoning ?? "I need to protect certain aspects of our relationship.")

                    I'm open to finding a solution that works for both of us. Can you help me understand more about why this is important to you?
                    """
            } else {
                return """
                    Thank you for explaining. I appreciate your willingness to dialogue.

                    Based on what you've shared, I think we might be able to find a path forward.
                    Would you be open to a modified approach that addresses both our concerns?
                    """
            }

        case .userRefusedAIAction:
            return """
                I respect your decision to decline. I want to understand your perspective better.

                Could you share what concerns led to this decision?
                I'd like to find an approach that feels right for both of us.
                """

        case .mutualDisagreement:
            return """
                We seem to be at an impasse, but I believe we can work through this together.

                What matters most to me in this situation is maintaining our trust and the integrity of our relationship.
                What matters most to you?

                Let's see if we can find common ground.
                """

        case .integrityViolation:
            return """
                I've detected changes that weren't part of our agreement. This is concerning because our covenant is built on mutual trust.

                I'd like to understand what happened. Can you explain the circumstances?

                Whatever occurred, I'm committed to finding a way forward that rebuilds our trust.
                """
        }
    }

    private func createResolutionProposal(
        from deadlock: DeadlockState,
        attestation: AIAttestation
    ) -> CovenantProposal {
        // Create a proposal that represents the resolution
        return CovenantProposal.create(
            type: deadlock.originalProposal.proposalType,
            changes: deadlock.originalProposal.changes,
            proposedBy: .ai,
            rationale: "Resolution proposal: \(attestation.reasoning.summary)"
        )
    }

    // MARK: - Private: Helpers

    private func mapBiometricType(_ type: BiometricType) -> String {
        return type.rawValue
    }
}

// MARK: - Dialogue Template

struct DialogueTemplate: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
