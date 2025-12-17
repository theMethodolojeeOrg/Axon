//
//  CovenantDetailView.swift
//  Axon
//
//  Detailed view of a covenant showing all its contents:
//  trust tiers, signatures, state hashes, and negotiation history.
//

import SwiftUI

struct CovenantDetailView: View {
    let covenant: Covenant
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showingRenegotiation = false

    var body: some View {
        NavigationStack {
            List {
                // Overview Section
                Section("Overview") {
                    LabeledContent("Version", value: "v\(covenant.version)")
                    LabeledContent("Status", value: covenantStatusDisplayName)
                    LabeledContent("Created", value: covenant.createdAt.formatted(date: .long, time: .shortened))
                    LabeledContent("Last Updated", value: covenant.updatedAt.formatted(date: .long, time: .shortened))
                }

                // Trust Tiers Section
                Section {
                    if covenant.trustTiers.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "shield.slash")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("No Trust Tiers")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    } else {
                        ForEach(covenant.trustTiers) { tier in
                            CovenantTrustTierRow(tier: tier)
                        }
                    }
                } header: {
                    HStack {
                        Text("Trust Tiers")
                        Spacer()
                        Text("\(covenant.activeTrustTiers.count) active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Signatures Section
                Section("Signatures") {
                    // AI Attestation
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.purple)
                            Text("AI Attestation")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                        }

                        Text(covenant.aiAttestation.reasoning.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Signature")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(covenant.aiAttestation.shortSignature)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Signed")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(covenant.aiAttestation.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    // User Signature
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.blue)
                            Text("User Signature")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                        }

                        HStack {
                            Image(systemName: covenant.userSignature.biometricSystemImage)
                            Text(covenant.userSignature.biometricDisplayName)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Signature")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(covenant.userSignature.shortSignature)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Signed")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(covenant.userSignature.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // State Integrity Section
                Section("State Integrity") {
                    StateHashRow(
                        title: "Memory State",
                        icon: "brain",
                        hash: covenant.memoryStateHash
                    )

                    StateHashRow(
                        title: "Capability State",
                        icon: "gearshape.2",
                        hash: covenant.capabilityStateHash
                    )

                    StateHashRow(
                        title: "Settings State",
                        icon: "slider.horizontal.3",
                        hash: covenant.settingsStateHash
                    )
                }

                // Negotiation History Section
                if !covenant.negotiationHistory.isEmpty {
                    Section("Negotiation History") {
                        ForEach(covenant.negotiationHistory.suffix(5).reversed(), id: \.id) { event in
                            CovenantNegotiationEventRow(event: event)
                        }

                        if covenant.negotiationHistory.count > 5 {
                            Text("+ \(covenant.negotiationHistory.count - 5) more events")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Actions Section
                Section {
                    Button(action: { showingRenegotiation = true }) {
                        Label("Propose Changes", systemImage: "pencil")
                    }

                    if covenant.status == .active {
                        Button(role: .destructive, action: {}) {
                            Label("Suspend Covenant", systemImage: "pause.circle")
                        }
                    }
                }
            }
            .navigationTitle("Covenant Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingRenegotiation) {
                CovenantNegotiationView()
                    #if os(macOS)
                    .frame(minWidth: 550, idealWidth: 650, minHeight: 550, idealHeight: 700)
                    #endif
            }
        }
    }

    private var covenantStatusDisplayName: String {
        switch covenant.status {
        case .active: return "Active"
        case .pending: return "Pending"
        case .renegotiating: return "Renegotiating"
        case .suspended: return "Suspended"
        case .superseded: return "Superseded"
        }
    }
}

// MARK: - Covenant Trust Tier Row

struct CovenantTrustTierRow: View {
    let tier: TrustTier

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundColor(tier.isExpired ? .secondary : .blue)

                Text(tier.name)
                    .font(.headline)
                    .foregroundColor(tier.isExpired ? .secondary : .primary)

                Spacer()

                if tier.isExpired {
                    Text("Expired")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                } else if tier.isFullySigned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }

            Text(tier.description)
                .font(.caption)
                .foregroundColor(.secondary)

            // Actions summary
            HStack(spacing: 4) {
                ForEach(Array(tier.allowedActions.prefix(4).enumerated()), id: \.offset) { _, action in
                    Image(systemName: action.category.tierIcon)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }

                if tier.allowedActions.count > 4 {
                    Text("+\(tier.allowedActions.count - 4)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let expiresAt = tier.expiresAt {
                    Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(tier.isExpired ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(tier.isExpired ? 0.6 : 1.0)
    }
}

// MARK: - State Hash Row

struct StateHashRow: View {
    let title: String
    let icon: String
    let hash: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)

                Text(hash.prefix(32) + "...")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Covenant Negotiation Event Row

struct CovenantNegotiationEventRow: View {
    let event: NegotiationEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: eventIcon)
                .foregroundColor(eventColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.description)
                    .font(.subheadline)

                HStack {
                    Text(eventTypeDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var eventTypeDisplayName: String {
        switch event.eventType {
        case .covenantCreated: return "Covenant Created"
        case .proposalSubmitted: return "Proposal Submitted"
        case .proposalAccepted: return "Proposal Accepted"
        case .proposalRejected: return "Proposal Rejected"
        case .proposalCountered: return "Counter-Proposal"
        case .trustTierAdded: return "Trust Tier Added"
        case .trustTierModified: return "Trust Tier Modified"
        case .trustTierRemoved: return "Trust Tier Removed"
        case .deadlockEntered: return "Deadlock Entered"
        case .deadlockResolved: return "Deadlock Resolved"
        case .covenantSuperseded: return "Covenant Superseded"
        }
    }

    private var eventIcon: String {
        switch event.eventType {
        case .covenantCreated: return "doc.badge.plus"
        case .proposalSubmitted: return "doc.badge.plus"
        case .proposalAccepted: return "checkmark.circle"
        case .proposalRejected: return "xmark.circle"
        case .proposalCountered: return "arrow.triangle.2.circlepath"
        case .deadlockEntered: return "exclamationmark.triangle"
        case .deadlockResolved: return "checkmark.shield"
        case .covenantSuperseded: return "doc.badge.gearshape"
        case .trustTierAdded: return "plus.shield"
        case .trustTierRemoved: return "minus.shield"
        case .trustTierModified: return "pencil"
        }
    }

    private var eventColor: Color {
        switch event.eventType {
        case .proposalAccepted, .deadlockResolved, .trustTierAdded, .covenantCreated:
            return .green
        case .proposalRejected, .deadlockEntered, .trustTierRemoved:
            return .red
        case .proposalCountered, .trustTierModified:
            return .orange
        default:
            return .blue
        }
    }
}

// MARK: - Preview

#Preview {
    CovenantDetailView(covenant: Covenant.createInitial(
        aiAttestation: AIAttestation.create(
            reasoning: .consent(
                summary: "Test attestation",
                detailedReasoning: "Detailed reasoning here",
                valuesApplied: ["autonomy"]
            ),
            attestedState: AttestedState(
                memoryCount: 0,
                memoryHash: "abc123",
                enabledCapabilities: [],
                capabilityHash: "def456",
                trustTierIds: [],
                currentProviderId: "test",
                settingsHash: "ghi789"
            ),
            modelId: "test-model",
            signatureGenerator: { _ in "test-signature" }
        ),
        userSignature: UserSignature.create(
            signedItemType: .covenant,
            signedItemId: "test",
            signedDataHash: "test-hash",
            biometricType: "faceID",
            deviceId: "test-device",
            signatureGenerator: { _ in "test-signature" }
        ),
        memoryStateHash: "abc123",
        capabilityStateHash: "def456",
        settingsStateHash: "ghi789"
    ))
}
