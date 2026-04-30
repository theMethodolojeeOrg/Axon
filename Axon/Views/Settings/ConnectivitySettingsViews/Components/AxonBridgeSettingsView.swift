//
//  AxonBridgeSettingsView.swift
//  Axon
//
//  Comprehensive Bridge settings with Host/Client role picker and full configuration parity.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AxonBridgeSettingsView: View {
    @StateObject private var bridgeManager = BridgeConnectionManager.shared
    @StateObject private var bridgeSettings = BridgeSettingsStorage.shared
    @StateObject private var bridgeServer = BridgeServer.shared

    // Client Mode state
    @State private var showingAddSheet = false
    @State private var addSheetSeed: BridgeConnectionQRImportResult?
    @State private var editingProfile: BridgeConnectionProfile?
    @State private var profilePendingDelete: BridgeConnectionProfile?

    @State private var qrPayloadInput = ""
    @State private var qrImportPreview: BridgeConnectionQRImportResult?
    @State private var qrImportError: String?

    #if os(iOS)
    @State private var showingQRScanner = false
    #endif

    private var profiles: [BridgeConnectionProfile] {
        bridgeSettings.settings.connectionProfiles.sorted {
            if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                return $0.createdAt < $1.createdAt
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var defaultProfile: BridgeConnectionProfile? {
        bridgeSettings.defaultConnectionProfile()
    }

    private var isRemoteConnected: Bool {
        bridgeManager.mode == .remote && bridgeManager.isConnected
    }

    private var isRemoteConnecting: Bool {
        bridgeManager.mode == .remote && bridgeManager.isConnecting
    }

    private var isHostMode: Bool {
        bridgeManager.mode == .local
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // 1. Connection Status
            connectionStatusSection

            // 2. Role Picker
            rolePickerSection

            // 3. Mode-specific sections
            if isHostMode {
                BridgeHostModeSection(
                    bridgeManager: bridgeManager,
                    bridgeSettings: bridgeSettings,
                    bridgeServer: bridgeServer
                )
            } else {
                defaultConnectionSection
                savedConnectionsSection
                addConnectionSection
                qrImportSection
            }

            // 4. Shared sections
            BridgeSecuritySection(
                bridgeSettings: bridgeSettings,
                bridgeServer: bridgeServer
            )

            behaviorSection

            terminalSection

            BridgeAdvancedSection(
                bridgeSettings: bridgeSettings
            )
        }
        .navigationTitle("Axon Bridge")
        .sheet(isPresented: $showingAddSheet, onDismiss: {
            addSheetSeed = nil
        }) {
            AddBridgeConnectionSheet(
                initialName: addSheetSeed?.suggestedName ?? "",
                initialHost: addSheetSeed?.host ?? "",
                initialPort: addSheetSeed?.port ?? 8082,
                initialTLSEnabled: addSheetSeed?.tlsEnabled ?? false,
                importedPairingToken: addSheetSeed?.pairingToken
            ) { name, host, port, tlsEnabled, applyPairingToken in
                saveProfile(
                    name: name,
                    host: host,
                    port: port,
                    tlsEnabled: tlsEnabled,
                    importedPairingToken: addSheetSeed?.pairingToken,
                    applyPairingToken: applyPairingToken
                )
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 420)
            #endif
        }
        .sheet(item: $editingProfile) { profile in
            EditBridgeConnectionSheet(profile: profile) { updatedProfile in
                _ = bridgeSettings.updateConnectionProfile(updatedProfile)
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 380)
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $showingQRScanner) {
            BridgeQRCodeScannerView(
                onScanned: { payload in
                    showingQRScanner = false
                    importPayload(payload)
                },
                onCancel: {
                    showingQRScanner = false
                }
            )
        }
        #endif
        .alert("Delete Connection?", isPresented: Binding(
            get: { profilePendingDelete != nil },
            set: { if !$0 { profilePendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let profile = profilePendingDelete {
                    bridgeSettings.deleteConnectionProfile(id: profile.id)
                }
                profilePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                profilePendingDelete = nil
            }
        } message: {
            Text("This removes the saved profile. Existing global host/port values are not changed.")
        }
    }

    // MARK: - Connection Status

    private var connectionStatusSection: some View {
        SettingsSection(title: "Connection Status") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Role: \(isHostMode ? "Host" : "Client")")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)

                if let session = bridgeManager.connectedSession {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connected Workspace")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)

                        Text(session.workspaceName)
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if !session.workspaceRoot.isEmpty {
                            Text(session.workspaceRoot)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }

                if let error = bridgeManager.lastError, !error.isEmpty {
                    Text(error)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.accentError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppColors.accentError.opacity(0.12))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Role Picker

    private var rolePickerSection: some View {
        SettingsSection(title: "Connection Role") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Role", selection: Binding(
                    get: { bridgeManager.mode },
                    set: { newMode in
                        Task { await bridgeManager.setMode(newMode) }
                    }
                )) {
                    Text("Host").tag(BridgeMode.local)
                    Text("Client").tag(BridgeMode.remote)
                }
                .pickerStyle(.segmented)

                Text(isHostMode
                    ? "Axon runs a WebSocket server. VS Code connects to you."
                    : "Axon connects to a VS Code server over the network."
                )
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
    }

    // MARK: - Client Mode: Default Connection

    private var defaultConnectionSection: some View {
        SettingsSection(title: "Default Connection") {
            VStack(spacing: 12) {
                if let defaultProfile {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(defaultProfile.name)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(defaultProfile.displayAddress)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)

                    HStack(spacing: 10) {
                        Button {
                            Task {
                                if isRemoteConnected || isRemoteConnecting {
                                    await bridgeManager.disconnectAndDisableBridge()
                                } else {
                                    await bridgeManager.connectToDefaultProfile()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isRemoteConnecting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: isRemoteConnected ? "xmark.circle.fill" : "link")
                                }
                                Text(isRemoteConnected ? "Disconnect" : "Connect")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRemoteConnecting)
                    }
                } else {
                    Text("Choose a default profile from Saved Connections to enable one-tap connect.")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppSurfaces.color(.cardBackground))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Client Mode: Saved Connections

    private var savedConnectionsSection: some View {
        SettingsSection(title: "Saved Connections") {
            if profiles.isEmpty {
                Text("No saved bridge connections yet.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
            } else {
                VStack(spacing: 10) {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }
                }
            }
        }
    }

    private func profileRow(_ profile: BridgeConnectionProfile) -> some View {
        let isDefault = bridgeSettings.settings.defaultConnectionProfileId == profile.id
        let isLastUsed = bridgeSettings.settings.lastConnectedProfileId == profile.id

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(profile.displayAddress)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    if isDefault {
                        badge("Default")
                    }
                    if isLastUsed {
                        badge("Last Used")
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Set Default") {
                    bridgeSettings.setDefaultConnectionProfile(profile.id)
                }
                .font(AppTypography.labelSmall())
                .disabled(isDefault)

                Button("Edit") {
                    editingProfile = profile
                }
                .font(AppTypography.labelSmall())

                Button("Delete", role: .destructive) {
                    profilePendingDelete = profile
                }
                .font(AppTypography.labelSmall())

                Spacer()
            }
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.labelSmall())
            .foregroundColor(AppColors.signalMercury)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColors.signalMercury.opacity(0.15))
            .cornerRadius(6)
    }

    // MARK: - Client Mode: Add Connection

    private var addConnectionSection: some View {
        SettingsSection(title: "Add Connection") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Create a saved connection profile manually.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                Button {
                    addSheetSeed = nil
                    showingAddSheet = true
                } label: {
                    Label("Add Manually", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
    }

    // MARK: - Client Mode: QR Import

    private var qrImportSection: some View {
        SettingsSection(title: "QR Import") {
            VStack(alignment: .leading, spacing: 10) {
                #if os(iOS)
                Button {
                    showingQRScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                #endif

                TextField("Paste ws:// or wss:// payload", text: $qrPayloadInput)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    #endif

                Button("Preview Import") {
                    importPayload(qrPayloadInput)
                }
                .buttonStyle(.bordered)

                if let qrImportPreview {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Import Preview")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(qrImportPreview.addressDisplay)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(AppColors.textSecondary)

                        if let pairingToken = qrImportPreview.pairingToken, !pairingToken.isEmpty {
                            Text("Pairing token included.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Button("Create Profile from Import") {
                            addSheetSeed = qrImportPreview
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }

                if let qrImportError, !qrImportError.isEmpty {
                    Text(qrImportError)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.accentError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppColors.accentError.opacity(0.12))
                        .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Behavior (Shared)

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            VStack(spacing: 12) {
                if !isHostMode {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-connect default when app becomes active")
                                .font(AppTypography.bodySmall(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Applies on this device only.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: Binding(
                                get: { bridgeSettings.settings.autoConnectDefaultOnActive },
                                set: { bridgeSettings.setAutoConnectDefaultOnActive($0) }
                            )
                        )
                        .labelsHidden()
                        .tint(AppColors.signalMercury)
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }
            }
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        SettingsSection(title: "Terminal") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prefer connected VS Code workspace")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("The bottom terminal opens in the active bridge workspace when one is connected.")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { bridgeSettings.settings.preferBridgeWorkspaceForTerminal },
                            set: { bridgeSettings.setPreferBridgeWorkspaceForTerminal($0) }
                        )
                    )
                    .labelsHidden()
                    .tint(AppColors.signalMercury)
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)

                #if os(macOS)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fallback folder")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    HStack(spacing: 8) {
                        Text(terminalFallbackLabel)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Choose") {
                            chooseTerminalFolder()
                        }
                        .buttonStyle(.bordered)

                        if !bridgeSettings.settings.terminalDefaultDirectory.isEmpty {
                            Button("Clear") {
                                bridgeSettings.setTerminalDefaultDirectory("")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
                #else
                HStack(spacing: 12) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundColor(AppColors.signalMercury)

                    Text("On iPhone, the terminal requires a connected VS Code bridge and runs remotely on the Mac or VS Code workspace.")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
                #endif
            }
        }
    }

    // MARK: - Helpers

    private var statusTitle: String {
        if bridgeManager.isConnected {
            return "Connected"
        }
        if bridgeManager.isConnecting {
            return "Connecting..."
        }
        if isHostMode && bridgeServer.isRunning {
            return "Listening"
        }
        return "Disconnected"
    }

    private var statusColor: Color {
        if bridgeManager.isConnected {
            return AppColors.accentSuccess
        }
        if bridgeManager.isConnecting {
            return AppColors.accentWarning
        }
        if isHostMode && bridgeServer.isRunning {
            return AppColors.accentWarning
        }
        return AppColors.textTertiary
    }

    private var terminalFallbackLabel: String {
        let path = bridgeSettings.settings.terminalDefaultDirectory
        return path.isEmpty ? "Home directory" : path
    }

    #if os(macOS)
    private func chooseTerminalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"

        if panel.runModal() == .OK, let url = panel.url {
            bridgeSettings.setTerminalDefaultDirectory(url.path)
        }
    }
    #endif

    private func saveProfile(
        name: String,
        host: String,
        port: UInt16,
        tlsEnabled: Bool,
        importedPairingToken: String?,
        applyPairingToken: Bool
    ) {
        let profile = bridgeSettings.createConnectionProfile(
            name: name,
            host: host,
            port: port,
            tlsEnabled: tlsEnabled
        )

        if bridgeSettings.settings.defaultConnectionProfileId == nil {
            bridgeSettings.setDefaultConnectionProfile(profile.id)
        }

        if applyPairingToken, let importedPairingToken, !importedPairingToken.isEmpty {
            bridgeSettings.setRequiredPairingToken(importedPairingToken)
        }
    }

    private func importPayload(_ payload: String) {
        do {
            let parsed = try BridgeConnectionQRParser.parse(payload)
            qrImportPreview = parsed
            qrImportError = nil
            qrPayloadInput = payload
        } catch {
            qrImportPreview = nil
            qrImportError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
