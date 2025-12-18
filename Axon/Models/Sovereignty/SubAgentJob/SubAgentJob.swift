//
//  SubAgentJob.swift
//  Axon
//
//  The core job model for sub-agent orchestration.
//  Includes state machine, attestations, results, and timing.
//

import Foundation

// MARK: - Sub-Agent Job

/// A job assigned to a sub-agent by Axon.
/// Tracks the full lifecycle from proposal through completion/termination.
struct SubAgentJob: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let parentJobId: String?  // For tracking job chains (Designer → Scout recommendations)
    let role: SubAgentRole
    let task: String
    let contextInjectionTags: [String]  // e.g., ["#SuccessfulAgents", "#VSIX"]
    let permissions: SubAgentPermissions

    // MARK: - Model Selection

    /// Explicit provider override (nil = auto-select)
    let provider: AIProvider?

    /// Explicit model override (nil = auto-select based on tier)
    let model: String?

    /// Preferred model tier for auto-selection
    let modelTierPreference: ModelTier?

    // MARK: - State Machine

    var state: SubAgentJobState
    var stateHistory: [SubAgentJobStateTransition]

    // MARK: - Attestations (Axon's signatures)

    /// Axon's approval to run this job
    var approvalAttestation: JobAttestation?

    /// Axon's acceptance of the job result
    var completionAttestation: JobAttestation?

    /// Axon's termination order (if terminated early)
    var terminationAttestation: JobAttestation?

    // MARK: - Results

    var result: SubAgentJobResult?

    /// Reference to the output silo
    var siloId: String?

    // MARK: - Timing

    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?

    /// When this job should expire (Axon-controlled retention)
    var expiresAt: Date?

    // MARK: - Cost Tracking

    var tokenUsage: TokenUsage?
    var estimatedCostUSD: Double?

    /// Actual provider/model used (set after execution)
    var executedProvider: AIProvider?
    var executedModel: String?

    // MARK: - Computed Properties

    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }

    var isExpired: Bool {
        guard let expires = expiresAt else { return false }
        return Date() > expires
    }

    var hasQuestions: Bool {
        result?.clarificationQuestions?.isEmpty == false
    }

    var isTerminal: Bool {
        state.isTerminal
    }

    // MARK: - Initialization

    init(
        id: String = UUID().uuidString,
        parentJobId: String? = nil,
        role: SubAgentRole,
        task: String,
        contextInjectionTags: [String] = [],
        permissions: SubAgentPermissions? = nil,
        provider: AIProvider? = nil,
        model: String? = nil,
        modelTierPreference: ModelTier? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.parentJobId = parentJobId
        self.role = role
        self.task = task
        self.contextInjectionTags = contextInjectionTags
        self.permissions = permissions ?? role.defaultPermissions
        self.provider = provider
        self.model = model
        self.modelTierPreference = modelTierPreference ?? role.recommendedModelTiers.first
        self.state = .proposed
        self.stateHistory = []
        self.createdAt = Date()
        self.expiresAt = expiresAt
    }
}

// MARK: - Sub-Agent Job State

/// State machine for sub-agent job lifecycle.
enum SubAgentJobState: String, Codable, CaseIterable, Sendable {
    case proposed       // Job created, awaiting Axon's approval attestation
    case approved       // Axon approved, ready to execute
    case running        // Currently executing
    case awaitingInput  // Sub-agent has questions, needs clarification from Axon
    case completed      // Successfully finished
    case failed         // Failed with error
    case terminated     // Manually terminated by Axon
    case expired        // Timed out
    case rejected       // Axon rejected the proposal

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .terminated, .expired, .rejected:
            return true
        case .proposed, .approved, .running, .awaitingInput:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .proposed: return "Proposed"
        case .approved: return "Approved"
        case .running: return "Running"
        case .awaitingInput: return "Awaiting Input"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .terminated: return "Terminated"
        case .expired: return "Expired"
        case .rejected: return "Rejected"
        }
    }

    var icon: String {
        switch self {
        case .proposed: return "doc.badge.clock"
        case .approved: return "checkmark.seal"
        case .running: return "play.circle"
        case .awaitingInput: return "questionmark.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .terminated: return "stop.circle.fill"
        case .expired: return "clock.badge.xmark"
        case .rejected: return "xmark.seal"
        }
    }

    /// Valid transitions from this state
    var validTransitions: Set<SubAgentJobState> {
        switch self {
        case .proposed:
            return [.approved, .rejected, .expired]
        case .approved:
            return [.running, .terminated, .expired]
        case .running:
            return [.completed, .awaitingInput, .failed, .terminated, .expired]
        case .awaitingInput:
            return [.approved, .terminated, .expired]  // approved = re-run after clarification
        case .completed, .failed, .terminated, .expired, .rejected:
            return []  // Terminal states
        }
    }
}

// MARK: - State Transition

/// Records a state transition with timestamp, reason, and optional attestation.
struct SubAgentJobStateTransition: Codable, Equatable, Sendable {
    let from: SubAgentJobState
    let to: SubAgentJobState
    let timestamp: Date
    let reason: String?
    let attestationId: String?

    init(
        from: SubAgentJobState,
        to: SubAgentJobState,
        reason: String? = nil,
        attestationId: String? = nil
    ) {
        self.from = from
        self.to = to
        self.timestamp = Date()
        self.reason = reason
        self.attestationId = attestationId
    }
}

// MARK: - Job Result

/// The output from a sub-agent's execution.
struct SubAgentJobResult: Codable, Equatable, Sendable {
    let summary: String
    let fullResponse: String

    /// Questions the sub-agent needs answered before continuing
    let clarificationQuestions: [String]?

    /// IDs of any artifacts produced (files, code blocks, etc.)
    let artifactsProduced: [String]?

    /// IDs of silo entries created
    let siloEntriesCreated: [String]?

    /// Tools that were invoked during execution
    let toolsUsed: [String]?

    /// Whether the task completed successfully
    let success: Bool

    /// Error message if failed
    let errorMessage: String?

    /// Spawn recommendations from Designer agents (no-nesting enforcement)
    let spawnRecommendations: [SpawnRecommendation]?

    init(
        summary: String,
        fullResponse: String,
        clarificationQuestions: [String]? = nil,
        artifactsProduced: [String]? = nil,
        siloEntriesCreated: [String]? = nil,
        toolsUsed: [String]? = nil,
        success: Bool,
        errorMessage: String? = nil,
        spawnRecommendations: [SpawnRecommendation]? = nil
    ) {
        self.summary = summary
        self.fullResponse = fullResponse
        self.clarificationQuestions = clarificationQuestions
        self.artifactsProduced = artifactsProduced
        self.siloEntriesCreated = siloEntriesCreated
        self.toolsUsed = toolsUsed
        self.success = success
        self.errorMessage = errorMessage
        self.spawnRecommendations = spawnRecommendations
    }
}

// MARK: - Spawn Recommendation

/// A Designer's recommendation to spawn another agent.
/// Enforces the no-nesting rule: agents cannot spawn directly, only recommend.
struct SpawnRecommendation: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let role: SubAgentRole
    let task: String
    let contextTags: [String]
    let rationale: String
    let priority: Priority

    enum Priority: String, Codable, Sendable {
        case low
        case medium
        case high
        case critical
    }

    init(
        role: SubAgentRole,
        task: String,
        contextTags: [String] = [],
        rationale: String,
        priority: Priority = .medium
    ) {
        self.id = UUID().uuidString
        self.role = role
        self.task = task
        self.contextTags = contextTags
        self.rationale = rationale
        self.priority = priority
    }
}

// MARK: - Token Usage

/// Token consumption for cost tracking.
struct TokenUsage: Codable, Equatable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int

    var totalTokens: Int {
        inputTokens + outputTokens
    }
}

// MARK: - Job Mutators

extension SubAgentJob {
    /// Create a copy with updated state and recorded transition
    func transitioning(
        to newState: SubAgentJobState,
        reason: String? = nil,
        attestationId: String? = nil
    ) -> SubAgentJob {
        var copy = self
        let transition = SubAgentJobStateTransition(
            from: copy.state,
            to: newState,
            reason: reason,
            attestationId: attestationId
        )
        copy.stateHistory.append(transition)
        copy.state = newState
        return copy
    }

    /// Create a copy with approval attestation
    func withApproval(_ attestation: JobAttestation) -> SubAgentJob {
        var copy = self
        copy.approvalAttestation = attestation
        return copy
    }

    /// Create a copy with completion attestation
    func withCompletion(_ attestation: JobAttestation) -> SubAgentJob {
        var copy = self
        copy.completionAttestation = attestation
        return copy
    }

    /// Create a copy with termination attestation
    func withTermination(_ attestation: JobAttestation) -> SubAgentJob {
        var copy = self
        copy.terminationAttestation = attestation
        return copy
    }

    /// Create a copy with result
    func withResult(_ result: SubAgentJobResult) -> SubAgentJob {
        var copy = self
        copy.result = result
        return copy
    }

    /// Create a copy with silo reference
    func withSilo(_ siloId: String) -> SubAgentJob {
        var copy = self
        copy.siloId = siloId
        return copy
    }

    /// Create a copy with execution metadata
    func withExecutionMetadata(
        provider: AIProvider,
        model: String,
        tokenUsage: TokenUsage,
        costUSD: Double
    ) -> SubAgentJob {
        var copy = self
        copy.executedProvider = provider
        copy.executedModel = model
        copy.tokenUsage = tokenUsage
        copy.estimatedCostUSD = costUSD
        return copy
    }

    /// Create a copy with start time
    func started() -> SubAgentJob {
        var copy = self
        copy.startedAt = Date()
        return copy
    }

    /// Create a copy with completion time
    func finished() -> SubAgentJob {
        var copy = self
        copy.completedAt = Date()
        return copy
    }
}
