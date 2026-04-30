//
//  ChatBridgeQuickCard.swift
//  Axon
//
//  Compact bridge controls for Chat Info settings.
//

import SwiftUI

struct ChatBridgeQuickCard: View {
    @ObservedObject var bridgeManager = BridgeConnectionManager.shared
    @ObservedObject var bridgeSettings = BridgeSettingsStorage.shared

    let onManage: () -> Void

    @State private var showingProfilePicker = false
    @State private var selectedProfileId: UUID?
    @State private var setSelectedAsDefault = true

    private var defaultProfile: BridgeConnectionProfile? {
        bridgeSettings.defaultConnectionProfile()
    }

    private var profiles: [BridgeConnectionProfile] {
        bridgeSettings.settings.connectionProfiles.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var isRemoteConnected: Bool {
        bridgeManager.mode == .remote && bridgeManager.isConnected
    }

    private var isRemoteConnecting: Bool {
        bridgeManager.mode == .remote && bridgeManager.isConnecting
    }

    var body: some View {
        ChatInfoSection(title: "Axon Bridge") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusText)
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if let defaultProfile {
                            Text("\(defaultProfile.name) • \(defaultProfile.displayAddress)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        } else {
                            Text("No default profile selected")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await primaryAction()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isRemoteConnecting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: isRemoteConnected ? "xmark.circle.fill" : "link")
                            }
                            Text(primaryButtonTitle)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRemoteConnecting)

                    Button("Manage") {
                        onManage()
                    }
                    .buttonStyle(.bordered)
                }

                if let error = bridgeManager.lastError, !error.isEmpty {
                    Text(error)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.accentError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .sheet(isPresented: $showingProfilePicker) {
            ProfilePickerSheet(
                profiles: profiles,
                selectedProfileId: $selectedProfileId,
                setSelectedAsDefault: $setSelectedAsDefault,
                onConnect: connectFromPicker
            )
            #if os(macOS)
            .frame(minWidth: 500, minHeight: 420)
            #endif
        }
    }

    private var statusText: String {
        if isRemoteConnected {
            return "Connected to VS Code"
        }
        if isRemoteConnecting {
            return "Connecting..."
        }
        return "Disconnected"
    }

    private var statusColor: Color {
        if isRemoteConnected {
            return AppColors.accentSuccess
        }
        if isRemoteConnecting {
            return AppColors.accentWarning
        }
        return AppColors.textTertiary
    }

    private var primaryButtonTitle: String {
        if isRemoteConnecting {
            return "Connecting..."
        }
        if isRemoteConnected {
            return "Disconnect"
        }
        return "Connect"
    }

    private func primaryAction() async {
        if isRemoteConnected || isRemoteConnecting {
            await bridgeManager.disconnectAndDisableBridge()
            return
        }

        if defaultProfile != nil {
            await bridgeManager.connectToDefaultProfile()
            return
        }

        guard !profiles.isEmpty else {
            onManage()
            return
        }

        selectedProfileId = profiles.first?.id
        setSelectedAsDefault = true
        showingProfilePicker = true
    }

    @MainActor
    private func connectFromPicker() {
        guard let selectedProfileId else { return }
        showingProfilePicker = false

        Task {
            if setSelectedAsDefault {
                bridgeSettings.setDefaultConnectionProfile(selectedProfileId)
            }
            await bridgeManager.connectToProfile(profileId: selectedProfileId)
        }
    }
}

private struct ProfilePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profiles: [BridgeConnectionProfile]
    @Binding var selectedProfileId: UUID?
    @Binding var setSelectedAsDefault: Bool
    let onConnect: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                List(profiles) { profile in
                    Button {
                        selectedProfileId = profile.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedProfileId == profile.id ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedProfileId == profile.id ? AppColors.signalMercury : AppColors.textTertiary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(AppColors.textPrimary)
                                Text(profile.displayAddress)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)

                Toggle("Set selected profile as default", isOn: $setSelectedAsDefault)
                    .padding(.horizontal)
            }
            .navigationTitle("Choose Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        onConnect()
                    }
                    .disabled(selectedProfileId == nil)
                }
            }
        }
    }
}
