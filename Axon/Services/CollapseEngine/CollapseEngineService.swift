//
//  CollapseEngineService.swift
//  Axon
//
//  Service managing Collapse Engine workflow state, persistence, and orchestration.
//  Implements hybrid storage: MemoryService for searchable content + JSON files for full artifacts.
//

import Foundation
import Combine
import os.log

// MARK: - Collapse Engine Service

/// Service for managing Collapse Engine workflows.
///
/// The Collapse Engine transforms high-fidelity analogies into scoped, testable research artifacts
/// through a formal 10-phase workflow.
@MainActor
final class CollapseEngineService: ObservableObject {

    // MARK: - Singleton

    static let shared = CollapseEngineService()

    // MARK: - Dependencies

    private let fileManager = FileManager.default
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "CollapseEngineService"
    )

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Published State

    @Published private(set) var sessions: [CollapseSession] = []
    @Published private(set) var currentSessionId: CollapseSessionId?
    @Published private(set) var isProcessing: Bool = false
    @Published var error: String?

    // MARK: - Storage Paths

    private var collapseEngineDirectory: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("AxonTools/collapse_engine")
    }

    private var sessionsDirectory: URL {
        collapseEngineDirectory.appendingPathComponent("sessions")
    }

    private var artifactsDirectory: URL {
        collapseEngineDirectory.appendingPathComponent("artifacts")
    }

    private var ledgerDirectory: URL {
        collapseEngineDirectory.appendingPathComponent("ledger")
    }

    private var paperPacketsDirectory: URL {
        collapseEngineDirectory.appendingPathComponent("paper_packets")
    }

    // MARK: - Initialization

    private init() {
        setupDirectories()
        loadSessions()
    }

    // MARK: - Directory Setup

    private func setupDirectories() {
        let directories = [
            sessionsDirectory,
            artifactsDirectory.appendingPathComponent("analog_cards"),
            artifactsDirectory.appendingPathComponent("constraint_sets"),
            artifactsDirectory.appendingPathComponent("identity_gates"),
            artifactsDirectory.appendingPathComponent("divergence_budgets"),
            artifactsDirectory.appendingPathComponent("derivation_records"),
            artifactsDirectory.appendingPathComponent("gauge_anchors"),
            artifactsDirectory.appendingPathComponent("gauge_relativity_notes"),
            artifactsDirectory.appendingPathComponent("collapse_statements"),
            ledgerDirectory,
            paperPacketsDirectory
        ]

        for directory in directories {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create directory \(directory.path): \(error.localizedDescription)")
            }
        }

        logger.info("Collapse Engine directories initialized at \(self.collapseEngineDirectory.path)")
    }

    // MARK: - Session Management

    /// Load all sessions from disk
    func loadSessions() {
        do {
            let files = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }

            sessions = jsonFiles.compactMap { url -> CollapseSession? in
                do {
                    let data = try Data(contentsOf: url)
                    return try jsonDecoder.decode(CollapseSession.self, from: data)
                } catch {
                    logger.error("Failed to load session from \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }.sorted { $0.updatedAt > $1.updatedAt }

            logger.info("Loaded \(self.sessions.count) collapse sessions")
        } catch {
            logger.error("Failed to enumerate sessions: \(error.localizedDescription)")
            sessions = []
        }
    }

    /// Create a new collapse session
    func createSession(
        name: String,
        description: String?,
        tags: [String],
        useSubAgents: Bool = false
    ) async throws -> CollapseSession {
        let session = CollapseSession.create(
            name: name,
            description: description,
            tags: tags,
            useSubAgents: useSubAgents
        )

        try saveSession(session)

        // Create ledger for this session
        let ledger = StrataLedger(sessionId: session.id)
        try saveLedger(ledger)

        // Record creation in ledger
        try recordLedgerEntry(
            sessionId: session.id,
            entryType: .creation,
            artifactId: session.id,
            artifactType: "CollapseSession",
            version: 1,
            changeDescription: "Session created: \(name)"
        )

        sessions.insert(session, at: 0)
        currentSessionId = session.id

        logger.info("Created collapse session: \(session.id)")
        return session
    }

    /// Get a session by ID
    func getSession(_ id: CollapseSessionId) -> CollapseSession? {
        sessions.first { $0.id == id }
    }

    /// Update and save a session
    func updateSession(_ session: CollapseSession) throws {
        var updated = session
        updated.updatedAt = Date()

        try saveSession(updated)

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = updated
        }

        logger.info("Updated session: \(session.id)")
    }

    /// Delete a session and all its artifacts
    func deleteSession(_ id: CollapseSessionId) async throws {
        // Remove session file
        let sessionFile = sessionsDirectory.appendingPathComponent("\(id).json")
        try? fileManager.removeItem(at: sessionFile)

        // Remove ledger
        let ledgerFile = ledgerDirectory.appendingPathComponent("\(id)_ledger.json")
        try? fileManager.removeItem(at: ledgerFile)

        // Note: We don't delete artifacts as they might be useful for research history
        // They can be cleaned up manually or through a separate garbage collection process

        sessions.removeAll { $0.id == id }
        if currentSessionId == id {
            currentSessionId = sessions.first?.id
        }

        logger.info("Deleted session: \(id)")
    }

    /// Set the current active session
    func setCurrentSession(_ id: CollapseSessionId?) {
        currentSessionId = id
    }

    // MARK: - Phase 1: Capture Analog Card

    /// Capture an initial analogy hypothesis
    func captureAnalogCard(
        sessionId: CollapseSessionId,
        systemA: SystemDescription,
        systemB: SystemDescription,
        analogyHypothesis: String,
        generativePotential: String,
        initialConfidence: Double,
        predictedTransfer: String? = nil,
        scaryMismatch: String? = nil,
        scopeHint: String? = nil,
        sketchMapping: [MappingElement]? = nil,
        tags: [String] = []
    ) async throws -> AnalogCard {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        let card = AnalogCard(
            sessionId: sessionId,
            systemA: systemA,
            systemB: systemB,
            analogyHypothesis: analogyHypothesis,
            generativePotential: generativePotential,
            initialConfidence: initialConfidence,
            predictedTransfer: predictedTransfer,
            scaryMismatch: scaryMismatch,
            scopeHint: scopeHint,
            sketchMapping: sketchMapping,
            tags: tags
        )

        try saveArtifact(card, type: "analog_cards", id: card.id)

        session.analogCardId = card.id
        if session.currentPhase == .captureAnalog {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .creation,
            artifactId: card.id,
            artifactType: "AnalogCard",
            version: 1,
            changeDescription: "Captured analog: \(systemA.name) ↔ \(systemB.name)"
        )

        logger.info("Captured analog card for session \(sessionId)")
        return card
    }

    /// Load an analog card by ID
    func getAnalogCard(_ id: String) throws -> AnalogCard {
        try loadArtifact(type: "analog_cards", id: id)
    }

    // MARK: - Phase 2: Extract Constraints

    /// Extract constraints for a system
    func extractConstraints(
        sessionId: CollapseSessionId,
        system: SystemLabel,
        constraints: [Constraint],
        method: ExtractionMethod = .manual,
        notes: String? = nil
    ) async throws -> ConstraintSet {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        let constraintSet = ConstraintSet(
            sessionId: sessionId,
            system: system,
            constraints: constraints,
            extractionMethod: method,
            extractionNotes: notes
        )

        try saveArtifact(constraintSet, type: "constraint_sets", id: constraintSet.id)

        session.constraintSetIds.append(constraintSet.id)
        if session.currentPhase == .extractConstraints && session.constraintSetIds.count >= 2 {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .creation,
            artifactId: constraintSet.id,
            artifactType: "ConstraintSet",
            version: 1,
            changeDescription: "Extracted \(constraints.count) constraints for System \(system.rawValue)"
        )

        logger.info("Extracted \(constraints.count) constraints for system \(system.rawValue)")
        return constraintSet
    }

    /// Load a constraint set by ID
    func getConstraintSet(_ id: String) throws -> ConstraintSet {
        try loadArtifact(type: "constraint_sets", id: id)
    }

    // MARK: - Phase 3: Identity Gate

    /// Run the identity gate to compare constraint sets
    func runIdentityGate(
        sessionId: CollapseSessionId,
        scope: String,
        matchedPairs: [ConstraintPair],
        unmatchedA: [String],
        unmatchedB: [String],
        notes: String? = nil
    ) async throws -> IdentityGateResult {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        guard session.constraintSetIds.count >= 2 else {
            throw CollapseEngineError.missingArtifacts(["Need at least 2 constraint sets"])
        }

        // Determine verdict based on matches
        let totalConstraints = matchedPairs.count * 2 + unmatchedA.count + unmatchedB.count
        let matchRatio = totalConstraints > 0 ? Double(matchedPairs.count * 2) / Double(totalConstraints) : 0

        let verdict: IdentityGateVerdict
        if unmatchedA.isEmpty && unmatchedB.isEmpty && matchedPairs.allSatisfy({ $0.matchType == .exact || $0.matchType == .equivalent }) {
            verdict = .identical
        } else if matchRatio > 0.7 {
            verdict = .similar
        } else {
            verdict = .divergent
        }

        let result = IdentityGateResult(
            sessionId: sessionId,
            constraintSetAId: session.constraintSetIds[0],
            constraintSetBId: session.constraintSetIds[1],
            verdict: verdict,
            matchedPairs: matchedPairs,
            unmatchedA: unmatchedA,
            unmatchedB: unmatchedB,
            similarityScore: matchRatio,
            scope: scope,
            notes: notes
        )

        try saveArtifact(result, type: "identity_gates", id: result.id)

        session.identityGateResultId = result.id
        if session.currentPhase == .identityGate {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .phaseTransition,
            artifactId: result.id,
            artifactType: "IdentityGateResult",
            version: 1,
            changeDescription: "Identity gate verdict: \(verdict.displayName)"
        )

        logger.info("Identity gate completed: \(verdict.displayName)")
        return result
    }

    /// Load an identity gate result by ID
    func getIdentityGateResult(_ id: String) throws -> IdentityGateResult {
        try loadArtifact(type: "identity_gates", id: id)
    }

    // MARK: - Phase 4: Divergence Budget

    /// Record a divergence
    func recordDivergence(
        sessionId: CollapseSessionId,
        description: String,
        classification: DivergenceClassification,
        affectedConstraints: [String] = [],
        impactedClaims: [String]? = nil,
        patchStrategy: String? = nil,
        rationale: String
    ) async throws -> Divergence {
        guard getSession(sessionId) != nil else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        let divergence = Divergence(
            sessionId: sessionId,
            description: description,
            classification: classification,
            affectedConstraints: affectedConstraints,
            impactedClaims: impactedClaims,
            patchStrategy: patchStrategy,
            rationale: rationale
        )

        // Store divergence as part of the budget (will be compiled later)
        try saveArtifact(divergence, type: "divergence_budgets", id: "divergence_\(divergence.id)")

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .creation,
            artifactId: divergence.id,
            artifactType: "Divergence",
            version: 1,
            changeDescription: "Recorded \(classification.displayName) divergence"
        )

        logger.info("Recorded divergence: \(classification.displayName)")
        return divergence
    }

    /// Compile the divergence budget for a session
    func compileDivergenceBudget(
        sessionId: CollapseSessionId,
        divergences: [Divergence],
        scope: String,
        notes: String? = nil
    ) async throws -> DivergenceBudget {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        let budget = DivergenceBudget(
            sessionId: sessionId,
            divergences: divergences,
            scope: scope,
            notes: notes
        )

        try saveArtifact(budget, type: "divergence_budgets", id: budget.id)

        session.divergenceBudgetId = budget.id
        if session.currentPhase == .divergenceBudget {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .phaseTransition,
            artifactId: budget.id,
            artifactType: "DivergenceBudget",
            version: 1,
            changeDescription: "Compiled budget: \(budget.fatalCount) fatal, \(budget.patchableCount) patchable, \(budget.outOfScopeCount) out of scope"
        )

        logger.info("Compiled divergence budget: \(budget.totalCount) total, \(budget.fatalCount) fatal")
        return budget
    }

    /// Load a divergence budget by ID
    func getDivergenceBudget(_ id: String) throws -> DivergenceBudget {
        try loadArtifact(type: "divergence_budgets", id: id)
    }

    // MARK: - Phase 5: Derivation Check

    /// Check a derivation for a structure claim
    func checkDerivation(
        sessionId: CollapseSessionId,
        claim: StructureClaim,
        status: DerivationStatus,
        derivationSteps: [DerivationStep]? = nil,
        proofSketch: String? = nil,
        missingLemma: String? = nil,
        requiredEvidence: [String]? = nil,
        verificationMethod: String,
        counterexamples: [String]? = nil,
        notes: String? = nil
    ) async throws -> DerivationRecord {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        let record = DerivationRecord(
            sessionId: sessionId,
            claim: claim,
            status: status,
            derivationSteps: derivationSteps,
            proofSketch: proofSketch,
            missingLemma: missingLemma,
            requiredEvidence: requiredEvidence,
            verificationMethod: verificationMethod,
            counterexamples: counterexamples,
            notes: notes
        )

        try saveArtifact(record, type: "derivation_records", id: record.id)

        session.derivationRecordIds.append(record.id)
        if session.currentPhase == .derivationCheck {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .creation,
            artifactId: record.id,
            artifactType: "DerivationRecord",
            version: 1,
            changeDescription: "Derivation \(status.displayName): \(claim.statement.prefix(50))..."
        )

        logger.info("Checked derivation: \(status.displayName)")
        return record
    }

    /// Load a derivation record by ID
    func getDerivationRecord(_ id: String) throws -> DerivationRecord {
        try loadArtifact(type: "derivation_records", id: id)
    }

    // MARK: - Phase 6: Gauge Selection

    /// Select a gauge anchor
    func selectGaugeAnchor(
        sessionId: CollapseSessionId,
        name: String,
        description: String,
        quotientSymmetries: [String],
        invariantsMadeLegible: [String]? = nil,
        operatorsStabilized: [String]? = nil,
        representationalBasis: String,
        selectionRationale: String,
        risks: [String]? = nil
    ) async throws -> GaugeAnchor {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        let anchor = GaugeAnchor(
            sessionId: sessionId,
            name: name,
            description: description,
            quotientSymmetries: quotientSymmetries,
            invariantsMadeLegible: invariantsMadeLegible,
            operatorsStabilized: operatorsStabilized,
            representationalBasis: representationalBasis,
            selectionRationale: selectionRationale,
            risks: risks
        )

        try saveArtifact(anchor, type: "gauge_anchors", id: anchor.id)

        session.gaugeAnchorIds.append(anchor.id)
        if session.currentPhase == .gaugeSelection {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .creation,
            artifactId: anchor.id,
            artifactType: "GaugeAnchor",
            version: 1,
            changeDescription: "Selected gauge: \(name)"
        )

        logger.info("Selected gauge anchor: \(name)")
        return anchor
    }

    /// Load a gauge anchor by ID
    func getGaugeAnchor(_ id: String) throws -> GaugeAnchor {
        try loadArtifact(type: "gauge_anchors", id: id)
    }

    // MARK: - Phase 7: Gauge Relativity

    /// Record a gauge relativity note
    func recordGaugeRelativityNote(
        sessionId: CollapseSessionId,
        claimId: String,
        gaugeId: String,
        scope: String,
        permitsReGauging: Bool = true,
        reGaugingConstraints: [String]? = nil,
        allowableReGauges: [String]? = nil,
        transformHints: [String]? = nil,
        scopeDependencies: [String]? = nil,
        notes: String? = nil
    ) async throws -> GaugeRelativityNote {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        let note = GaugeRelativityNote(
            sessionId: sessionId,
            claimId: claimId,
            gaugeId: gaugeId,
            scope: scope,
            permitsReGauging: permitsReGauging,
            reGaugingConstraints: reGaugingConstraints,
            allowableReGauges: allowableReGauges,
            transformHints: transformHints,
            scopeDependencies: scopeDependencies,
            notes: notes
        )

        try saveArtifact(note, type: "gauge_relativity_notes", id: note.id)

        session.gaugeRelativityNoteIds.append(note.id)
        if session.currentPhase == .gaugeRelativity {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .creation,
            artifactId: note.id,
            artifactType: "GaugeRelativityNote",
            version: 1,
            changeDescription: "Indexed claim to gauge: \(note.claimIndexing)"
        )

        logger.info("Recorded gauge relativity note")
        return note
    }

    /// Load a gauge relativity note by ID
    func getGaugeRelativityNote(_ id: String) throws -> GaugeRelativityNote {
        try loadArtifact(type: "gauge_relativity_notes", id: id)
    }

    // MARK: - Phase 8: Collapse Statement

    /// Generate the final collapse statement
    func generateCollapseStatement(
        sessionId: CollapseSessionId,
        summary: String,
        structureS: String,
        constraintsUsed: [String],
        structurePreserved: [String],
        structureLost: [String],
        confidenceScore: Double,
        scope: String,
        justification: String,
        recommendations: [String]? = nil
    ) async throws -> CollapseStatement {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        // Determine verdict based on divergence budget and identity gate
        var verdict: CollapseStatus = .analogyOnly

        if let budgetId = session.divergenceBudgetId,
           let budget = try? getDivergenceBudget(budgetId),
           budget.canProceed,
           let gateId = session.identityGateResultId,
           let gate = try? getIdentityGateResult(gateId),
           gate.canProceedToCollapse {
            verdict = .collapsed
        }

        let statement = CollapseStatement(
            sessionId: sessionId,
            verdict: verdict,
            summary: summary,
            structureS: structureS,
            constraintsUsed: constraintsUsed,
            structurePreserved: structurePreserved,
            structureLost: structureLost,
            confidenceScore: confidenceScore,
            gaugeUsed: session.gaugeAnchorIds.first,
            scope: scope,
            justification: justification,
            recommendations: recommendations
        )

        try saveArtifact(statement, type: "collapse_statements", id: statement.id)

        session.collapseStatementId = statement.id
        session.status = verdict
        if session.currentPhase == .collapseDecision {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .phaseTransition,
            artifactId: statement.id,
            artifactType: "CollapseStatement",
            version: 1,
            changeDescription: "Collapse verdict: \(verdict.displayName)"
        )

        logger.info("Generated collapse statement: \(verdict.displayName)")
        return statement
    }

    /// Load a collapse statement by ID
    func getCollapseStatement(_ id: String) throws -> CollapseStatement {
        try loadArtifact(type: "collapse_statements", id: id)
    }

    // MARK: - Phase 9: Paper Packet

    /// Generate a paper packet from the session
    func generatePaperPacket(
        sessionId: CollapseSessionId,
        title: String,
        abstract: String,
        predictions: [String],
        failureModes: [String]
    ) async throws -> PaperPacket {
        guard var session = getSession(sessionId) else {
            throw CollapseEngineError.sessionNotFound(sessionId)
        }

        // Build sections from session artifacts
        var sections: [PaperSection] = []

        // Introduction
        if let cardId = session.analogCardId, let card = try? getAnalogCard(cardId) {
            sections.append(PaperSection(
                title: "Introduction",
                content: """
                This paper examines the structural analogy between \(card.systemA.name) and \(card.systemB.name).

                **Hypothesis:** \(card.analogyHypothesis)

                **Generative Potential:** \(card.generativePotential)
                """,
                sectionType: .introduction
            ))

            sections.append(PaperSection(
                title: "Analogy Description",
                content: """
                **System A: \(card.systemA.name)**
                Domain: \(card.systemA.domain)
                \(card.systemA.description)

                **System B: \(card.systemB.name)**
                Domain: \(card.systemB.domain)
                \(card.systemB.description)
                """,
                sectionType: .analogyDescription
            ))
        }

        // Constraint Extraction
        if session.constraintSetIds.count >= 2 {
            var constraintContent = ""
            for setId in session.constraintSetIds {
                if let set = try? getConstraintSet(setId) {
                    constraintContent += "**System \(set.system.rawValue) Constraints (\(set.count))**\n\n"
                    for constraint in set.constraints.prefix(10) {
                        constraintContent += "- [\(constraint.category.displayName)] \(constraint.content)\n"
                    }
                    if set.count > 10 {
                        constraintContent += "- ... and \(set.count - 10) more\n"
                    }
                    constraintContent += "\n"
                }
            }
            sections.append(PaperSection(
                title: "Constraint Extraction",
                content: constraintContent,
                sectionType: .constraintExtraction
            ))
        }

        // Identity Gate
        if let gateId = session.identityGateResultId, let gate = try? getIdentityGateResult(gateId) {
            sections.append(PaperSection(
                title: "Identity Gate Analysis",
                content: """
                **Verdict:** \(gate.verdict.displayName)
                **Similarity Score:** \(String(format: "%.1f%%", gate.similarityScore * 100))
                **Matched Pairs:** \(gate.matchedCount)
                **Unmatched:** \(gate.unmatchedCount)
                **Scope:** \(gate.scope)
                """,
                sectionType: .identityGateAnalysis
            ))
        }

        // Collapse Statement
        if let statementId = session.collapseStatementId, let statement = try? getCollapseStatement(statementId) {
            sections.append(PaperSection(
                title: "Collapse Statement",
                content: """
                **Verdict:** \(statement.verdict.displayName)
                \(statement.formalStatement)

                **Summary:** \(statement.summary)

                **Confidence:** \(String(format: "%.1f%%", statement.confidenceScore * 100))

                **Justification:** \(statement.justification)
                """,
                sectionType: .collapseStatement
            ))
        }

        // Conclusion
        sections.append(PaperSection(
            title: "Conclusion",
            content: abstract,
            sectionType: .conclusion
        ))

        let packet = PaperPacket(
            sessionId: sessionId,
            title: title,
            abstract: abstract,
            sections: sections,
            predictions: predictions,
            failureModes: failureModes
        )

        // Save packet
        let packetDir = paperPacketsDirectory.appendingPathComponent(packet.id)
        try fileManager.createDirectory(at: packetDir, withIntermediateDirectories: true)
        let packetFile = packetDir.appendingPathComponent("packet.json")
        let data = try jsonEncoder.encode(packet)
        try data.write(to: packetFile)

        // Also save markdown export
        let mdFile = packetDir.appendingPathComponent("\(packet.id).md")
        try packet.toMarkdown().write(to: mdFile, atomically: true, encoding: .utf8)

        session.paperPacketId = packet.id
        if session.currentPhase == .paperPacket {
            _ = session.advancePhase()
        }
        try updateSession(session)

        try recordLedgerEntry(
            sessionId: sessionId,
            entryType: .phaseTransition,
            artifactId: packet.id,
            artifactType: "PaperPacket",
            version: 1,
            changeDescription: "Generated paper packet: \(title)"
        )

        logger.info("Generated paper packet: \(title)")
        return packet
    }

    /// Load a paper packet by ID
    func getPaperPacket(_ id: String) throws -> PaperPacket {
        let packetFile = paperPacketsDirectory.appendingPathComponent(id).appendingPathComponent("packet.json")
        let data = try Data(contentsOf: packetFile)
        return try jsonDecoder.decode(PaperPacket.self, from: data)
    }

    // MARK: - Phase 10: Strata Ledger

    /// Record an entry in the strata ledger
    @discardableResult
    func recordLedgerEntry(
        sessionId: CollapseSessionId,
        entryType: StrataEntryType,
        artifactId: String,
        artifactType: String,
        version: Int,
        changeDescription: String,
        previousVersionId: String? = nil,
        createdBy: StrataActor = .system
    ) throws -> StrataLedgerEntry {
        var ledger = try loadLedger(sessionId: sessionId)

        let entry = StrataLedgerEntry(
            sessionId: sessionId,
            entryType: entryType,
            artifactId: artifactId,
            artifactType: artifactType,
            version: version,
            changeDescription: changeDescription,
            previousVersionId: previousVersionId,
            createdBy: createdBy
        )

        ledger.addEntry(entry)
        try saveLedger(ledger)

        return entry
    }

    /// Get the ledger for a session
    func getLedger(sessionId: CollapseSessionId) throws -> StrataLedger {
        try loadLedger(sessionId: sessionId)
    }

    /// Query ledger entries
    func queryLedger(
        sessionId: CollapseSessionId,
        artifactId: String? = nil,
        entryType: StrataEntryType? = nil,
        limit: Int? = nil
    ) throws -> [StrataLedgerEntry] {
        let ledger = try loadLedger(sessionId: sessionId)

        var entries = ledger.entries

        if let artifactId = artifactId {
            entries = entries.filter { $0.artifactId == artifactId }
        }

        if let entryType = entryType {
            entries = entries.filter { $0.entryType == entryType }
        }

        if let limit = limit {
            entries = Array(entries.suffix(limit))
        }

        return entries
    }

    // MARK: - Private Helpers

    private func saveSession(_ session: CollapseSession) throws {
        let file = sessionsDirectory.appendingPathComponent("\(session.id).json")
        let data = try jsonEncoder.encode(session)
        try data.write(to: file)
    }

    private func saveArtifact<T: Codable>(_ artifact: T, type: String, id: String) throws {
        let dir = artifactsDirectory.appendingPathComponent(type)
        let file = dir.appendingPathComponent("\(id).json")
        let data = try jsonEncoder.encode(artifact)
        try data.write(to: file)
    }

    private func loadArtifact<T: Codable>(type: String, id: String) throws -> T {
        let file = artifactsDirectory.appendingPathComponent(type).appendingPathComponent("\(id).json")
        let data = try Data(contentsOf: file)
        return try jsonDecoder.decode(T.self, from: data)
    }

    private func saveLedger(_ ledger: StrataLedger) throws {
        let file = ledgerDirectory.appendingPathComponent("\(ledger.sessionId)_ledger.json")
        let data = try jsonEncoder.encode(ledger)
        try data.write(to: file)
    }

    private func loadLedger(sessionId: CollapseSessionId) throws -> StrataLedger {
        let file = ledgerDirectory.appendingPathComponent("\(sessionId)_ledger.json")
        if fileManager.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            return try jsonDecoder.decode(StrataLedger.self, from: data)
        } else {
            return StrataLedger(sessionId: sessionId)
        }
    }
}

// MARK: - Errors

enum CollapseEngineError: Error, LocalizedError {
    case sessionNotFound(CollapseSessionId)
    case missingArtifacts([String])
    case invalidPhaseTransition(from: CollapsePhase, to: CollapsePhase)
    case artifactNotFound(type: String, id: String)
    case persistenceError(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "Collapse session not found: \(id)"
        case .missingArtifacts(let artifacts):
            return "Missing required artifacts: \(artifacts.joined(separator: ", "))"
        case .invalidPhaseTransition(let from, let to):
            return "Invalid phase transition from \(from.displayName) to \(to.displayName)"
        case .artifactNotFound(let type, let id):
            return "Artifact not found: \(type)/\(id)"
        case .persistenceError(let message):
            return "Persistence error: \(message)"
        }
    }
}
