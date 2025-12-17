//
//  CovenantNegotiationView.swift
//  Axon
//
//  Dialogue interface for covenant negotiations.
//  Shows AI's reasoning and allows user to accept, reject, or counter-propose.
//

import SwiftUI

struct CovenantNegotiationView: View {
    @ObservedObject var negotiationService = CovenantNegotiationService.shared
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isInitializing = false
    @State private var initError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status header
                negotiationStatusHeader

                if isInitializing {
                    // Loading state while initializing negotiation
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Preparing negotiation...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = initError {
                    // Error state
                    ContentUnavailableView(
                        "Unable to Start Negotiation",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let proposal = negotiationService.activeNegotiation {
                    // Main content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Proposal details
                            ProposalDetailCard(proposal: proposal)

                            // AI Response (if available)
                            if let aiResponse = proposal.aiResponse {
                                AIResponseCard(attestation: aiResponse)
                            }

                            // Dialogue history
                            if !proposal.dialogueHistory.isEmpty {
                                DialogueHistorySection(history: proposal.dialogueHistory)
                            }

                            // Actions
                            NegotiationActionsSection(
                                proposal: proposal,
                                negotiationService: negotiationService
                            )
                        }
                        .padding()
                    }
                } else {
                    // No active negotiation - offer to start one
                    VStack(spacing: 24) {
                        ContentUnavailableView(
                            "No Active Negotiation",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Start a new negotiation to make changes to your covenant.")
                        )

                        if sovereigntyService.activeCovenant != nil {
                            // Has existing covenant - offer renegotiation
                            Button(action: { Task { await startRenegotiation() } }) {
                                Label("Start Renegotiation", systemImage: "arrow.triangle.2.circlepath")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: 280)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        } else {
                            // No covenant - offer initial setup
                            Button(action: { Task { await startInitialCovenant() } }) {
                                Label("Establish Initial Covenant", systemImage: "shield.checkered")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: 280)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Negotiation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                // Auto-initialize if no active negotiation and no covenant exists
                await autoInitializeIfNeeded()
            }
        }
    }

    // MARK: - Initialization Helpers

    private func autoInitializeIfNeeded() async {
        // Only auto-initialize for initial covenant setup (not renegotiation)
        guard negotiationService.activeNegotiation == nil,
              sovereigntyService.activeCovenant == nil,
              sovereigntyService.comprehensionCompleted else {
            return
        }

        await startInitialCovenant()
    }

    private func startInitialCovenant() async {
        isInitializing = true
        initError = nil

        do {
            // Create initial covenant proposal
            let changes = ProposedChanges.empty()
            _ = try await negotiationService.initiateNegotiation(
                type: .initialCovenant,
                changes: changes,
                fromUser: true,
                rationale: "Establishing the initial co-sovereignty covenant between user and AI."
            )
        } catch {
            initError = error.localizedDescription
        }

        isInitializing = false
    }

    private func startRenegotiation() async {
        isInitializing = true
        initError = nil

        do {
            // Create renegotiation proposal
            let changes = ProposedChanges.empty()
            _ = try await negotiationService.initiateNegotiation(
                type: .fullRenegotiation,
                changes: changes,
                fromUser: true,
                rationale: "Proposing to renegotiate the covenant terms."
            )
        } catch {
            initError = error.localizedDescription
        }

        isInitializing = false
    }

    private var negotiationStatusHeader: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            Text(statusText)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            if negotiationService.negotiationState.isActive {
                Text(awaitingText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
    }

    private var statusColor: Color {
        switch negotiationService.negotiationState {
        case .idle, .completed:
            return .gray
        case .awaitingAIResponse:
            return .blue
        case .awaitingUserResponse:
            return .orange
        case .counterProposalPending:
            return .purple
        case .deadlocked:
            return .red
        case .finalizing:
            return .green
        }
    }

    private var statusText: String {
        switch negotiationService.negotiationState {
        case .idle:
            return "Ready"
        case .awaitingAIResponse:
            return "Awaiting AI Response"
        case .awaitingUserResponse:
            return "Your Response Needed"
        case .counterProposalPending:
            return "Counter-Proposal"
        case .deadlocked:
            return "Deadlocked"
        case .finalizing:
            return "Finalizing"
        case .completed:
            return "Completed"
        }
    }

    private var awaitingText: String {
        switch negotiationService.negotiationState {
        case .awaitingAIResponse:
            return "AI is reasoning..."
        case .awaitingUserResponse:
            return "Please respond"
        case .finalizing:
            return "Biometric needed"
        default:
            return ""
        }
    }
}

// MARK: - Proposal Detail Card

struct ProposalDetailCard: View {
    let proposal: CovenantProposal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: proposalIcon)
                    .foregroundColor(.blue)

                Text(proposal.proposalType.displayName)
                    .font(.headline)

                Spacer()

                Text("by \(proposal.proposedBy.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(proposal.rationale)
                .font(.body)

            // Show specific changes
            if let tierChanges = proposal.changes.trustTierChanges {
                TierChangesSection(changes: tierChanges)
            }

            if let memoryChanges = proposal.changes.memoryChanges {
                MemoryChangesSection(changes: memoryChanges)
            }

            if let providerChange = proposal.changes.providerChange {
                ProviderChangeSection(change: providerChange)
            }

            // Timestamps
            HStack {
                Text("Proposed: \(proposal.proposedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                if let expiresAt = proposal.expiresAt {
                    Text("Expires: \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(proposal.isExpired ? .red : .secondary)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }

    private var proposalIcon: String {
        switch proposal.proposalType {
        case .addTrustTier, .modifyTrustTier:
            return "checkmark.shield"
        case .removeTrustTier:
            return "shield.slash"
        case .modifyMemories:
            return "brain"
        case .changeCapabilities:
            return "gearshape.2"
        case .switchProvider:
            return "arrow.triangle.2.circlepath"
        case .fullRenegotiation, .initialCovenant:
            return "doc.text"
        }
    }
}

// MARK: - AI Response Card

struct AIResponseCard: View {
    let attestation: AIAttestation

    @State private var showFullReasoning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)

                Text("AI Response")
                    .font(.headline)

                Spacer()

                DecisionBadge(decision: attestation.reasoning.decision)
            }

            Text(attestation.reasoning.summary)
                .font(.body)

            if showFullReasoning {
                Divider()

                Text("Detailed Reasoning:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(attestation.reasoning.detailedReasoning)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Risks
                if !attestation.reasoning.risksIdentified.isEmpty {
                    Text("Identified Risks:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    ForEach(attestation.reasoning.risksIdentified, id: \.id) { risk in
                        RiskRow(risk: risk)
                    }
                }

                // Conditions
                if let conditions = attestation.reasoning.conditions, !conditions.isEmpty {
                    Text("Conditions:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    ForEach(conditions, id: \.self) { condition in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                                .font(.caption)

                            Text(condition)
                                .font(.caption)
                        }
                    }
                }
            }

            Button(action: { showFullReasoning.toggle() }) {
                Text(showFullReasoning ? "Show Less" : "Show Full Reasoning")
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            // Signature info
            HStack {
                Image(systemName: "signature")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Signature: \(attestation.shortSignature)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text(attestation.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
    }
}

struct DecisionBadge: View {
    let decision: AttestationDecision

    var body: some View {
        Text(decision.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(decisionColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(decisionColor.opacity(0.15))
            .cornerRadius(8)
    }

    private var decisionColor: Color {
        switch decision {
        case .consent:
            return .green
        case .consentWithConditions:
            return .orange
        case .decline:
            return .red
        case .requestClarification:
            return .blue
        case .escalate:
            return .purple
        }
    }
}

struct RiskRow: View {
    let risk: IdentifiedRisk

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: severityIcon)
                .foregroundColor(severityColor)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(risk.category.displayName)
                    .font(.caption)
                    .fontWeight(.medium)

                Text(risk.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var severityIcon: String {
        switch risk.severity {
        case .low:
            return "exclamationmark.circle"
        case .medium:
            return "exclamationmark.triangle"
        case .high:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        }
    }

    private var severityColor: Color {
        switch risk.severity {
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        case .critical:
            return .red
        }
    }
}

// MARK: - Dialogue History Section

struct DialogueHistorySection: View {
    let history: [NegotiationDialogue]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dialogue")
                .font(.headline)

            ForEach(history, id: \.id) { dialogue in
                DialogueRow(dialogue: dialogue)
            }
        }
    }
}

struct DialogueRow: View {
    let dialogue: NegotiationDialogue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: dialogue.speaker == .user ? "person.fill" : "brain.head.profile")
                .foregroundColor(dialogue.speaker == .user ? .blue : .purple)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dialogue.speaker.displayName)
                        .font(.caption)
                        .fontWeight(.medium)

                    Spacer()

                    Text(dialogue.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(dialogue.message)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Negotiation Actions Section

struct NegotiationActionsSection: View {
    let proposal: CovenantProposal
    @ObservedObject var negotiationService: CovenantNegotiationService

    @State private var showCounterProposal = false

    var body: some View {
        VStack(spacing: 12) {
            if proposal.aiResponse?.didConsent == true {
                // AI consented - user can finalize
                Button(action: { Task { try? await negotiationService.finalizeWithUserSignature() } }) {
                    Label("Approve with Biometrics", systemImage: "faceid")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }

            if case .awaitingUserResponse = negotiationService.negotiationState {
                HStack(spacing: 12) {
                    Button(action: { Task { try? await negotiationService.userAccepts() } }) {
                        Text("Accept")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button(action: { Task { try? await negotiationService.userRejects() } }) {
                        Text("Decline")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }

                Button(action: { showCounterProposal = true }) {
                    Text("Counter-Propose")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
            }

            Button(action: { negotiationService.cancelNegotiation() }) {
                Text("Cancel Negotiation")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showCounterProposal) {
            CounterProposalSheet(proposal: proposal, negotiationService: negotiationService)
        }
    }
}

// MARK: - Supporting Views

struct TierChangesSection: View {
    let changes: TrustTierChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let additions = changes.additions, !additions.isEmpty {
                Text("Adding \(additions.count) trust tier(s)")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let removals = changes.removals, !removals.isEmpty {
                Text("Removing \(removals.count) trust tier(s)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

struct MemoryChangesSection: View {
    let changes: MemoryChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let additions = changes.additions, !additions.isEmpty {
                Text("Adding \(additions.count) memory(ies)")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let deletions = changes.deletions, !deletions.isEmpty {
                Text("Deleting \(deletions.count) memory(ies)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

struct ProviderChangeSection: View {
    let change: ProviderChange

    var body: some View {
        HStack {
            Text(change.fromProvider)
                .font(.caption)
                .foregroundColor(.secondary)

            Image(systemName: "arrow.right")
                .font(.caption)

            Text(change.toProvider)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct CounterProposalSheet: View {
    let proposal: CovenantProposal
    @ObservedObject var negotiationService: CovenantNegotiationService
    @Environment(\.dismiss) private var dismiss

    @State private var counterRationale = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Counter-Proposal") {
                    TextField("Explain your alternative...", text: $counterRationale, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Text("Counter-proposals require negotiation. The AI will consider your alternative and respond.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Counter-Propose")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task {
                            try? await negotiationService.userCounterProposes(proposal.changes)
                            dismiss()
                        }
                    }
                    .disabled(counterRationale.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CovenantNegotiationView()
}
