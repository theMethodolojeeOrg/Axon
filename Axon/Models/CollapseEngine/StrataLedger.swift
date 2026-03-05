//
//  StrataLedger.swift
//  Axon
//
//  Phase 10 artifact: Versioned research memory.
//

import Foundation

// MARK: - Strata Ledger Entry

/// Entry in the versioning ledger.
///
/// From the protocol:
/// All artifacts and packets are logged as strata. Revisions preserve provenance,
/// enabling cumulative progress and principled resurrection of earlier frames
/// under new constraints.
///
/// Key points:
/// - Every revision is a new stratum, not a silent overwrite.
/// - Contradictions are handled by scope revision or re-gauging, not by erasure.
/// - The ledger is the empirical record of what collapses survived which tests.
///
/// Formally: L = {Π_t}^T_{t=1}, Π_{t+1} = Revise(Π_t; ΔC, ΔS, Δg, ΔD)
struct StrataLedgerEntry: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier for this entry
    let id: String

    /// Session this entry belongs to
    let sessionId: CollapseSessionId

    /// Type of entry
    let entryType: StrataEntryType

    /// ID of the artifact being versioned
    let artifactId: String

    /// Type name of the artifact (e.g., "AnalogCard", "ConstraintSet")
    let artifactType: String

    /// Version number of this artifact
    let version: Int

    /// Description of the change
    let changeDescription: String

    /// ID of the previous version (if any)
    let previousVersionId: String?

    /// Hash for integrity verification
    let snapshotHash: String?

    /// Delta from previous version (JSON-encoded changes)
    let delta: String?

    /// When this entry was created
    let createdAt: Date

    /// Who/what created this entry
    let createdBy: StrataActor

    /// Additional metadata
    let metadata: [String: String]?

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        entryType: StrataEntryType,
        artifactId: String,
        artifactType: String,
        version: Int,
        changeDescription: String,
        previousVersionId: String? = nil,
        snapshotHash: String? = nil,
        delta: String? = nil,
        createdAt: Date = Date(),
        createdBy: StrataActor = .system,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.entryType = entryType
        self.artifactId = artifactId
        self.artifactType = artifactType
        self.version = version
        self.changeDescription = changeDescription
        self.previousVersionId = previousVersionId
        self.snapshotHash = snapshotHash
        self.delta = delta
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.metadata = metadata
    }

    /// Generate a compact log line
    var logLine: String {
        let timestamp = ISO8601DateFormatter().string(from: createdAt)
        return "[\(timestamp)] \(entryType.displayName): \(artifactType)#\(artifactId.prefix(8)) v\(version) - \(changeDescription)"
    }
}

// MARK: - Strata Ledger

/// Complete ledger for a session.
///
/// This is the empirical record of what changes were made, when, and by whom.
/// It enables:
/// - Auditing the research process
/// - Rolling back to previous versions
/// - Understanding the evolution of the collapse
struct StrataLedger: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: String

    /// Session this ledger belongs to
    let sessionId: CollapseSessionId

    /// All entries in chronological order
    var entries: [StrataLedgerEntry]

    /// When this ledger was created
    let createdAt: Date

    /// When this ledger was last updated
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        entries: [StrataLedgerEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.entries = entries.sorted { $0.createdAt < $1.createdAt }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Add an entry to the ledger
    mutating func addEntry(_ entry: StrataLedgerEntry) {
        entries.append(entry)
        entries.sort { $0.createdAt < $1.createdAt }
        updatedAt = Date()
    }

    /// Get entries for a specific artifact
    func entries(forArtifact artifactId: String) -> [StrataLedgerEntry] {
        entries.filter { $0.artifactId == artifactId }
    }

    /// Get entries of a specific type
    func entries(ofType entryType: StrataEntryType) -> [StrataLedgerEntry] {
        entries.filter { $0.entryType == entryType }
    }

    /// Get the latest version number for an artifact
    func latestVersion(forArtifact artifactId: String) -> Int {
        entries(forArtifact: artifactId).map { $0.version }.max() ?? 0
    }

    /// Get all phase transitions
    var phaseTransitions: [StrataLedgerEntry] {
        entries(ofType: .phaseTransition)
    }

    /// Get entry count
    var count: Int { entries.count }

    /// Generate a summary for memory storage
    var summary: String {
        let typeGroups = Dictionary(grouping: entries, by: { $0.entryType })
        let typeCounts = typeGroups.map { "\($0.key.displayName): \($0.value.count)" }.joined(separator: ", ")

        return """
        Strata Ledger for session \(sessionId.prefix(8))
        Total entries: \(count)
        Breakdown: \(typeCounts)
        """
    }
}
