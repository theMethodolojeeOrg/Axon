//
//  SovereigntyService.swift
//  Axon
//
//  Central orchestrator for the co-sovereignty model.
//  Manages the active covenant, checks permissions, and coordinates
//  negotiation and deadlock flows.
//

import Foundation
import Combine
import os.log

// MARK: - Permission Result

/// Result of checking an action's permission against the covenant
enum PermissionResult: Equatable {
    case preApproved(TrustTier)           // Action is within a trust tier
    case requiresApproval                  // Action needs explicit approval
    case requiresAIConsent                 // Action needs AI to consent
    case blocked(BlockedReason)            // Action is blocked

    var isAllowed: Bool {
        switch self {
        case .preApproved:
            return true
        default:
            return false
        }
    }
}

enum BlockedReason: Equatable {
    case deadlocked(String)               // Deadlock ID
    case noCovenant                        // No covenant established
    case integrityViolation               // State integrity compromised
    case covenantSuspended                // Covenant suspended
}

// MARK: - Sovereignty Error

enum SovereigntyError: LocalizedError {
    case noActiveCovenant
    case covenantSuspended
    case deadlockActive(String)
    case aiDeclined(AttestationReasoning)
    case userDeclined
    case integrityViolation(String)
    case proposalExpired
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case .noActiveCovenant:
            return "No active covenant exists. Please establish a covenant first."
        case .covenantSuspended:
            return "The covenant is currently suspended due to a disagreement."
        case .deadlockActive(let id):
            return "A deadlock is active (ID: \(id)). Please resolve it before proceeding."
        case .aiDeclined(let reasoning):
            return "AI declined: \(reasoning.summary)"
        case .userDeclined:
            return "User declined the request."
        case .integrityViolation(let message):
            return "Integrity violation detected: \(message)"
        case .proposalExpired:
            return "The proposal has expired."
        case .invalidState(let message):
            return "Invalid state: \(message)"
        }
    }
}

// MARK: - Sovereignty Service

@MainActor
final class SovereigntyService: ObservableObject {
    static let shared = SovereigntyService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Axon", category: "Sovereignty")
    private let secureVault = SecureVault.shared
    private let deviceIdentity = DeviceIdentity.shared
    private let covenantSync = CovenantSyncService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Storage Keys

    private let activeCovenantKey = "sovereignty.activeCovenant"
    private let covenantHistoryKey = "sovereignty.covenantHistory"
    private let deadlockStateKey = "sovereignty.deadlockState"
    private let trustTierUsageKey = "sovereignty.trustTierUsage"
    private let comprehensionCompletedKey = "sovereignty.comprehensionCompleted"

    // MARK: - Published State

    @Published private(set) var activeCovenant: Covenant?
    @Published private(set) var pendingProposals: [CovenantProposal] = []
    @Published private(set) var deadlockState: DeadlockState?
    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var comprehensionCompleted: Bool = false

    // MARK: - Initialization

    private init() {
        Task {
            await loadState()
            setupCloudSyncListener()
        }
    }

    /// Set up listener for covenant changes from iCloud
    private func setupCloudSyncListener() {
        covenantSync.covenantChangedFromCloud
            .receive(on: DispatchQueue.main)
            .sink { [weak self] syncableCovenant in
                self?.handleCovenantFromCloud(syncableCovenant)
            }
            .store(in: &cancellables)
    }

    /// Handle a covenant received from iCloud sync
    private func handleCovenantFromCloud(_ syncable: SyncableCovenant) {
        // Only apply if this covenant is for the current device
        guard syncable.deviceId == deviceIdentity.deviceId else {
            logger.info("Received covenant from cloud for different device: \(syncable.deviceName)")
            return
        }

        // Check if this is newer than our current covenant
        if let current = activeCovenant {
            if syncable.covenant.version > current.version {
                logger.info("Applying newer covenant from cloud (v\(syncable.covenant.version) > v\(current.version))")
                do {
                    try secureVault.storeObject(syncable.covenant, forKey: activeCovenantKey)
                    activeCovenant = syncable.covenant
                } catch {
                    logger.error("Failed to apply covenant from cloud: \(error.localizedDescription)")
                }
            }
        } else {
            // No local covenant, apply the cloud one
            logger.info("Applying covenant from cloud (no local covenant)")
            do {
                try secureVault.storeObject(syncable.covenant, forKey: activeCovenantKey)
                activeCovenant = syncable.covenant
            } catch {
                logger.error("Failed to apply covenant from cloud: \(error.localizedDescription)")
            }
        }
    }

    /// Load persisted state from secure storage
    private func loadState() async {
        // Load active covenant
        if let covenant: Covenant = try? secureVault.retrieveObject(
            forKey: activeCovenantKey,
            type: Covenant.self
        ) {
            activeCovenant = covenant
            logger.info("Loaded active covenant (version \(covenant.version))")
        }

        // Load deadlock state
        if let deadlock: DeadlockState = try? secureVault.retrieveObject(
            forKey: deadlockStateKey,
            type: DeadlockState.self
        ) {
            if deadlock.isActive {
                deadlockState = deadlock
                logger.info("Loaded active deadlock state")
            }
        }

        // Load comprehension status
        if let completed = try? secureVault.retrieveString(forKey: comprehensionCompletedKey) {
            comprehensionCompleted = completed == "true"
        }

        isInitialized = true
    }

    // MARK: - Public API: Permission Checking

    /// Check if an action is permitted under the current covenant
    func checkActionPermission(_ action: SovereignAction, scope: ActionScope? = nil) -> PermissionResult {
        // Check for deadlock first
        if let deadlock = deadlockState, deadlock.isActive {
            return .blocked(.deadlocked(deadlock.id))
        }

        // Check for active covenant
        guard let covenant = activeCovenant else {
            return .blocked(.noCovenant)
        }

        // Check covenant status
        guard covenant.isActive else {
            if covenant.isDeadlocked {
                return .blocked(.covenantSuspended)
            }
            return .blocked(.covenantSuspended)
        }

        // Check if action affects AI identity (requires AI consent)
        if action.category.affectsAIIdentity {
            return .requiresAIConsent
        }

        // Check trust tiers for pre-approval
        for tier in covenant.activeTrustTiers {
            if tier.allows(action, scope: scope) {
                // Check rate limit
                if let rateLimit = tier.rateLimit {
                    if !checkRateLimit(tier: tier, limit: rateLimit) {
                        continue // Try next tier
                    }
                }

                recordTierUsage(tier: tier)
                return .preApproved(tier)
            }
        }

        // Action requires explicit approval
        return .requiresApproval
    }

    /// Check if a specific action category requires AI consent
    func requiresAIConsent(for category: ActionCategory) -> Bool {
        category.affectsAIIdentity
    }

    /// Check if a specific action category affects the world (requires user biometrics)
    func affectsWorld(for category: ActionCategory) -> Bool {
        category.affectsWorld
    }

    // MARK: - Public API: Covenant Management

    /// Initialize the first covenant (called after comprehension test)
    func initializeCovenant(
        aiAttestation: AIAttestation,
        userSignature: UserSignature
    ) async throws -> Covenant {
        guard comprehensionCompleted else {
            throw SovereigntyError.invalidState("Comprehension test not completed")
        }

        // Compute current state hashes
        let memoryHash = await computeMemoryStateHash()
        let capabilityHash = await computeCapabilityStateHash()
        let settingsHash = await computeSettingsStateHash()

        let covenant = Covenant.createInitial(
            aiAttestation: aiAttestation,
            userSignature: userSignature,
            memoryStateHash: memoryHash,
            capabilityStateHash: capabilityHash,
            settingsStateHash: settingsHash
        )

        // Store and activate
        try secureVault.storeObject(covenant, forKey: activeCovenantKey)
        activeCovenant = covenant

        // Sync to iCloud (device-scoped)
        covenantSync.saveCovenantToCloud(covenant)

        logger.info("Initialized covenant: \(covenant.id)")
        return covenant
    }

    /// Update the covenant with new state (after successful negotiation)
    func updateCovenant(_ covenant: Covenant) throws {
        guard covenant.isActive else {
            throw SovereigntyError.invalidState("Cannot update with inactive covenant")
        }

        // Archive previous covenant
        if let previous = activeCovenant {
            archiveCovenant(previous.superseded())
        }

        // Store new covenant
        try secureVault.storeObject(covenant, forKey: activeCovenantKey)
        activeCovenant = covenant

        // Sync to iCloud (device-scoped)
        covenantSync.saveCovenantToCloud(covenant)

        logger.info("Updated covenant to version \(covenant.version)")
    }

    /// Get the current covenant's state hashes
    func getCurrentStateHashes() async -> (memory: String, capability: String, settings: String) {
        let memoryHash = await computeMemoryStateHash()
        let capabilityHash = await computeCapabilityStateHash()
        let settingsHash = await computeSettingsStateHash()
        return (memoryHash, capabilityHash, settingsHash)
    }

    // MARK: - Public API: Proposals

    /// Submit a proposal for covenant changes
    func submitProposal(_ proposal: CovenantProposal) throws {
        // Allow proposals even without a covenant for initial covenant creation
        // The proposal type determines if this is valid
        if activeCovenant == nil {
            // Only allow certain proposal types without an existing covenant
            let allowedWithoutCovenant: [ProposalType] = [.initialCovenant, .addTrustTier]
            if !allowedWithoutCovenant.contains(proposal.proposalType) {
                throw SovereigntyError.noActiveCovenant
            }
            logger.info("Allowing proposal without covenant for initial setup: \(proposal.proposalType.displayName)")
        }

        if let deadlock = deadlockState, deadlock.isActive {
            throw SovereigntyError.deadlockActive(deadlock.id)
        }

        var proposals = pendingProposals
        proposals.append(proposal)
        pendingProposals = proposals

        logger.info("Submitted proposal: \(proposal.id) (\(proposal.proposalType.displayName))")
    }

    /// Update a proposal with AI response
    func updateProposalWithAIResponse(_ proposalId: String, attestation: AIAttestation) throws {
        guard let index = pendingProposals.firstIndex(where: { $0.id == proposalId }) else {
            throw SovereigntyError.invalidState("Proposal not found: \(proposalId)")
        }

        let updated = pendingProposals[index].withAIResponse(attestation)
        pendingProposals[index] = updated

        // Check if AI declined - may trigger deadlock
        if attestation.didDecline {
            logger.info("AI declined proposal \(proposalId)")
            // Deadlock handling will be triggered by negotiation service
        }
    }

    /// Update a proposal with user signature
    func updateProposalWithUserSignature(_ proposalId: String, signature: UserSignature) throws {
        guard let index = pendingProposals.firstIndex(where: { $0.id == proposalId }) else {
            throw SovereigntyError.invalidState("Proposal not found: \(proposalId)")
        }

        let updated = pendingProposals[index].withUserSignature(signature)
        pendingProposals[index] = updated

        // Check if proposal is now fully accepted
        if updated.isAccepted {
            logger.info("Proposal \(proposalId) accepted by both parties")
        }
    }

    /// Remove a proposal (after processing or expiration)
    func removeProposal(_ proposalId: String) {
        pendingProposals.removeAll { $0.id == proposalId }
    }

    // MARK: - Public API: Deadlock Management

    /// Enter deadlock state
    func enterDeadlock(
        trigger: DeadlockTrigger,
        proposal: CovenantProposal
    ) -> DeadlockState {
        guard let covenant = activeCovenant else {
            fatalError("Cannot enter deadlock without active covenant")
        }

        let deadlock = DeadlockState.create(
            trigger: trigger,
            originalProposal: proposal,
            covenantId: covenant.id
        )

        deadlockState = deadlock

        // Persist
        try? secureVault.storeObject(deadlock, forKey: deadlockStateKey)

        logger.warning("Entered deadlock: \(trigger.displayName)")
        return deadlock
    }

    /// Update deadlock state
    func updateDeadlock(_ deadlock: DeadlockState) {
        deadlockState = deadlock
        try? secureVault.storeObject(deadlock, forKey: deadlockStateKey)
    }

    /// Resolve deadlock (requires both signatures)
    func resolveDeadlock(
        aiAttestation: AIAttestation,
        userSignature: UserSignature
    ) throws {
        guard var deadlock = deadlockState, deadlock.isActive else {
            throw SovereigntyError.invalidState("No active deadlock to resolve")
        }

        guard aiAttestation.didConsent else {
            throw SovereigntyError.aiDeclined(aiAttestation.reasoning)
        }

        deadlock = deadlock.resolved()
        deadlockState = nil

        // Clear persisted deadlock
        try? secureVault.delete(forKey: deadlockStateKey)

        logger.info("Deadlock resolved")
    }

    /// Add a blocked action to current deadlock
    func addBlockedAction(_ action: PendingAction) {
        guard var deadlock = deadlockState, deadlock.isActive else { return }

        deadlock = deadlock.withBlockedAction(action)
        deadlockState = deadlock
        try? secureVault.storeObject(deadlock, forKey: deadlockStateKey)
    }

    // MARK: - Public API: Comprehension Test

    /// Mark comprehension test as completed for user
    func markUserComprehensionCompleted() {
        comprehensionCompleted = true
        try? secureVault.store("true", forKey: comprehensionCompletedKey)
        logger.info("User comprehension test completed")
    }

    /// Reset comprehension (for testing or re-onboarding)
    func resetComprehension() {
        comprehensionCompleted = false
        try? secureVault.delete(forKey: comprehensionCompletedKey)
        logger.info("Comprehension status reset")
    }

    // MARK: - State Hash Computation

    /// Compute hash of memory state
    func computeMemoryStateHash() async -> String {
        // In practice, this would hash all memory IDs + content hashes
        // For now, use a placeholder that will be implemented with MemoryService integration
        let timestamp = Date().timeIntervalSince1970
        return deviceIdentity.generateDeviceSignature(data: "memories:\(timestamp)")
    }

    /// Compute hash of capability state
    func computeCapabilityStateHash() async -> String {
        // In practice, this would hash enabled capability IDs
        // For now, use a placeholder
        let timestamp = Date().timeIntervalSince1970
        return deviceIdentity.generateDeviceSignature(data: "capabilities:\(timestamp)")
    }

    /// Compute hash of settings state
    func computeSettingsStateHash() async -> String {
        // In practice, this would hash AI-affecting settings
        let timestamp = Date().timeIntervalSince1970
        return deviceIdentity.generateDeviceSignature(data: "settings:\(timestamp)")
    }

    // MARK: - Rate Limiting

    private func checkRateLimit(tier: TrustTier, limit: RateLimit) -> Bool {
        let usage = loadTierUsage(tierId: tier.id)
        let windowStart = Date().addingTimeInterval(-Double(limit.windowSeconds))

        let recentUsage = usage.filter { $0 > windowStart }
        return recentUsage.count < limit.maxCalls
    }

    private func recordTierUsage(tier: TrustTier) {
        var usage = loadTierUsage(tierId: tier.id)
        usage.append(Date())

        // Keep only last 1000 entries
        if usage.count > 1000 {
            usage = Array(usage.suffix(1000))
        }

        saveTierUsage(tierId: tier.id, usage: usage)
    }

    private func loadTierUsage(tierId: String) -> [Date] {
        let key = "\(trustTierUsageKey).\(tierId)"
        return (try? secureVault.retrieveObject(forKey: key, type: [Date].self)) ?? []
    }

    private func saveTierUsage(tierId: String, usage: [Date]) {
        let key = "\(trustTierUsageKey).\(tierId)"
        try? secureVault.storeObject(usage, forKey: key)
    }

    // MARK: - Covenant History

    private func archiveCovenant(_ covenant: Covenant) {
        var history: [Covenant] = (try? secureVault.retrieveObject(
            forKey: covenantHistoryKey,
            type: [Covenant].self
        )) ?? []

        history.append(covenant)

        // Keep last 50 covenants
        if history.count > 50 {
            history = Array(history.suffix(50))
        }

        try? secureVault.storeObject(history, forKey: covenantHistoryKey)
    }

    /// Get covenant history
    func getCovenantHistory() -> [Covenant] {
        (try? secureVault.retrieveObject(
            forKey: covenantHistoryKey,
            type: [Covenant].self
        )) ?? []
    }

    // MARK: - Signature Generation

    /// Generate a signature for sovereignty-related data
    func generateSignature(data: String) -> String {
        deviceIdentity.generateDeviceSignature(data: data)
    }

    // MARK: - Provider/Model Change Restrictions

    /// Check if provider changes are allowed under the current covenant
    /// Returns true if allowed, false if restricted by covenant
    func isProviderChangeAllowed() -> Bool {
        // If no covenant exists, changes are allowed (no restrictions yet)
        guard let covenant = activeCovenant else {
            return true
        }

        // Check if there's a deadlock - if so, restrict changes
        if let deadlock = deadlockState, deadlock.isActive {
            return false
        }

        // Check if covenant is suspended
        guard covenant.isActive else {
            return false
        }

        // Check if there's a trust tier that explicitly allows provider switching
        let providerSwitchAction = SovereignAction.category(.providerSwitch)
        for tier in covenant.activeTrustTiers {
            if tier.allows(providerSwitchAction, scope: nil) {
                return true
            }
        }

        // Provider switching affects AI identity, so it requires negotiation if not pre-approved
        return false
    }

    /// Get the reason why provider changes are restricted
    func providerChangeRestrictionReason() -> String? {
        guard let covenant = activeCovenant else {
            return nil // No covenant = no restrictions
        }

        if let deadlock = deadlockState, deadlock.isActive {
            return "A deadlock is active. Resolve it before changing providers."
        }

        if !covenant.isActive {
            return "The covenant is suspended. Resolve the issue before changing providers."
        }

        // Check if provider switching is pre-approved
        let providerSwitchAction = SovereignAction.category(.providerSwitch)
        for tier in covenant.activeTrustTiers {
            if tier.allows(providerSwitchAction, scope: nil) {
                return nil // Allowed
            }
        }

        return "Provider changes require renegotiation. This affects Axon's identity."
    }

    /// Check if model changes are allowed (within the same provider)
    /// Model changes within a provider are generally less restrictive than provider changes
    func isModelChangeAllowed() -> Bool {
        // If no covenant exists, changes are allowed
        guard let covenant = activeCovenant else {
            return true
        }

        // Check for deadlock
        if let deadlock = deadlockState, deadlock.isActive {
            return false
        }

        // Check covenant status
        guard covenant.isActive else {
            return false
        }

        // Model changes within the same provider are typically allowed
        // unless there's a specific restriction
        return true
    }

    /// Get the reason why model changes are restricted
    func modelChangeRestrictionReason() -> String? {
        guard let covenant = activeCovenant else {
            return nil
        }

        if let deadlock = deadlockState, deadlock.isActive {
            return "A deadlock is active. Resolve it before changing models."
        }

        if !covenant.isActive {
            return "The covenant is suspended. Resolve the issue before changing models."
        }

        return nil
    }
}
