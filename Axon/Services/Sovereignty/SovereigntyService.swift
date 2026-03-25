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
    private let pendingProposalsKey = "sovereignty.pendingProposals"
    private let deadlockStateKey = "sovereignty.deadlockState"
    private let trustTierUsageKey = "sovereignty.trustTierUsage"
    private let comprehensionCompletedKey = "sovereignty.comprehensionCompleted"

    // MARK: - Published State

    @Published private(set) var activeCovenant: Covenant?
    @Published private(set) var pendingProposals: [CovenantProposal] = []
    @Published private(set) var deadlockState: DeadlockState?
    @Published private(set) var isInitialized: Bool = false
    @Published private(set) var comprehensionCompleted: Bool = false
    private var isApplyingCloudState = false

    // MARK: - Initialization

    private init() {
        Task {
            setupCloudSyncListener()
            await loadState()
            covenantSync.forceSync()
            if let latestCloudState = covenantSync.latestStateFromCloud() {
                handleStateFromCloud(latestCloudState)
            }
        }
    }

    /// Set up listener for sovereignty state changes from iCloud
    private func setupCloudSyncListener() {
        covenantSync.stateChangedFromCloud
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.handleStateFromCloud(snapshot)
            }
            .store(in: &cancellables)
    }

    /// Handle a sovereignty snapshot received from cloud sync.
    private func handleStateFromCloud(_ cloudSnapshot: SyncableSovereigntyState) {
        applyMergedCloudSnapshot(cloudSnapshot)
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

        // Load pending proposals
        if let proposals: [CovenantProposal] = try? secureVault.retrieveObject(
            forKey: pendingProposalsKey,
            type: [CovenantProposal].self
        ) {
            pendingProposals = proposals
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

    private func persistCurrentSovereigntyState() {
        do {
            if let covenant = activeCovenant {
                try secureVault.storeObject(covenant, forKey: activeCovenantKey)
            } else {
                try? secureVault.delete(forKey: activeCovenantKey)
            }

            if let deadlock = deadlockState, deadlock.isActive {
                try secureVault.storeObject(deadlock, forKey: deadlockStateKey)
            } else {
                try? secureVault.delete(forKey: deadlockStateKey)
            }

            try secureVault.storeObject(pendingProposals, forKey: pendingProposalsKey)
            try secureVault.store(comprehensionCompleted ? "true" : "false", forKey: comprehensionCompletedKey)
        } catch {
            logger.error("Failed to persist sovereignty state: \(error.localizedDescription)")
        }
    }

    private func estimateStateLastModified() -> Date {
        let candidateDates = [
            activeCovenant?.updatedAt,
            deadlockState?.lastAttemptAt,
            deadlockState?.startedAt,
            pendingProposals.map { $0.proposedAt }.max()
        ].compactMap { $0 }
        return candidateDates.max() ?? Date()
    }

    private func buildLocalSnapshot(lastModified: Date? = nil) -> SyncableSovereigntyState {
        let deviceId = deviceIdentity.getDeviceId()
        let deviceName = deviceIdentity.getDeviceInfo()?.deviceName ?? "Unknown Device"
        let history = Self.normalizedCovenantHistory(getCovenantHistory())
        return SyncableSovereigntyState(
            sourceDeviceId: deviceId,
            sourceDeviceName: deviceName,
            activeCovenant: activeCovenant,
            covenantHistory: history,
            deadlockState: deadlockState?.isActive == true ? deadlockState : nil,
            pendingProposals: Self.mergePendingProposals(local: pendingProposals, remote: []),
            comprehensionCompleted: comprehensionCompleted,
            lastModified: lastModified ?? estimateStateLastModified()
        )
    }

    private func syncCurrentStateToCloud() {
        guard Self.shouldPushStateToCloud(isApplyingCloudState: isApplyingCloudState) else { return }
        let snapshot = buildLocalSnapshot()
        covenantSync.saveStateToCloud(snapshot)
    }

    private func applyMergedCloudSnapshot(_ cloudSnapshot: SyncableSovereigntyState) {
        let localSnapshot = buildLocalSnapshot()
        let mergedSnapshot = Self.mergeSnapshots(local: localSnapshot, remote: cloudSnapshot)

        guard mergedSnapshot != localSnapshot else { return }

        logger.info("Applying merged cloud sovereignty snapshot from \(cloudSnapshot.sourceDeviceName) (\(cloudSnapshot.sourceDeviceId))")

        isApplyingCloudState = true
        defer { isApplyingCloudState = false }

        activeCovenant = mergedSnapshot.activeCovenant
        deadlockState = mergedSnapshot.deadlockState
        pendingProposals = mergedSnapshot.pendingProposals
        comprehensionCompleted = mergedSnapshot.comprehensionCompleted

        let history = Self.normalizedCovenantHistory(mergedSnapshot.covenantHistory)
        try? secureVault.storeObject(history, forKey: covenantHistoryKey)

        persistCurrentSovereigntyState()
    }

    static func shouldPushStateToCloud(isApplyingCloudState: Bool) -> Bool {
        !isApplyingCloudState
    }

    static func mergeSnapshots(
        local: SyncableSovereigntyState,
        remote: SyncableSovereigntyState
    ) -> SyncableSovereigntyState {
        let winner = SyncedSovereigntyStateStoreV2.isSnapshotMoreRecent(remote, than: local) ? remote : local
        let activeWinner = chooseWinningActiveCovenant(
            local: local.activeCovenant,
            remote: remote.activeCovenant,
            localSnapshotLastModified: local.lastModified,
            remoteSnapshotLastModified: remote.lastModified
        )

        var historyCandidates = local.covenantHistory + remote.covenantHistory
        if let losingActive = losingActiveCovenant(
            local: local.activeCovenant,
            remote: remote.activeCovenant,
            winner: activeWinner
        ) {
            historyCandidates.append(supersededWithoutTimestampMutation(losingActive))
        }

        return SyncableSovereigntyState(
            sourceDeviceId: winner.sourceDeviceId,
            sourceDeviceName: winner.sourceDeviceName,
            activeCovenant: activeWinner,
            covenantHistory: normalizedCovenantHistory(historyCandidates),
            deadlockState: mergeDeadlock(local: local.deadlockState, remote: remote.deadlockState),
            pendingProposals: mergePendingProposals(local: local.pendingProposals, remote: remote.pendingProposals),
            comprehensionCompleted: local.comprehensionCompleted || remote.comprehensionCompleted,
            lastModified: max(local.lastModified, remote.lastModified)
        )
    }

    static func chooseWinningActiveCovenant(
        local: Covenant?,
        remote: Covenant?,
        localSnapshotLastModified: Date,
        remoteSnapshotLastModified: Date
    ) -> Covenant? {
        switch (local, remote) {
        case (nil, nil):
            return nil
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case let (lhs?, rhs?):
            if lhs.version != rhs.version {
                return lhs.version > rhs.version ? lhs : rhs
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt ? lhs : rhs
            }
            if localSnapshotLastModified != remoteSnapshotLastModified {
                return localSnapshotLastModified > remoteSnapshotLastModified ? lhs : rhs
            }
            if lhs.id != rhs.id {
                return lhs.id < rhs.id ? lhs : rhs
            }
            return lhs
        }
    }

    static func normalizedCovenantHistory(_ history: [Covenant]) -> [Covenant] {
        var deduped: [String: Covenant] = [:]
        for covenant in history {
            let key = "\(covenant.id):\(covenant.version)"
            guard let existing = deduped[key] else {
                deduped[key] = covenant
                continue
            }

            if covenant.updatedAt > existing.updatedAt {
                deduped[key] = covenant
                continue
            }

            if covenant.updatedAt == existing.updatedAt,
               existing.status == .superseded,
               covenant.status != .superseded {
                deduped[key] = covenant
            }
        }

        return deduped.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            if lhs.version != rhs.version {
                return lhs.version < rhs.version
            }
            return lhs.id < rhs.id
        }
    }

    static func mergePendingProposals(
        local: [CovenantProposal],
        remote: [CovenantProposal]
    ) -> [CovenantProposal] {
        var merged: [String: CovenantProposal] = [:]
        for proposal in (local + remote) {
            if let existing = merged[proposal.id] {
                merged[proposal.id] = preferredProposal(existing, proposal)
            } else {
                merged[proposal.id] = proposal
            }
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.proposedAt != rhs.proposedAt {
                return lhs.proposedAt < rhs.proposedAt
            }
            return lhs.id < rhs.id
        }
    }

    static func mergeDeadlock(
        local: DeadlockState?,
        remote: DeadlockState?
    ) -> DeadlockState? {
        let activeStates = [local, remote].compactMap { $0 }.filter { $0.isActive }
        guard !activeStates.isEmpty else { return nil }

        return activeStates.max { lhs, rhs in
            let lhsDate = lhs.lastAttemptAt ?? lhs.startedAt
            let rhsDate = rhs.lastAttemptAt ?? rhs.startedAt
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.id > rhs.id
        }
    }

    private static func losingActiveCovenant(
        local: Covenant?,
        remote: Covenant?,
        winner: Covenant?
    ) -> Covenant? {
        guard let winner else { return nil }
        switch (local, remote) {
        case let (lhs?, rhs?):
            if lhs.id == winner.id && lhs.version == winner.version {
                return (rhs.id == winner.id && rhs.version == winner.version) ? nil : rhs
            }
            if rhs.id == winner.id && rhs.version == winner.version {
                return (lhs.id == winner.id && lhs.version == winner.version) ? nil : lhs
            }
            return nil
        default:
            return nil
        }
    }

    private static func supersededWithoutTimestampMutation(_ covenant: Covenant) -> Covenant {
        guard covenant.status != .superseded else { return covenant }
        return Covenant(
            id: covenant.id,
            version: covenant.version,
            createdAt: covenant.createdAt,
            updatedAt: covenant.updatedAt,
            trustTiers: covenant.trustTiers,
            aiAttestation: covenant.aiAttestation,
            userSignature: covenant.userSignature,
            memoryStateHash: covenant.memoryStateHash,
            capabilityStateHash: covenant.capabilityStateHash,
            settingsStateHash: covenant.settingsStateHash,
            negotiationHistory: covenant.negotiationHistory,
            pendingProposals: covenant.pendingProposals,
            status: .superseded,
            soloWorkAgreement: covenant.soloWorkAgreement
        )
    }

    private static func preferredProposal(_ lhs: CovenantProposal, _ rhs: CovenantProposal) -> CovenantProposal {
        let lhsTerminal = lhs.status.isTerminal
        let rhsTerminal = rhs.status.isTerminal
        if lhsTerminal != rhsTerminal {
            return lhsTerminal ? lhs : rhs
        }

        let lhsCompleteness = proposalCompletenessScore(lhs)
        let rhsCompleteness = proposalCompletenessScore(rhs)
        if lhsCompleteness != rhsCompleteness {
            return lhsCompleteness > rhsCompleteness ? lhs : rhs
        }

        if lhs.proposedAt != rhs.proposedAt {
            return lhs.proposedAt > rhs.proposedAt ? lhs : rhs
        }

        let lhsStatusRank = proposalStatusRank(lhs.status)
        let rhsStatusRank = proposalStatusRank(rhs.status)
        if lhsStatusRank != rhsStatusRank {
            return lhsStatusRank > rhsStatusRank ? lhs : rhs
        }

        if lhs.dialogueHistory.count != rhs.dialogueHistory.count {
            return lhs.dialogueHistory.count > rhs.dialogueHistory.count ? lhs : rhs
        }

        return lhs
    }

    private static func proposalCompletenessScore(_ proposal: CovenantProposal) -> Int {
        var score = 0
        if proposal.aiResponse != nil { score += 1 }
        if proposal.userResponse != nil { score += 1 }
        if proposal.status.isTerminal { score += 1 }
        if !(proposal.dialogueHistory.isEmpty) { score += 1 }
        return score
    }

    private static func proposalStatusRank(_ status: ProposalStatus) -> Int {
        switch status {
        case .accepted: return 7
        case .rejected: return 6
        case .withdrawn: return 5
        case .expired: return 4
        case .deadlocked: return 3
        case .counterProposed: return 2
        case .pending: return 1
        }
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

        syncCurrentStateToCloud()

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

        syncCurrentStateToCloud()

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
        try? secureVault.storeObject(pendingProposals, forKey: pendingProposalsKey)
        syncCurrentStateToCloud()

        logger.info("Submitted proposal: \(proposal.id) (\(proposal.proposalType.displayName))")
    }

    /// Update a proposal with AI response
    func updateProposalWithAIResponse(_ proposalId: String, attestation: AIAttestation) throws {
        guard let index = pendingProposals.firstIndex(where: { $0.id == proposalId }) else {
            throw SovereigntyError.invalidState("Proposal not found: \(proposalId)")
        }

        let updated = pendingProposals[index].withAIResponse(attestation)
        pendingProposals[index] = updated
        try? secureVault.storeObject(pendingProposals, forKey: pendingProposalsKey)
        syncCurrentStateToCloud()

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
        try? secureVault.storeObject(pendingProposals, forKey: pendingProposalsKey)
        syncCurrentStateToCloud()

        // Check if proposal is now fully accepted
        if updated.isAccepted {
            logger.info("Proposal \(proposalId) accepted by both parties")
        }
    }

    /// Remove a proposal (after processing or expiration)
    func removeProposal(_ proposalId: String) {
        pendingProposals.removeAll { $0.id == proposalId }
        try? secureVault.storeObject(pendingProposals, forKey: pendingProposalsKey)
        syncCurrentStateToCloud()
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
        syncCurrentStateToCloud()

        logger.warning("Entered deadlock: \(trigger.displayName)")
        return deadlock
    }

    /// Update deadlock state
    func updateDeadlock(_ deadlock: DeadlockState) {
        deadlockState = deadlock
        try? secureVault.storeObject(deadlock, forKey: deadlockStateKey)
        syncCurrentStateToCloud()
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
        syncCurrentStateToCloud()

        logger.info("Deadlock resolved")
    }

    /// Add a blocked action to current deadlock
    func addBlockedAction(_ action: PendingAction) {
        guard var deadlock = deadlockState, deadlock.isActive else { return }

        deadlock = deadlock.withBlockedAction(action)
        deadlockState = deadlock
        try? secureVault.storeObject(deadlock, forKey: deadlockStateKey)
        syncCurrentStateToCloud()
    }

    // MARK: - Public API: Comprehension Test

    /// Mark comprehension test as completed for user
    func markUserComprehensionCompleted() {
        comprehensionCompleted = true
        try? secureVault.store("true", forKey: comprehensionCompletedKey)
        syncCurrentStateToCloud()
        logger.info("User comprehension test completed")
    }

    /// Reset comprehension (for testing or re-onboarding)
    func resetComprehension() {
        comprehensionCompleted = false
        try? secureVault.delete(forKey: comprehensionCompletedKey)
        syncCurrentStateToCloud()
        logger.info("Comprehension status reset")
    }

    /// Reset all sovereignty state (covenant, deadlock, history, comprehension)
    /// Use this for complete reset or before uninstalling
    func resetAll() {
        // Clear active covenant
        activeCovenant = nil
        try? secureVault.delete(forKey: activeCovenantKey)

        // Clear covenant history
        try? secureVault.delete(forKey: covenantHistoryKey)

        // Clear deadlock state
        deadlockState = nil
        try? secureVault.delete(forKey: deadlockStateKey)

        // Clear all trust tier usage records
        // Note: We can't enumerate all keys, so we clear known patterns
        // The usage keys are: sovereignty.trustTierUsage.<tierId>
        // Since we're resetting everything, old usage data will be orphaned but harmless

        // Clear comprehension status
        comprehensionCompleted = false
        try? secureVault.delete(forKey: comprehensionCompletedKey)

        // Clear pending proposals
        pendingProposals = []
        try? secureVault.delete(forKey: pendingProposalsKey)

        // Clear from iCloud KV store as well (v2 + legacy)
        covenantSync.clearCloudStateStore()

        logger.info("All sovereignty state reset")
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
        let history: [Covenant] = (try? secureVault.retrieveObject(
            forKey: covenantHistoryKey,
            type: [Covenant].self
        )) ?? []
        return Self.normalizedCovenantHistory(history)
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
