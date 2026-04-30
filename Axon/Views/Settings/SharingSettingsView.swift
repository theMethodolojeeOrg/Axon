//
//  SharingSettingsView.swift
//  Axon
//
//  Created by Tom on 2025.
//

import SwiftUI

// MARK: - Sharing Settings View

struct SharingSettingsView: View {
    @ObservedObject private var settingsService = SettingsViewModel.shared
    @ObservedObject private var sharingService = GuestSharingService.shared
    @State private var showingRequestDetail: SharingRequest?
    @State private var showingInvitationDetail: GuestInvitation?
    @State private var showingCreateInvitation = false
    @State private var showingRequestLink = false

    private var settings: SharingSettings {
        settingsService.settings.sharingSettings
    }

    var body: some View {
        List {
            // Enable/Disable Section
            enableSection

            if settings.enabled {
                // Pending Requests Section
                pendingRequestsSection

                // Active Invitations Section
                activeInvitationsSection

                // Connected Guests Section
                connectedGuestsSection

                // Privacy Settings Section
                privacySettingsSection

                // Default Settings Section
                defaultSettingsSection
            }
        }
        .navigationTitle("AI Sharing")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(item: $showingRequestDetail) {
            request in
            Group {
            RequestDetailSheet(request: request)

            }
            .appSheetMaterial()
}
        .sheet(item: $showingInvitationDetail) {
            invitation in
            Group {
            InvitationDetailSheet(invitation: invitation)

            }
            .appSheetMaterial()
}
    }

    // MARK: - Enable Section

    private var enableSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.enabled },
                set: { newValue in
                    var updated = settingsService.settings
                    updated.sharingSettings.enabled = newValue
                    settingsService.settings = updated
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable AI Sharing")
                        .font(.body)
                    Text("Allow friends to request access to your AI's learned patterns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if settings.enabled {
                Button {
                    showingRequestLink = true
                } label: {
                    HStack {
                        Image(systemName: "link.badge.plus")
                        Text("Share Request Link")
                    }
                }
                .sheet(isPresented: $showingRequestLink) {
                    Group {
                    RequestLinkSheet()

                    }
                    .appSheetMaterial()
}
            }
        } header: {
            Text("Sharing")
        } footer: {
            if settings.enabled {
                Text("Friends can use your request link to ask for access. You and your AI will review each request together.")
            }
        }
    }

    // MARK: - Pending Requests Section

    private var pendingRequestsSection: some View {
        Section {
            if sharingService.pendingRequests.filter({ !$0.status.isTerminal }).isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .foregroundColor(.secondary)
                    Text("No pending requests")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(sharingService.pendingRequests.filter { !$0.status.isTerminal }) { request in
                    RequestRow(request: request)
                        .onTapGesture {
                            showingRequestDetail = request
                        }
                }
            }
        } header: {
            HStack {
                Text("Pending Requests")
                Spacer()
                let count = sharingService.pendingRequests.filter { !$0.status.isTerminal }.count
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Active Invitations Section

    private var activeInvitationsSection: some View {
        Section {
            if sharingService.activeInvitations.filter({ $0.isValid }).isEmpty {
                HStack {
                    Image(systemName: "ticket")
                        .foregroundColor(.secondary)
                    Text("No active invitations")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(sharingService.activeInvitations.filter { $0.isValid }) { invitation in
                    InvitationRow(invitation: invitation)
                        .onTapGesture {
                            showingInvitationDetail = invitation
                        }
                }
            }
        } header: {
            Text("Active Invitations")
        }
    }

    // MARK: - Connected Guests Section

    private var connectedGuestsSection: some View {
        Section {
            if sharingService.activeSessions.filter({ $0.isActive }).isEmpty {
                HStack {
                    Image(systemName: "person.2")
                        .foregroundColor(.secondary)
                    Text("No guests connected")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(sharingService.activeSessions.filter { $0.isActive }) { session in
                    GuestSessionRow(session: session)
                }
            }
        } header: {
            Text("Connected Guests")
        }
    }

    // MARK: - Privacy Settings Section

    private var privacySettingsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.requireAIConsent },
                set: { newValue in
                    var updated = settingsService.settings
                    updated.sharingSettings.requireAIConsent = newValue
                    settingsService.settings = updated
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Require AI Consent")
                        .font(.body)
                    Text("Both you and your AI must approve each sharing request")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Toggle(isOn: Binding(
                get: { settings.requireBiometricForInvitations },
                set: { newValue in
                    var updated = settingsService.settings
                    updated.sharingSettings.requireBiometricForInvitations = newValue
                    settingsService.settings = updated
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Require Biometric")
                        .font(.body)
                    Text("Use Face ID or Touch ID when creating invitations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            NavigationLink {
                ExcludedTagsEditor()
            } label: {
                HStack {
                    Text("Excluded Tags")
                    Spacer()
                    Text("\(settings.excludedTags.count) tags")
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Memories tagged with excluded tags will never be shared with guests.")
        }
    }

    // MARK: - Default Settings Section

    private var defaultSettingsSection: some View {
        Section {
            Picker("Default Expiration", selection: Binding(
                get: { settings.defaultExpirationHours },
                set: { newValue in
                    var updated = settingsService.settings
                    updated.sharingSettings.defaultExpirationHours = newValue
                    settingsService.settings = updated
                }
            )) {
                Text("1 hour").tag(1)
                Text("6 hours").tag(6)
                Text("24 hours").tag(24)
                Text("7 days").tag(168)
            }

            Stepper(value: Binding(
                get: { settings.maxConcurrentGuests },
                set: { newValue in
                    var updated = settingsService.settings
                    updated.sharingSettings.maxConcurrentGuests = newValue
                    settingsService.settings = updated
                }
            ), in: 1...10) {
                HStack {
                    Text("Max Concurrent Guests")
                    Spacer()
                    Text("\(settings.maxConcurrentGuests)")
                        .foregroundColor(.secondary)
                }
            }

            Picker("Default Capabilities", selection: Binding(
                get: { settings.defaultCapabilitiesPreset },
                set: { newValue in
                    var updated = settingsService.settings
                    updated.sharingSettings.defaultCapabilitiesPreset = newValue
                    settingsService.settings = updated
                }
            )) {
                ForEach(GuestCapabilitiesPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }

            Toggle(isOn: Binding(
                get: { settings.notifyOnGuestConnect },
                set: { newValue in
                    var updated = settingsService.settings
                    updated.sharingSettings.notifyOnGuestConnect = newValue
                    settingsService.settings = updated
                }
            )) {
                Text("Notify When Guests Connect")
            }
        } header: {
            Text("Defaults")
        }
    }
}

// MARK: - Request Row

struct RequestRow: View {
    let request: SharingRequest

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(request.guestName.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundColor(.blue)
                )

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(request.guestName)
                    .font(.headline)
                Text(request.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: request.status)
                Text(request.formattedDuration)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Invitation Row

struct InvitationRow: View {
    let invitation: GuestInvitation

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "ticket.fill")
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 44, height: 44)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(invitation.guestName)
                    .font(.headline)
                Text(invitation.formattedTimeRemaining)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Sessions count
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(invitation.usageCount)/\(invitation.maxSessions)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text("sessions")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Guest Session Row

struct GuestSessionRow: View {
    let session: GuestSession

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(session.isActive ? Color.green : Color.gray)
                .frame(width: 10, height: 10)

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(session.guestDeviceName)
                    .font(.headline)
                Text("\(session.queryCount) queries • \(session.formattedSessionDuration)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Disconnect button
            if session.isActive {
                Button {
                    GuestSharingService.shared.disconnectSession(session.id)
                } label: {
                    Text("Disconnect")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: RequestStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.bold())
            .foregroundColor(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .negotiating: return .blue
        case .accepted: return .green
        case .counterOffered: return .purple
        case .declined: return .red
        case .expired: return .gray
        case .withdrawn: return .gray
        }
    }
}

// MARK: - Supporting Sheets

struct RequestDetailSheet: View {
    let request: SharingRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            JointNegotiationView(request: request)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct InvitationDetailSheet: View {
    let invitation: GuestInvitation
    @Environment(\.dismiss) private var dismiss
    @State private var showingRevokeAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Guest Name", value: invitation.guestName)
                    LabeledContent("Status", value: invitation.statusDescription)
                    LabeledContent("Time Remaining", value: invitation.formattedTimeRemaining)
                    LabeledContent("Sessions Used", value: "\(invitation.usageCount)/\(invitation.maxSessions)")
                }

                Section("Capabilities") {
                    CapabilitySummaryView(capabilities: invitation.grantedCapabilities)
                }

                if invitation.isValid {
                    Section {
                        Button(role: .destructive) {
                            showingRevokeAlert = true
                        } label: {
                            Label("Revoke Invitation", systemImage: "xmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("Invitation Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Revoke Invitation?", isPresented: $showingRevokeAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Revoke", role: .destructive) {
                    GuestSharingService.shared.revokeInvitation(invitation.id)
                    dismiss()
                }
            } message: {
                Text("This will immediately disconnect any active sessions using this invitation.")
            }
        }
    }
}

struct RequestLinkSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text("Share Your Request Link")
                    .font(.title2.bold())

                Text("Friends can use this link to request access to your AI's learned patterns. You'll review each request with your AI before approving.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                // Placeholder for QR code and link
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .overlay(
                            Text("QR Code\n(Coming Soon)")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        )

                    Button {
                        // Copy link to clipboard
                    } label: {
                        Label("Copy Link", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        // Share link
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Request Link")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExcludedTagsEditor: View {
    @ObservedObject private var settingsService = SettingsViewModel.shared
    @State private var newTag = ""

    private var excludedTags: [String] {
        settingsService.settings.sharingSettings.excludedTags
    }

    var body: some View {
        List {
            Section {
                ForEach(excludedTags, id: \.self) { tag in
                    Text(tag)
                }
                .onDelete(perform: deleteTag)
            }

            Section {
                HStack {
                    TextField("Add tag...", text: $newTag)
                    Button {
                        addTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newTag.isEmpty)
                }
            }
        }
        .navigationTitle("Excluded Tags")
    }

    private func deleteTag(at offsets: IndexSet) {
        var updated = settingsService.settings
        updated.sharingSettings.excludedTags.remove(atOffsets: offsets)
        settingsService.settings = updated
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tag.isEmpty, !excludedTags.contains(tag) else { return }

        var updated = settingsService.settings
        updated.sharingSettings.excludedTags.append(tag)
        settingsService.settings = updated
        newTag = ""
    }
}

struct CapabilitySummaryView: View {
    let capabilities: GuestCapabilities

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapabilityRow(
                icon: "bubble.left.and.bubble.right",
                title: "Chat with Context",
                enabled: capabilities.canChatWithContext
            )
            CapabilityRow(
                icon: "magnifyingglass",
                title: "Search Memories",
                enabled: capabilities.canQueryMemories
            )
            if capabilities.canQueryMemories {
                Text("Max \(capabilities.maxMemoriesPerQuery) memories per query, \(capabilities.maxQueriesPerHour)/hour")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 28)
            }
        }
    }
}

struct CapabilityRow: View {
    let icon: String
    let title: String
    let enabled: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(enabled ? .green : .gray)
                .frame(width: 20)
            Text(title)
            Spacer()
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(enabled ? .green : .gray)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SharingSettingsView()
    }
}
