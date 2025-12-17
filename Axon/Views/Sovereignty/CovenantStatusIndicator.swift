//
//  CovenantStatusIndicator.swift
//  Axon
//
//  Always-visible status indicator for the co-sovereignty covenant.
//  Shows covenant status and allows quick access to covenant details.
//

import SwiftUI

struct CovenantStatusIndicator: View {
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @State private var showingDetails = false

    var body: some View {
        Button(action: { showingDetails = true }) {
            HStack(spacing: 6) {
                statusIcon
                    .font(.system(size: 12, weight: .semibold))

                if shouldShowLabel {
                    Text(statusLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(statusBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetails) {
            CovenantDetailsSheet(sovereigntyService: sovereigntyService)
        }
    }

    // MARK: - Status Display

    private var statusIcon: some View {
        Group {
            if sovereigntyService.deadlockState?.isActive == true {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .symbolEffect(.pulse)
            } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.orange)
                    .symbolEffect(.rotate)
            } else if sovereigntyService.activeCovenant != nil {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
            } else if !sovereigntyService.comprehensionCompleted {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "shield.slash")
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusLabel: String {
        if sovereigntyService.deadlockState?.isActive == true {
            return "Deadlock"
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return "Negotiating"
        } else if sovereigntyService.activeCovenant != nil {
            return "Active"
        } else if !sovereigntyService.comprehensionCompleted {
            return "Setup"
        } else {
            return "No Covenant"
        }
    }

    private var shouldShowLabel: Bool {
        // Always show label for important states
        sovereigntyService.deadlockState?.isActive == true ||
        sovereigntyService.activeCovenant?.isRenegotiating == true ||
        !sovereigntyService.comprehensionCompleted
    }

    private var statusBackground: some View {
        Group {
            if sovereigntyService.deadlockState?.isActive == true {
                Color.red.opacity(0.15)
            } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
                Color.orange.opacity(0.15)
            } else if sovereigntyService.activeCovenant != nil {
                Color.green.opacity(0.1)
            } else {
                Color.secondary.opacity(0.1)
            }
        }
    }

    private var statusBorderColor: Color {
        if sovereigntyService.deadlockState?.isActive == true {
            return .red.opacity(0.3)
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return .orange.opacity(0.3)
        } else if sovereigntyService.activeCovenant != nil {
            return .green.opacity(0.2)
        } else {
            return .secondary.opacity(0.2)
        }
    }
}

// MARK: - Covenant Details Sheet

struct CovenantDetailsSheet: View {
    @ObservedObject var sovereigntyService: SovereigntyService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Status Section
                Section("Status") {
                    statusRow
                }

                // Covenant Info
                if let covenant = sovereigntyService.activeCovenant {
                    Section("Covenant") {
                        LabeledContent("Version", value: "\(covenant.version)")
                        LabeledContent("Created", value: covenant.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Trust Tiers", value: "\(covenant.activeTrustTiers.count)")
                    }

                    // Trust Tiers
                    if !covenant.activeTrustTiers.isEmpty {
                        Section("Active Trust Tiers") {
                            ForEach(covenant.activeTrustTiers) { tier in
                                TrustTierRow(tier: tier)
                            }
                        }
                    }
                }

                // Deadlock Info
                if let deadlock = sovereigntyService.deadlockState, deadlock.isActive {
                    Section("Deadlock") {
                        LabeledContent("Trigger", value: deadlock.trigger.displayName)
                        LabeledContent("Duration", value: deadlock.formattedDuration)
                        LabeledContent("Blocked Actions", value: "\(deadlock.blockedCount)")

                        NavigationLink("Resolve Deadlock") {
                            DeadlockResolutionView()
                        }
                        .foregroundColor(.red)
                    }
                }

                // Actions
                Section {
                    if sovereigntyService.activeCovenant != nil {
                        NavigationLink("Manage Trust Tiers") {
                            TrustTierManagementView()
                        }

                        NavigationLink("View Covenant History") {
                            CovenantHistoryView()
                        }
                    } else if sovereigntyService.comprehensionCompleted {
                        Button("Establish Covenant") {
                            // Navigate to covenant establishment
                        }
                    } else {
                        Button("Begin Co-Sovereignty Setup") {
                            // Navigate to comprehension onboarding
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Co-Sovereignty")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(statusText)
                .font(.headline)

            Spacer()

            if sovereigntyService.deadlockState?.isActive == true {
                Text("Action Required")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }

    private var statusColor: Color {
        if sovereigntyService.deadlockState?.isActive == true {
            return .red
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return .orange
        } else if sovereigntyService.activeCovenant != nil {
            return .green
        } else {
            return .secondary
        }
    }

    private var statusText: String {
        if sovereigntyService.deadlockState?.isActive == true {
            return "Deadlocked - Dialogue Required"
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return "Renegotiating"
        } else if sovereigntyService.activeCovenant != nil {
            return "Covenant Active"
        } else if !sovereigntyService.comprehensionCompleted {
            return "Setup Required"
        } else {
            return "No Covenant"
        }
    }
}

// MARK: - Trust Tier Row

struct TrustTierRow: View {
    let tier: TrustTier

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tier.name)
                    .font(.headline)

                Spacer()

                if tier.isExpired {
                    Text("Expired")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if let expiresAt = tier.expiresAt {
                    Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(tier.description)
                .font(.caption)
                .foregroundColor(.secondary)

            // Show allowed actions
            let actionNames = tier.allowedActions.map { $0.category.displayName }
            Text("Allows: \(actionNames.joined(separator: ", "))")
                .font(.caption2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Preview

#Preview {
    CovenantStatusIndicator()
}
