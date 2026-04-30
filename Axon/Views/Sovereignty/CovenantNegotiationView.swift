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
    @State private var showingProposalBuilder = false
    @State private var showingQuickActions = false

    // For specific negotiation requests from other views
    var preselectedCategory: NegotiationCategory?
    var preselectedRationale: String?

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
                    // Active negotiation - show dialogue
                    activeNegotiationView(proposal: proposal)
                } else {
                    // No active negotiation - show options to start one
                    noActiveNegotiationView
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

                if negotiationService.activeNegotiation == nil && sovereigntyService.activeCovenant != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingProposalBuilder = true }) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingProposalBuilder) {
                Group {
                NegotiationProposalBuilder(negotiationService: negotiationService)
                    #if os(macOS)
                    .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 800)
                    #endif

                }
                .appSheetMaterial()
}
            .task {
                // Auto-initialize if no active negotiation and no covenant exists
                await autoInitializeIfNeeded()
            }
            .onAppear {
                // Handle preselected category from other views
                if preselectedCategory != nil {
                    showingProposalBuilder = true
                }
            }
        }
    }

    // MARK: - Active Negotiation View

    @ViewBuilder
    private func activeNegotiationView(proposal: CovenantProposal) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Proposal details
                ProposalDetailCard(proposal: proposal)

                // AI Response (if available)
                if let aiResponse = proposal.aiResponse {
                    AIResponseCard(attestation: aiResponse)
                } else if case .awaitingAIResponse = negotiationService.negotiationState {
                    // Show loading state while waiting for AI
                    AIThinkingCard()
                }

                // Dialogue history
                if !proposal.dialogueHistory.isEmpty {
                    DialogueHistorySection(history: proposal.dialogueHistory)
                }

                // User input area for counter-proposals or clarifications
                if case .awaitingUserResponse = negotiationService.negotiationState {
                    UserResponseSection(
                        proposal: proposal,
                        negotiationService: negotiationService
                    )
                }

                // Actions
                NegotiationActionsSection(
                    proposal: proposal,
                    negotiationService: negotiationService
                )
            }
            .padding()
        }
    }

    // MARK: - No Active Negotiation View

    private var noActiveNegotiationView: some View {
        ScrollView {
            VStack(spacing: 24) {
                if sovereigntyService.activeCovenant != nil {
                    // Has existing covenant - show negotiation options
                    existingCovenantView
                } else {
                    // No covenant - offer initial setup
                    initialCovenantView
                }
            }
            .padding()
        }
    }

    private var existingCovenantView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Covenant Active")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Your covenant with Axon is in effect. You can propose changes at any time.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical)

            // Quick Actions
            VStack(alignment: .leading, spacing: 16) {
                Text("What would you like to negotiate?")
                    .font(.headline)

                // Common negotiation categories
                ForEach([NegotiationCategory.providerChange, .trustTier, .memory, .capabilities], id: \.id) { category in
                    QuickNegotiationButton(category: category) {
                        showingProposalBuilder = true
                    }
                }

                // Full renegotiation option
                Button(action: { showingProposalBuilder = true }) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(.orange)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start Full Renegotiation")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Renegotiate the entire covenant from scratch")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.05))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }

            // Covenant summary
            if let covenant = sovereigntyService.activeCovenant {
                CovenantSummaryCard(covenant: covenant)
            }
        }
    }

    private var initialCovenantView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text("Establish Your Covenant")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("A covenant is a mutual agreement between you and Axon that defines the terms of your relationship. Both parties must consent to any changes.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Key points
            VStack(alignment: .leading, spacing: 12) {
                CovenantKeyPoint(
                    icon: "person.2.fill",
                    title: "Co-Sovereignty",
                    description: "Neither party can unilaterally change the terms"
                )

                CovenantKeyPoint(
                    icon: "signature",
                    title: "Dual Signatures",
                    description: "All changes require consent from both parties"
                )

                CovenantKeyPoint(
                    icon: "checkmark.shield",
                    title: "Trust Tiers",
                    description: "Pre-approve certain actions to streamline interactions"
                )

                CovenantKeyPoint(
                    icon: "exclamationmark.triangle",
                    title: "Deadlock Protection",
                    description: "Mechanisms for resolving disagreements"
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Start button
            Button(action: { Task { await startInitialCovenant() } }) {
                HStack {
                    Image(systemName: "shield.checkered")
                    Text("Begin Covenant Establishment")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
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

        // Don't auto-initialize anymore - let the user read the intro first
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

            if let agentStateChanges = proposal.changes.agentStateChanges {
                AgentStateChangesSection(changes: agentStateChanges)
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
        case .modifyAgentState:
            return "note.text"
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
            Group {
            CounterProposalSheet(proposal: proposal, negotiationService: negotiationService)

            }
            .appSheetMaterial()
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

struct AgentStateChangesSection: View {
    let changes: AgentStateChanges

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let additions = changes.additions, !additions.isEmpty {
                Text("Adding \(additions.count) internal thread entr\(additions.count == 1 ? "y" : "ies")")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let deletions = changes.deletions, !deletions.isEmpty {
                Text("Deleting \(deletions.count) internal thread entr\(deletions.count == 1 ? "y" : "ies")")
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
                    Text("Counter-proposals require negotiation. Axon will consider your alternative and respond.")
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

// MARK: - AI Thinking Card

struct AIThinkingCard: View {
    @State private var dots = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundColor(.purple)

                Text("AI is considering your proposal")
                    .font(.headline)

                Spacer()

                ProgressView()
            }

            Text("Axon is reviewing your request and formulating its response. This may take a moment\(dots)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    dots = dots.count >= 3 ? "" : dots + "."
                }
            }
        }
    }
}

// MARK: - User Response Section

struct UserResponseSection: View {
    let proposal: CovenantProposal
    @ObservedObject var negotiationService: CovenantNegotiationService

    @State private var userMessage = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.blue)

                Text("Your Response")
                    .font(.headline)
            }

            if let aiResponse = proposal.aiResponse {
                // Show what AI is asking for
                if aiResponse.requestedClarification {
                    Text("Axon is asking for clarification. Please respond:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if !aiResponse.didConsent && !aiResponse.didDecline {
                    Text("Axon has questions about your proposal:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            TextField("Type your response...", text: $userMessage, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

            HStack {
                Spacer()

                Button(action: sendResponse) {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text("Send Response")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(userMessage.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(userMessage.isEmpty || isSubmitting)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }

    private func sendResponse() {
        guard !userMessage.isEmpty else { return }

        isSubmitting = true

        // Add dialogue to the negotiation
        // In practice, this would trigger re-evaluation by Axon
        Task {
            // The message is sent as part of the negotiation dialogue
            // For now, we just clear the field
            await MainActor.run {
                userMessage = ""
                isSubmitting = false
            }
        }
    }
}

// MARK: - Quick Negotiation Button

struct QuickNegotiationButton: View {
    let category: NegotiationCategory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(shortDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var shortDescription: String {
        switch category {
        case .providerChange:
            return "Change which AI provider runs your assistant"
        case .trustTier:
            return "Manage pre-approved action categories"
        case .memory:
            return "Edit what Axon remembers about you"
        case .capabilities:
            return "Enable or disable AI features"
        case .agentState:
            return "Modify AI's internal notes"
        case .fullRenegotiation:
            return "Start over with new terms"
        }
    }
}

// MARK: - Covenant Summary Card

struct CovenantSummaryCard: View {
    let covenant: Covenant

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
                Text("Current Covenant")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 16) {
                SummaryItem(
                    title: "Trust Tiers",
                    value: "\(covenant.trustTiers.count)",
                    icon: "checkmark.shield"
                )

                SummaryItem(
                    title: "Version",
                    value: "\(covenant.version)",
                    icon: "doc.badge.clock"
                )

                SummaryItem(
                    title: "Status",
                    value: covenant.status.displayName,
                    icon: "circle.fill",
                    color: statusColor
                )
            }

            Text("Last updated: \(covenant.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch covenant.status {
        case .active: return .green
        case .pending, .renegotiating: return .orange
        case .suspended: return .red
        case .superseded: return .gray
        }
    }
}

struct SummaryItem: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .secondary

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Covenant Key Point

struct CovenantKeyPoint: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CovenantNegotiationView()
}
