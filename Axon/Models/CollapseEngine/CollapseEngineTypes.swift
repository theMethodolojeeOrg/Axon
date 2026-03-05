//
//  CollapseEngineTypes.swift
//  Axon
//
//  Core types for the Collapse Engine - a formal workflow for transforming
//  high-fidelity analogies into scoped, testable research artifacts.
//

import Foundation

// MARK: - Type Aliases

/// Unique session ID for a collapse workflow
typealias CollapseSessionId = String

// MARK: - Collapse Status

/// Status of a collapse engine workflow
enum CollapseStatus: String, Codable, CaseIterable, Equatable {
    case inProgress = "in_progress"
    case collapsed = "collapsed"       // Analogy proven structurally valid
    case analogyOnly = "analogy_only"  // Analogy heuristic only, not collapsed
    case aborted = "aborted"

    var displayName: String {
        switch self {
        case .inProgress: return "In Progress"
        case .collapsed: return "Collapsed"
        case .analogyOnly: return "Analogy Only"
        case .aborted: return "Aborted"
        }
    }

    var isTerminal: Bool {
        switch self {
        case .inProgress: return false
        case .collapsed, .analogyOnly, .aborted: return true
        }
    }
}

// MARK: - Collapse Phase

/// Phases of the collapse engine workflow
enum CollapsePhase: String, Codable, CaseIterable, Equatable {
    case captureAnalog = "capture_analog"
    case extractConstraints = "extract_constraints"
    case identityGate = "identity_gate"
    case divergenceBudget = "divergence_budget"
    case derivationCheck = "derivation_check"
    case gaugeSelection = "gauge_selection"
    case gaugeRelativity = "gauge_relativity"
    case collapseDecision = "collapse_decision"
    case paperPacket = "paper_packet"
    case complete = "complete"

    var displayName: String {
        switch self {
        case .captureAnalog: return "Capture Analog"
        case .extractConstraints: return "Extract Constraints"
        case .identityGate: return "Identity Gate"
        case .divergenceBudget: return "Divergence Budget"
        case .derivationCheck: return "Derivation Check"
        case .gaugeSelection: return "Gauge Selection"
        case .gaugeRelativity: return "Gauge Relativity"
        case .collapseDecision: return "Collapse Decision"
        case .paperPacket: return "Paper Packet"
        case .complete: return "Complete"
        }
    }

    var phaseNumber: Int {
        switch self {
        case .captureAnalog: return 1
        case .extractConstraints: return 2
        case .identityGate: return 3
        case .divergenceBudget: return 4
        case .derivationCheck: return 5
        case .gaugeSelection: return 6
        case .gaugeRelativity: return 7
        case .collapseDecision: return 8
        case .paperPacket: return 9
        case .complete: return 10
        }
    }

    var nextPhase: CollapsePhase? {
        switch self {
        case .captureAnalog: return .extractConstraints
        case .extractConstraints: return .identityGate
        case .identityGate: return .divergenceBudget
        case .divergenceBudget: return .derivationCheck
        case .derivationCheck: return .gaugeSelection
        case .gaugeSelection: return .gaugeRelativity
        case .gaugeRelativity: return .collapseDecision
        case .collapseDecision: return .paperPacket
        case .paperPacket: return .complete
        case .complete: return nil
        }
    }

    var previousPhase: CollapsePhase? {
        switch self {
        case .captureAnalog: return nil
        case .extractConstraints: return .captureAnalog
        case .identityGate: return .extractConstraints
        case .divergenceBudget: return .identityGate
        case .derivationCheck: return .divergenceBudget
        case .gaugeSelection: return .derivationCheck
        case .gaugeRelativity: return .gaugeSelection
        case .collapseDecision: return .gaugeRelativity
        case .paperPacket: return .collapseDecision
        case .complete: return .paperPacket
        }
    }
}

// MARK: - Identity Gate

/// Verdict from the identity gate comparing constraint sets
enum IdentityGateVerdict: String, Codable, Equatable {
    case identical = "IDENTICAL"   // Constraints are identical within scope → deductive transfer permitted
    case similar = "SIMILAR"       // Constraints are similar → heuristic transfer only
    case divergent = "DIVERGENT"   // Constraints diverge → revise scope or abandon collapse

    var displayName: String {
        switch self {
        case .identical: return "Identical"
        case .similar: return "Similar"
        case .divergent: return "Divergent"
        }
    }

    var permitsCollapse: Bool {
        self == .identical
    }
}

// MARK: - Divergence Classification

/// Classification for divergences between systems
enum DivergenceClassification: String, Codable, Equatable {
    case outOfScope = "OUT_OF_SCOPE"  // Irrelevant to the claimed structure S
    case patchable = "PATCHABLE"       // Can be resolved by refining scope or adding matched constraints
    case fatal = "FATAL"               // Breaks constraint identity, collapse disallowed

    var displayName: String {
        switch self {
        case .outOfScope: return "Out of Scope"
        case .patchable: return "Patchable"
        case .fatal: return "Fatal"
        }
    }

    var blocksCollapse: Bool {
        self == .fatal
    }
}

// MARK: - Derivation Status

/// Status of a derivation check
enum DerivationStatus: String, Codable, Equatable {
    case proven = "PROVEN"           // Entailment proven → collapse becomes a theorem
    case conjectured = "CONJECTURED" // Entailment unproven → collapse withheld or framed as conjecture

    var displayName: String {
        switch self {
        case .proven: return "Proven"
        case .conjectured: return "Conjectured"
        }
    }
}

// MARK: - System Label

/// Label for which system a constraint belongs to
enum SystemLabel: String, Codable, Equatable {
    case systemA = "A"
    case systemB = "B"

    var displayName: String {
        "System \(rawValue)"
    }
}

// MARK: - Constraint Category

/// Category of constraint for organization
enum ConstraintCategory: String, Codable, CaseIterable, Equatable {
    case axiom = "AXIOM"
    case boundary = "BOUNDARY"
    case rule = "RULE"
    case invariant = "INVARIANT"
    case mechanism = "MECHANISM"
    case structural = "STRUCTURAL"
    case behavioral = "BEHAVIORAL"
    case compositional = "COMPOSITIONAL"
    case symmetry = "SYMMETRY"

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Match Type

/// Type of match between constraints
enum MatchType: String, Codable, Equatable {
    case exact = "EXACT"           // Identical constraint statements
    case equivalent = "EQUIVALENT" // Logically equivalent but differently stated
    case analogous = "ANALOGOUS"   // Structurally similar but in different domains
    case partial = "PARTIAL"       // Partially overlapping

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Strata Entry Type

/// Type of entry in the strata ledger
enum StrataEntryType: String, Codable, Equatable {
    case creation = "CREATION"
    case modification = "MODIFICATION"
    case phaseTransition = "PHASE_TRANSITION"
    case checkpoint = "CHECKPOINT"
    case rollback = "ROLLBACK"

    var displayName: String {
        switch self {
        case .creation: return "Creation"
        case .modification: return "Modification"
        case .phaseTransition: return "Phase Transition"
        case .checkpoint: return "Checkpoint"
        case .rollback: return "Rollback"
        }
    }
}

// MARK: - Strata Actor

/// Actor that created a strata entry
enum StrataActor: String, Codable, Equatable {
    case user = "USER"
    case agent = "AGENT"
    case system = "SYSTEM"

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Paper Status

/// Status of a paper packet
enum PaperStatus: String, Codable, Equatable {
    case draft = "DRAFT"
    case review = "REVIEW"
    case finalized = "FINALIZED"

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Paper Section Type

/// Type of section in a paper packet
enum PaperSectionType: String, Codable, CaseIterable, Equatable {
    case introduction = "INTRODUCTION"
    case analogyDescription = "ANALOGY_DESCRIPTION"
    case constraintExtraction = "CONSTRAINT_EXTRACTION"
    case identityGateAnalysis = "IDENTITY_GATE_ANALYSIS"
    case divergenceBudget = "DIVERGENCE_BUDGET"
    case derivationProofs = "DERIVATION_PROOFS"
    case gaugeSelection = "GAUGE_SELECTION"
    case collapseStatement = "COLLAPSE_STATEMENT"
    case discussion = "DISCUSSION"
    case conclusion = "CONCLUSION"

    var displayName: String {
        switch self {
        case .introduction: return "Introduction"
        case .analogyDescription: return "Analogy Description"
        case .constraintExtraction: return "Constraint Extraction"
        case .identityGateAnalysis: return "Identity Gate Analysis"
        case .divergenceBudget: return "Divergence Budget"
        case .derivationProofs: return "Derivation Proofs"
        case .gaugeSelection: return "Gauge Selection"
        case .collapseStatement: return "Collapse Statement"
        case .discussion: return "Discussion"
        case .conclusion: return "Conclusion"
        }
    }

    var order: Int {
        switch self {
        case .introduction: return 1
        case .analogyDescription: return 2
        case .constraintExtraction: return 3
        case .identityGateAnalysis: return 4
        case .divergenceBudget: return 5
        case .derivationProofs: return 6
        case .gaugeSelection: return 7
        case .collapseStatement: return 8
        case .discussion: return 9
        case .conclusion: return 10
        }
    }
}

// MARK: - Export Format

/// Format for exporting paper packets
enum CollapseExportFormat: String, Codable, CaseIterable {
    case markdown = "markdown"
    case latex = "latex"
    case json = "json"

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .latex: return "tex"
        case .json: return "json"
        }
    }
}
