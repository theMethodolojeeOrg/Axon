//
//  CovenantHistoryView.swift
//  Axon
//
//  View showing the history of all covenants, including past versions
//  and covenants from other devices (when synced).
//

import SwiftUI

struct CovenantHistoryView: View {
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCovenant: Covenant?
    @State private var showingCovenantDetail = false

    var body: some View {
        NavigationStack {
            List {
                // Current Covenant Section
                if let current = sovereigntyService.activeCovenant {
                    Section("Current Covenant") {
                        CovenantHistoryRow(
                            covenant: current,
                            isCurrent: true
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCovenant = current
                            showingCovenantDetail = true
                        }
                    }
                }

                // Past Covenants Section
                let history = sovereigntyService.getCovenantHistory()
                if !history.isEmpty {
                    Section("Past Covenants") {
                        ForEach(history.reversed(), id: \.id) { covenant in
                            CovenantHistoryRow(
                                covenant: covenant,
                                isCurrent: false
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCovenant = covenant
                                showingCovenantDetail = true
                            }
                        }
                    }
                }

                // Empty State
                if sovereigntyService.activeCovenant == nil && history.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Covenant History",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("Your covenant history will appear here once you establish your first covenant.")
                        )
                    }
                }

                // Info Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("About Covenant History", systemImage: "info.circle")
                            .font(.headline)

                        Text("Each time your covenant is updated through negotiation, the previous version is archived here. This provides a complete audit trail of your co-sovereignty relationship.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Covenant History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCovenantDetail) {
                if let covenant = selectedCovenant {
                    CovenantDetailView(covenant: covenant)
                        #if os(macOS)
                        .frame(minWidth: 500, idealWidth: 600, minHeight: 550, idealHeight: 700)
                        #endif
                }
            }
        }
    }
}

// MARK: - Covenant History Row

struct CovenantHistoryRow: View {
    let covenant: Covenant
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Status icon
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Covenant v\(covenant.version)")
                            .font(.headline)

                        if isCurrent {
                            Text("Current")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }

                    Text(covenant.status.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Device indicator (if available)
                if let deviceType = covenant.deviceType {
                    Image(systemName: deviceIcon(for: deviceType))
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Trust tiers summary
            HStack(spacing: 16) {
                Label("\(covenant.trustTiers.count) tiers", systemImage: "shield.checkered")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if covenant.isFullySigned {
                    Label("Signed", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            // Dates
            HStack {
                Text("Created: \(covenant.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                if !isCurrent {
                    Text("Superseded: \(covenant.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch covenant.status {
        case .active:
            return .green
        case .renegotiating:
            return .orange
        case .deadlocked:
            return .red
        case .superseded:
            return .gray
        case .suspended:
            return .yellow
        }
    }

    private var statusIcon: String {
        switch covenant.status {
        case .active:
            return "checkmark.shield.fill"
        case .renegotiating:
            return "arrow.triangle.2.circlepath"
        case .deadlocked:
            return "exclamationmark.triangle.fill"
        case .superseded:
            return "clock.arrow.circlepath"
        case .suspended:
            return "pause.circle.fill"
        }
    }

    private func deviceIcon(for deviceType: String) -> String {
        switch deviceType.lowercased() {
        case "iphone": return "iphone"
        case "ipad": return "ipad"
        case "mac": return "laptopcomputer"
        case "vision": return "visionpro"
        default: return "desktopcomputer"
        }
    }
}

// MARK: - Preview

#Preview {
    CovenantHistoryView()
}
