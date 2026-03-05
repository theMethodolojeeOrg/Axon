//
//  CollapseEngineHandler.swift
//  Axon
//
//  V2 Handler for Collapse Engine tools - transforms analogies into research artifacts.
//

import Foundation
import os.log

/// Handler for all Collapse Engine V2 tools.
///
/// Routes tools:
/// - run_collapse_engine (orchestrator)
/// - create_collapse_session, query_collapse_session, list_collapse_sessions
/// - capture_analog_card
/// - extract_constraints
/// - check_identity_gate
/// - record_divergence, compile_divergence_budget
/// - check_derivation
/// - select_gauge_anchor
/// - record_gauge_relativity
/// - generate_collapse_statement
/// - generate_paper_packet
/// - query_strata_ledger
@MainActor
final class CollapseEngineHandler: ToolHandlerV2 {

    let handlerId = "collapse_engine"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "CollapseEngineHandler"
    )

    private let service = CollapseEngineService.shared

    // MARK: - ToolHandlerV2

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        switch toolId {
        // Orchestrator
        case "run_collapse_engine":
            return try await executeRunCollapseEngine(inputs: inputs)

        // Session Management
        case "create_collapse_session":
            return try await executeCreateSession(inputs: inputs)
        case "query_collapse_session":
            return try await executeQuerySession(inputs: inputs)
        case "list_collapse_sessions":
            return try await executeListSessions(inputs: inputs)

        // Phase 1: Capture Analog
        case "capture_analog_card":
            return try await executeCaptureAnalogCard(inputs: inputs)

        // Phase 2: Extract Constraints
        case "extract_constraints":
            return try await executeExtractConstraints(inputs: inputs)

        // Phase 3: Identity Gate
        case "check_identity_gate":
            return try await executeCheckIdentityGate(inputs: inputs)

        // Phase 4: Divergence Budget
        case "record_divergence":
            return try await executeRecordDivergence(inputs: inputs)
        case "compile_divergence_budget":
            return try await executeCompileDivergenceBudget(inputs: inputs)

        // Phase 5: Derivation Check
        case "check_derivation":
            return try await executeCheckDerivation(inputs: inputs)

        // Phase 6: Gauge Selection
        case "select_gauge_anchor":
            return try await executeSelectGaugeAnchor(inputs: inputs)

        // Phase 7: Gauge Relativity
        case "record_gauge_relativity":
            return try await executeRecordGaugeRelativity(inputs: inputs)

        // Phase 8: Collapse Statement
        case "generate_collapse_statement":
            return try await executeGenerateCollapseStatement(inputs: inputs)

        // Phase 9: Paper Packet
        case "generate_paper_packet":
            return try await executeGeneratePaperPacket(inputs: inputs)

        // Phase 10: Strata Ledger
        case "query_strata_ledger":
            return try await executeQueryStrataLedger(inputs: inputs)

        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown collapse engine tool: \(toolId)")
        }
    }

    // MARK: - Orchestrator

    private func executeRunCollapseEngine(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "run_collapse_engine",
                error: "Missing required parameter: session_id"
            )
        }

        guard let session = service.getSession(sessionId) else {
            return ToolResultV2.failure(
                toolId: "run_collapse_engine",
                error: "Session not found: \(sessionId)"
            )
        }

        let phases = parsed["phases"] as? [String]
        let useSubAgents = parsed["use_sub_agents"] as? Bool ?? session.useSubAgents

        logger.info("Running collapse engine for session \(sessionId), phases: \(phases ?? ["all"])")

        // Return current status and guidance for next steps
        var output = "# Collapse Engine Status\n\n"
        output += "**Session:** \(session.name)\n"
        output += "**Status:** \(session.status.displayName)\n"
        output += "**Current Phase:** \(session.currentPhase.displayName)\n"
        output += "**Progress:** \(String(format: "%.0f%%", session.completionPercentage * 100))\n"
        output += "**Sub-Agents:** \(useSubAgents ? "Enabled" : "Disabled")\n\n"

        if !session.hasRequiredArtifacts {
            output += "## Missing Artifacts\n"
            for artifact in session.missingArtifacts {
                output += "- \(artifact)\n"
            }
            output += "\n"
        }

        output += "## Next Steps\n"
        switch session.currentPhase {
        case .captureAnalog:
            output += "Use `capture_analog_card` to record the initial analogy hypothesis.\n"
        case .extractConstraints:
            output += "Use `extract_constraints` to extract constraints for System A and System B.\n"
        case .identityGate:
            output += "Use `check_identity_gate` to compare constraint sets.\n"
        case .divergenceBudget:
            output += "Use `record_divergence` and `compile_divergence_budget` to track mismatches.\n"
        case .derivationCheck:
            output += "Use `check_derivation` to verify structure claims.\n"
        case .gaugeSelection:
            output += "Use `select_gauge_anchor` to choose a representational frame.\n"
        case .gaugeRelativity:
            output += "Use `record_gauge_relativity` to index claims to gauges.\n"
        case .collapseDecision:
            output += "Use `generate_collapse_statement` to produce the final verdict.\n"
        case .paperPacket:
            output += "Use `generate_paper_packet` to create the manuscript.\n"
        case .complete:
            output += "Workflow complete! Use `query_collapse_session` to review artifacts.\n"
        }

        return ToolResultV2.success(
            toolId: "run_collapse_engine",
            output: output,
            structured: [
                "sessionId": sessionId,
                "status": session.status.rawValue,
                "currentPhase": session.currentPhase.rawValue,
                "completionPercentage": session.completionPercentage,
                "hasRequiredArtifacts": session.hasRequiredArtifacts
            ]
        )
    }

    // MARK: - Session Management

    private func executeCreateSession(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let name = parsed["name"] as? String else {
            return ToolResultV2.failure(
                toolId: "create_collapse_session",
                error: "Missing required parameter: name"
            )
        }

        let description = parsed["description"] as? String
        let tags = parsed["tags"] as? [String] ?? []
        let useSubAgents = parsed["use_sub_agents"] as? Bool ?? false

        do {
            let session = try await service.createSession(
                name: name,
                description: description,
                tags: tags,
                useSubAgents: useSubAgents
            )

            return ToolResultV2.success(
                toolId: "create_collapse_session",
                output: """
                Session created successfully.

                **ID:** \(session.id)
                **Name:** \(session.name)
                **Status:** \(session.status.displayName)
                **Phase:** \(session.currentPhase.displayName)

                Use `capture_analog_card` to begin the collapse workflow.
                """,
                structured: [
                    "sessionId": session.id,
                    "name": session.name,
                    "status": session.status.rawValue
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "create_collapse_session",
                error: error.localizedDescription
            )
        }
    }

    private func executeQuerySession(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "query_collapse_session",
                error: "Missing required parameter: session_id"
            )
        }

        guard let session = service.getSession(sessionId) else {
            return ToolResultV2.failure(
                toolId: "query_collapse_session",
                error: "Session not found: \(sessionId)"
            )
        }

        return ToolResultV2.success(
            toolId: "query_collapse_session",
            output: session.summary,
            structured: [
                "sessionId": session.id,
                "name": session.name,
                "status": session.status.rawValue,
                "currentPhase": session.currentPhase.rawValue,
                "analogCardId": session.analogCardId as Any,
                "constraintSetIds": session.constraintSetIds,
                "identityGateResultId": session.identityGateResultId as Any,
                "divergenceBudgetId": session.divergenceBudgetId as Any,
                "collapseStatementId": session.collapseStatementId as Any,
                "paperPacketId": session.paperPacketId as Any
            ]
        )
    }

    private func executeListSessions(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)
        let statusFilter = parsed["status_filter"] as? String
        let limit = parsed["limit"] as? Int ?? 20

        var sessions = service.sessions

        if let statusFilter = statusFilter,
           let status = CollapseStatus(rawValue: statusFilter) {
            sessions = sessions.filter { $0.status == status }
        }

        sessions = Array(sessions.prefix(limit))

        if sessions.isEmpty {
            return ToolResultV2.success(
                toolId: "list_collapse_sessions",
                output: "No collapse sessions found.\n\nUse `create_collapse_session` to create one."
            )
        }

        var output = "# Collapse Sessions (\(sessions.count))\n\n"
        for session in sessions {
            output += "- **\(session.name)** [\(session.status.displayName)]\n"
            output += "  ID: \(session.id)\n"
            output += "  Phase: \(session.currentPhase.displayName)\n\n"
        }

        return ToolResultV2.success(
            toolId: "list_collapse_sessions",
            output: output,
            structured: [
                "count": sessions.count,
                "sessions": sessions.map { ["id": $0.id, "name": $0.name, "status": $0.status.rawValue] }
            ]
        )
    }

    // MARK: - Phase 1: Capture Analog Card

    private func executeCaptureAnalogCard(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "capture_analog_card",
                error: "Missing required parameter: session_id"
            )
        }

        guard let systemADict = parsed["system_a"] as? [String: Any],
              let systemBDict = parsed["system_b"] as? [String: Any] else {
            return ToolResultV2.failure(
                toolId: "capture_analog_card",
                error: "Missing required parameters: system_a, system_b"
            )
        }

        guard let hypothesis = parsed["hypothesis"] as? String,
              let generativePotential = parsed["generative_potential"] as? String,
              let confidence = parsed["confidence"] as? Double else {
            return ToolResultV2.failure(
                toolId: "capture_analog_card",
                error: "Missing required parameters: hypothesis, generative_potential, confidence"
            )
        }

        let systemA = SystemDescription(
            name: systemADict["name"] as? String ?? "",
            domain: systemADict["domain"] as? String ?? "",
            description: systemADict["description"] as? String ?? "",
            keyPrinciples: systemADict["key_principles"] as? [String]
        )

        let systemB = SystemDescription(
            name: systemBDict["name"] as? String ?? "",
            domain: systemBDict["domain"] as? String ?? "",
            description: systemBDict["description"] as? String ?? "",
            keyPrinciples: systemBDict["key_principles"] as? [String]
        )

        do {
            let card = try await service.captureAnalogCard(
                sessionId: sessionId,
                systemA: systemA,
                systemB: systemB,
                analogyHypothesis: hypothesis,
                generativePotential: generativePotential,
                initialConfidence: confidence,
                predictedTransfer: parsed["predicted_transfer"] as? String,
                scaryMismatch: parsed["scary_mismatch"] as? String,
                scopeHint: parsed["scope_hint"] as? String,
                tags: parsed["tags"] as? [String] ?? []
            )

            return ToolResultV2.success(
                toolId: "capture_analog_card",
                output: """
                Analog card captured successfully.

                \(card.summary)

                Next: Use `extract_constraints` to extract constraints for each system.
                """,
                structured: [
                    "cardId": card.id,
                    "systemA": card.systemA.name,
                    "systemB": card.systemB.name,
                    "confidence": card.initialConfidence
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "capture_analog_card",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 2: Extract Constraints

    private func executeExtractConstraints(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "extract_constraints",
                error: "Missing required parameter: session_id"
            )
        }

        guard let systemStr = parsed["system"] as? String,
              let system = SystemLabel(rawValue: systemStr) else {
            return ToolResultV2.failure(
                toolId: "extract_constraints",
                error: "Missing or invalid parameter: system (must be 'A' or 'B')"
            )
        }

        guard let constraintsArray = parsed["constraints"] as? [[String: Any]] else {
            return ToolResultV2.failure(
                toolId: "extract_constraints",
                error: "Missing required parameter: constraints (array of constraint objects)"
            )
        }

        let constraints = constraintsArray.map { dict -> Constraint in
            Constraint(
                system: system,
                content: dict["content"] as? String ?? "",
                category: ConstraintCategory(rawValue: (dict["category"] as? String ?? "").uppercased()) ?? .structural,
                derivedFrom: dict["derived_from"] as? String,
                evidence: dict["evidence"] as? [String],
                isGenerative: dict["is_generative"] as? Bool ?? true,
                confidence: dict["confidence"] as? Double ?? 0.8,
                tags: dict["tags"] as? [String] ?? []
            )
        }

        let methodStr = parsed["method"] as? String ?? "MANUAL"
        let method = ExtractionMethod(rawValue: methodStr) ?? .manual

        do {
            let constraintSet = try await service.extractConstraints(
                sessionId: sessionId,
                system: system,
                constraints: constraints,
                method: method,
                notes: parsed["notes"] as? String
            )

            return ToolResultV2.success(
                toolId: "extract_constraints",
                output: """
                Constraints extracted for System \(system.rawValue).

                \(constraintSet.summary)

                Next: Extract constraints for the other system, then use `check_identity_gate`.
                """,
                structured: [
                    "constraintSetId": constraintSet.id,
                    "system": system.rawValue,
                    "count": constraintSet.count,
                    "averageConfidence": constraintSet.averageConfidence
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "extract_constraints",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 3: Identity Gate

    private func executeCheckIdentityGate(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "check_identity_gate",
                error: "Missing required parameter: session_id"
            )
        }

        guard let scope = parsed["scope"] as? String else {
            return ToolResultV2.failure(
                toolId: "check_identity_gate",
                error: "Missing required parameter: scope"
            )
        }

        let matchedPairsArray = parsed["matched_pairs"] as? [[String: Any]] ?? []
        let matchedPairs = matchedPairsArray.map { dict -> ConstraintPair in
            ConstraintPair(
                constraintAId: dict["constraint_a_id"] as? String ?? "",
                constraintBId: dict["constraint_b_id"] as? String ?? "",
                matchType: MatchType(rawValue: (dict["match_type"] as? String ?? "").uppercased()) ?? .analogous,
                explanation: dict["explanation"] as? String,
                confidence: dict["confidence"] as? Double ?? 0.8
            )
        }

        let unmatchedA = parsed["unmatched_a"] as? [String] ?? []
        let unmatchedB = parsed["unmatched_b"] as? [String] ?? []

        do {
            let result = try await service.runIdentityGate(
                sessionId: sessionId,
                scope: scope,
                matchedPairs: matchedPairs,
                unmatchedA: unmatchedA,
                unmatchedB: unmatchedB,
                notes: parsed["notes"] as? String
            )

            return ToolResultV2.success(
                toolId: "check_identity_gate",
                output: """
                Identity gate completed.

                \(result.summary)

                \(result.canProceedToCollapse ? "✓ Can proceed to collapse." : "✗ Cannot collapse - constraints not identical.")

                Next: Use `record_divergence` and `compile_divergence_budget` to analyze mismatches.
                """,
                structured: [
                    "resultId": result.id,
                    "verdict": result.verdict.rawValue,
                    "similarityScore": result.similarityScore,
                    "canProceed": result.canProceedToCollapse
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "check_identity_gate",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 4: Divergence Budget

    private func executeRecordDivergence(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "record_divergence",
                error: "Missing required parameter: session_id"
            )
        }

        guard let description = parsed["description"] as? String,
              let classificationStr = parsed["classification"] as? String,
              let classification = DivergenceClassification(rawValue: classificationStr.uppercased()),
              let rationale = parsed["rationale"] as? String else {
            return ToolResultV2.failure(
                toolId: "record_divergence",
                error: "Missing required parameters: description, classification, rationale"
            )
        }

        do {
            let divergence = try await service.recordDivergence(
                sessionId: sessionId,
                description: description,
                classification: classification,
                affectedConstraints: parsed["affected_constraints"] as? [String] ?? [],
                impactedClaims: parsed["impacted_claims"] as? [String],
                patchStrategy: parsed["patch_strategy"] as? String,
                rationale: rationale
            )

            return ToolResultV2.success(
                toolId: "record_divergence",
                output: """
                Divergence recorded.

                **ID:** \(divergence.id)
                **Classification:** \(divergence.classification.displayName)
                **Description:** \(divergence.description)
                \(divergence.blocksCollapse ? "⚠️ This is a FATAL divergence - blocks collapse." : "")
                """,
                structured: [
                    "divergenceId": divergence.id,
                    "classification": divergence.classification.rawValue,
                    "blocksCollapse": divergence.blocksCollapse
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "record_divergence",
                error: error.localizedDescription
            )
        }
    }

    private func executeCompileDivergenceBudget(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "compile_divergence_budget",
                error: "Missing required parameter: session_id"
            )
        }

        guard let scope = parsed["scope"] as? String else {
            return ToolResultV2.failure(
                toolId: "compile_divergence_budget",
                error: "Missing required parameter: scope"
            )
        }

        let divergencesArray = parsed["divergences"] as? [[String: Any]] ?? []
        let divergences = divergencesArray.map { dict -> Divergence in
            Divergence(
                sessionId: sessionId,
                description: dict["description"] as? String ?? "",
                classification: DivergenceClassification(rawValue: (dict["classification"] as? String ?? "").uppercased()) ?? .outOfScope,
                affectedConstraints: dict["affected_constraints"] as? [String] ?? [],
                impactedClaims: dict["impacted_claims"] as? [String],
                patchStrategy: dict["patch_strategy"] as? String,
                rationale: dict["rationale"] as? String ?? ""
            )
        }

        do {
            let budget = try await service.compileDivergenceBudget(
                sessionId: sessionId,
                divergences: divergences,
                scope: scope,
                notes: parsed["notes"] as? String
            )

            return ToolResultV2.success(
                toolId: "compile_divergence_budget",
                output: """
                Divergence budget compiled.

                \(budget.summary)

                Next: Use `check_derivation` to verify structure claims.
                """,
                structured: [
                    "budgetId": budget.id,
                    "totalCount": budget.totalCount,
                    "fatalCount": budget.fatalCount,
                    "canProceed": budget.canProceed
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "compile_divergence_budget",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 5: Derivation Check

    private func executeCheckDerivation(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "check_derivation",
                error: "Missing required parameter: session_id"
            )
        }

        guard let claimDict = parsed["claim"] as? [String: Any],
              let claimStatement = claimDict["statement"] as? String else {
            return ToolResultV2.failure(
                toolId: "check_derivation",
                error: "Missing required parameter: claim.statement"
            )
        }

        guard let statusStr = parsed["status"] as? String,
              let status = DerivationStatus(rawValue: statusStr.uppercased()) else {
            return ToolResultV2.failure(
                toolId: "check_derivation",
                error: "Missing or invalid parameter: status (PROVEN or CONJECTURED)"
            )
        }

        let claim = StructureClaim(
            sessionId: sessionId,
            statement: claimStatement,
            evidence: claimDict["evidence"] as? [String] ?? [],
            confidence: claimDict["confidence"] as? Double ?? 0.8,
            tags: claimDict["tags"] as? [String] ?? []
        )

        let stepsArray = parsed["derivation_steps"] as? [[String: Any]]
        let steps = stepsArray?.enumerated().map { (index, dict) -> DerivationStep in
            DerivationStep(
                stepNumber: dict["step_number"] as? Int ?? index + 1,
                description: dict["description"] as? String ?? "",
                justification: dict["justification"] as? String ?? "",
                references: dict["references"] as? [String]
            )
        }

        do {
            let record = try await service.checkDerivation(
                sessionId: sessionId,
                claim: claim,
                status: status,
                derivationSteps: steps,
                proofSketch: parsed["proof_sketch"] as? String,
                missingLemma: parsed["missing_lemma"] as? String,
                requiredEvidence: parsed["required_evidence"] as? [String],
                verificationMethod: parsed["verification_method"] as? String ?? "manual",
                counterexamples: parsed["counterexamples"] as? [String],
                notes: parsed["notes"] as? String
            )

            return ToolResultV2.success(
                toolId: "check_derivation",
                output: """
                Derivation check completed.

                \(record.summary)

                Next: Use `select_gauge_anchor` to choose a representational frame.
                """,
                structured: [
                    "recordId": record.id,
                    "status": record.status.rawValue,
                    "isProven": record.isProven
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "check_derivation",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 6: Gauge Selection

    private func executeSelectGaugeAnchor(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "select_gauge_anchor",
                error: "Missing required parameter: session_id"
            )
        }

        guard let name = parsed["name"] as? String,
              let description = parsed["description"] as? String,
              let quotientSymmetries = parsed["quotient_symmetries"] as? [String],
              let representationalBasis = parsed["representational_basis"] as? String,
              let selectionRationale = parsed["selection_rationale"] as? String else {
            return ToolResultV2.failure(
                toolId: "select_gauge_anchor",
                error: "Missing required parameters"
            )
        }

        do {
            let anchor = try await service.selectGaugeAnchor(
                sessionId: sessionId,
                name: name,
                description: description,
                quotientSymmetries: quotientSymmetries,
                invariantsMadeLegible: parsed["invariants_made_legible"] as? [String],
                operatorsStabilized: parsed["operators_stabilized"] as? [String],
                representationalBasis: representationalBasis,
                selectionRationale: selectionRationale,
                risks: parsed["risks"] as? [String]
            )

            return ToolResultV2.success(
                toolId: "select_gauge_anchor",
                output: """
                Gauge anchor selected.

                \(anchor.summary)

                Next: Use `record_gauge_relativity` to index claims to this gauge.
                """,
                structured: [
                    "anchorId": anchor.id,
                    "name": anchor.name
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "select_gauge_anchor",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 7: Gauge Relativity

    private func executeRecordGaugeRelativity(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String,
              let claimId = parsed["claim_id"] as? String,
              let gaugeId = parsed["gauge_id"] as? String,
              let scope = parsed["scope"] as? String else {
            return ToolResultV2.failure(
                toolId: "record_gauge_relativity",
                error: "Missing required parameters: session_id, claim_id, gauge_id, scope"
            )
        }

        do {
            let note = try await service.recordGaugeRelativityNote(
                sessionId: sessionId,
                claimId: claimId,
                gaugeId: gaugeId,
                scope: scope,
                permitsReGauging: parsed["permits_regauging"] as? Bool ?? true,
                reGaugingConstraints: parsed["regauging_constraints"] as? [String],
                allowableReGauges: parsed["allowable_regauges"] as? [String],
                transformHints: parsed["transform_hints"] as? [String],
                scopeDependencies: parsed["scope_dependencies"] as? [String],
                notes: parsed["notes"] as? String
            )

            return ToolResultV2.success(
                toolId: "record_gauge_relativity",
                output: """
                Gauge relativity note recorded.

                \(note.summary)

                Next: Use `generate_collapse_statement` to produce the final verdict.
                """,
                structured: [
                    "noteId": note.id,
                    "claimIndexing": note.claimIndexing
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "record_gauge_relativity",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 8: Collapse Statement

    private func executeGenerateCollapseStatement(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "generate_collapse_statement",
                error: "Missing required parameter: session_id"
            )
        }

        guard let summary = parsed["summary"] as? String,
              let structureS = parsed["structure_s"] as? String,
              let scope = parsed["scope"] as? String,
              let justification = parsed["justification"] as? String else {
            return ToolResultV2.failure(
                toolId: "generate_collapse_statement",
                error: "Missing required parameters: summary, structure_s, scope, justification"
            )
        }

        do {
            let statement = try await service.generateCollapseStatement(
                sessionId: sessionId,
                summary: summary,
                structureS: structureS,
                constraintsUsed: parsed["constraints_used"] as? [String] ?? [],
                structurePreserved: parsed["structure_preserved"] as? [String] ?? [],
                structureLost: parsed["structure_lost"] as? [String] ?? [],
                confidenceScore: parsed["confidence_score"] as? Double ?? 0.8,
                scope: scope,
                justification: justification,
                recommendations: parsed["recommendations"] as? [String]
            )

            return ToolResultV2.success(
                toolId: "generate_collapse_statement",
                output: """
                Collapse statement generated.

                **Verdict:** \(statement.verdict.displayName)
                \(statement.formalStatement)

                \(statement.memorySummary)

                Next: Use `generate_paper_packet` to create the manuscript.
                """,
                structured: [
                    "statementId": statement.id,
                    "verdict": statement.verdict.rawValue,
                    "isCollapsed": statement.isCollapsed,
                    "confidenceScore": statement.confidenceScore
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "generate_collapse_statement",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 9: Paper Packet

    private func executeGeneratePaperPacket(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String,
              let title = parsed["title"] as? String else {
            return ToolResultV2.failure(
                toolId: "generate_paper_packet",
                error: "Missing required parameters: session_id, title"
            )
        }

        do {
            let packet = try await service.generatePaperPacket(
                sessionId: sessionId,
                title: title,
                abstract: parsed["abstract"] as? String ?? "",
                predictions: parsed["predictions"] as? [String] ?? [],
                failureModes: parsed["failure_modes"] as? [String] ?? []
            )

            return ToolResultV2.success(
                toolId: "generate_paper_packet",
                output: """
                Paper packet generated.

                \(packet.summary)

                The paper has been saved as both JSON and Markdown.
                Use `query_collapse_session` to see the final session state.
                """,
                structured: [
                    "packetId": packet.id,
                    "title": packet.title,
                    "sectionCount": packet.sections.count,
                    "status": packet.status.rawValue
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "generate_paper_packet",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Phase 10: Strata Ledger

    private func executeQueryStrataLedger(inputs: [String: Any]) async throws -> ToolResultV2 {
        let parsed = parseJSONQuery(inputs)

        guard let sessionId = parsed["session_id"] as? String else {
            return ToolResultV2.failure(
                toolId: "query_strata_ledger",
                error: "Missing required parameter: session_id"
            )
        }

        do {
            let entries = try service.queryLedger(
                sessionId: sessionId,
                artifactId: parsed["artifact_id"] as? String,
                entryType: (parsed["entry_type"] as? String).flatMap { StrataEntryType(rawValue: $0.uppercased()) },
                limit: parsed["limit"] as? Int
            )

            if entries.isEmpty {
                return ToolResultV2.success(
                    toolId: "query_strata_ledger",
                    output: "No ledger entries found for this session."
                )
            }

            var output = "# Strata Ledger (\(entries.count) entries)\n\n"
            for entry in entries.suffix(20) {
                output += "\(entry.logLine)\n"
            }

            return ToolResultV2.success(
                toolId: "query_strata_ledger",
                output: output,
                structured: [
                    "count": entries.count,
                    "entries": entries.suffix(20).map { [
                        "id": $0.id,
                        "type": $0.entryType.rawValue,
                        "artifactType": $0.artifactType,
                        "description": $0.changeDescription
                    ] }
                ]
            )
        } catch {
            return ToolResultV2.failure(
                toolId: "query_strata_ledger",
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Helpers

    private func parseJSONQuery(_ inputs: [String: Any]) -> [String: Any] {
        // If there's a "query" field that's a JSON string, parse it
        if let query = inputs["query"] as? String,
           let data = query.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return inputs
    }
}
