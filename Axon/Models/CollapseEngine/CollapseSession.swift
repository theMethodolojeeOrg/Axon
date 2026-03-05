//
//  CollapseSession.swift
//  Axon
//
//  Root model tying together a full collapse workflow.
//

import Foundation

// MARK: - Collapse Session

/// Root model for a Collapse Engine workflow session.
///
/// A session tracks the complete journey from initial analogy capture
/// through constraint extraction, identity gate, divergence budget,
/// derivation check, gauge selection, collapse decision, and paper packet.
struct CollapseSession: Codable, Identifiable, Equatable {
    /// Unique identifier for this session
    let id: CollapseSessionId

    /// Human-readable name for this session
    var name: String

    /// Description of what this session is exploring
    var description: String?

    /// Current status of the workflow
    var status: CollapseStatus

    /// Current phase in the workflow
    var currentPhase: CollapsePhase

    // MARK: - Artifact References

    /// ID of the analog card (Phase 1)
    var analogCardId: String?

    /// IDs of constraint sets (Phase 2) - typically one for A, one for B
    var constraintSetIds: [String]

    /// ID of the identity gate result (Phase 3)
    var identityGateResultId: String?

    /// ID of the divergence budget (Phase 4)
    var divergenceBudgetId: String?

    /// IDs of derivation records (Phase 5)
    var derivationRecordIds: [String]

    /// IDs of gauge anchors (Phase 6)
    var gaugeAnchorIds: [String]

    /// IDs of gauge relativity notes (Phase 7)
    var gaugeRelativityNoteIds: [String]

    /// ID of the collapse statement (Phase 8)
    var collapseStatementId: String?

    /// ID of the paper packet (Phase 9)
    var paperPacketId: String?

    // MARK: - Metadata

    /// Tags for organization and retrieval
    var tags: [String]

    /// When this session was created
    let createdAt: Date

    /// When this session was last updated
    var updatedAt: Date

    /// Whether to use sub-agents for this session
    var useSubAgents: Bool

    /// Additional metadata
    var metadata: [String: String]?

    init(
        id: CollapseSessionId = UUID().uuidString,
        name: String,
        description: String? = nil,
        status: CollapseStatus = .inProgress,
        currentPhase: CollapsePhase = .captureAnalog,
        analogCardId: String? = nil,
        constraintSetIds: [String] = [],
        identityGateResultId: String? = nil,
        divergenceBudgetId: String? = nil,
        derivationRecordIds: [String] = [],
        gaugeAnchorIds: [String] = [],
        gaugeRelativityNoteIds: [String] = [],
        collapseStatementId: String? = nil,
        paperPacketId: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        useSubAgents: Bool = false,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.currentPhase = currentPhase
        self.analogCardId = analogCardId
        self.constraintSetIds = constraintSetIds
        self.identityGateResultId = identityGateResultId
        self.divergenceBudgetId = divergenceBudgetId
        self.derivationRecordIds = derivationRecordIds
        self.gaugeAnchorIds = gaugeAnchorIds
        self.gaugeRelativityNoteIds = gaugeRelativityNoteIds
        self.collapseStatementId = collapseStatementId
        self.paperPacketId = paperPacketId
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.useSubAgents = useSubAgents
        self.metadata = metadata
    }

    // MARK: - Phase Management

    /// Whether the session is complete
    var isComplete: Bool {
        status.isTerminal || currentPhase == .complete
    }

    /// Whether the session can advance to the next phase
    var canAdvancePhase: Bool {
        !isComplete && currentPhase.nextPhase != nil
    }

    /// Advance to the next phase
    mutating func advancePhase() -> Bool {
        guard let next = currentPhase.nextPhase else { return false }
        currentPhase = next
        updatedAt = Date()
        return true
    }

    /// Check if a specific phase has been completed
    func hasCompletedPhase(_ phase: CollapsePhase) -> Bool {
        currentPhase.phaseNumber > phase.phaseNumber
    }

    /// Get the completion percentage (0.0-1.0)
    var completionPercentage: Double {
        Double(currentPhase.phaseNumber) / Double(CollapsePhase.complete.phaseNumber)
    }

    // MARK: - Validation

    /// Check if the session has the required artifacts for the current phase
    var hasRequiredArtifacts: Bool {
        switch currentPhase {
        case .captureAnalog:
            return true // No prerequisites
        case .extractConstraints:
            return analogCardId != nil
        case .identityGate:
            return constraintSetIds.count >= 2
        case .divergenceBudget:
            return identityGateResultId != nil
        case .derivationCheck:
            return divergenceBudgetId != nil
        case .gaugeSelection:
            return !derivationRecordIds.isEmpty
        case .gaugeRelativity:
            return !gaugeAnchorIds.isEmpty
        case .collapseDecision:
            return !gaugeRelativityNoteIds.isEmpty
        case .paperPacket:
            return collapseStatementId != nil
        case .complete:
            return paperPacketId != nil
        }
    }

    /// Get missing artifacts for the current phase
    var missingArtifacts: [String] {
        var missing: [String] = []
        switch currentPhase {
        case .extractConstraints:
            if analogCardId == nil { missing.append("Analog Card") }
        case .identityGate:
            if constraintSetIds.count < 2 { missing.append("Constraint Sets (need 2)") }
        case .divergenceBudget:
            if identityGateResultId == nil { missing.append("Identity Gate Result") }
        case .derivationCheck:
            if divergenceBudgetId == nil { missing.append("Divergence Budget") }
        case .gaugeSelection:
            if derivationRecordIds.isEmpty { missing.append("Derivation Records") }
        case .gaugeRelativity:
            if gaugeAnchorIds.isEmpty { missing.append("Gauge Anchors") }
        case .collapseDecision:
            if gaugeRelativityNoteIds.isEmpty { missing.append("Gauge Relativity Notes") }
        case .paperPacket:
            if collapseStatementId == nil { missing.append("Collapse Statement") }
        case .complete:
            if paperPacketId == nil { missing.append("Paper Packet") }
        default:
            break
        }
        return missing
    }

    // MARK: - Summaries

    /// Short summary for display
    var shortSummary: String {
        "\(name) - \(currentPhase.displayName) (\(status.displayName))"
    }

    /// Generate a comprehensive summary for memory storage
    var summary: String {
        """
        Collapse Session: \(name)
        Status: \(status.displayName)
        Phase: \(currentPhase.displayName) (\(String(format: "%.0f%%", completionPercentage * 100)) complete)

        Artifacts:
        - Analog Card: \(analogCardId != nil ? "✓" : "—")
        - Constraint Sets: \(constraintSetIds.count)
        - Identity Gate: \(identityGateResultId != nil ? "✓" : "—")
        - Divergence Budget: \(divergenceBudgetId != nil ? "✓" : "—")
        - Derivation Records: \(derivationRecordIds.count)
        - Gauge Anchors: \(gaugeAnchorIds.count)
        - Gauge Relativity Notes: \(gaugeRelativityNoteIds.count)
        - Collapse Statement: \(collapseStatementId != nil ? "✓" : "—")
        - Paper Packet: \(paperPacketId != nil ? "✓" : "—")

        Tags: \(tags.isEmpty ? "none" : tags.joined(separator: ", "))
        """
    }
}

// MARK: - Session Creation Helpers

extension CollapseSession {
    /// Create a new session with minimal required fields
    static func create(
        name: String,
        description: String? = nil,
        tags: [String] = [],
        useSubAgents: Bool = false
    ) -> CollapseSession {
        CollapseSession(
            name: name,
            description: description,
            tags: tags,
            useSubAgents: useSubAgents
        )
    }
}
