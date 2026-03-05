//
//  BridgeHostModeSection.swift
//  Axon
//
//  Host Mode UI sections for when Axon acts as the WebSocket server.
//  Includes server controls, configuration, LAN addresses, QR code, and connected clients.
//

import SwiftUI

struct BridgeHostModeSection: View {
    @ObservedObject var bridgeManager: BridgeConnectionManager
    @ObservedObject var bridgeSettings: BridgeSettingsStorage
    @ObservedObject var bridgeServer: BridgeServer

    @State private var portText: String = ""
    @State private var copiedPayload = false

    var body: some View {
        serverControlsSection
        serverConfigSection
        serverAddressesSection
        qrCodeSection
        connectedClientsSection
    }

    // MARK: - Server Controls

    private var serverControlsSection: some View {
        SettingsSection(title: "Server Controls") {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(bridgeServer.isRunning ? AppColors.accentSuccess : AppColors.textTertiary)
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(bridgeServer.isRunning ? "Server Running" : "Server Stopped")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if bridgeServer.isRunning {
                            Text("Listening on port \(bridgeSettings.settings.port)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    Spacer()
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)

                Button {
                    Task {
                        if bridgeServer.isRunning {
                            await bridgeManager.stopHostMode()
                        } else {
                            await bridgeManager.startHostMode()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: bridgeServer.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        Text(bridgeServer.isRunning ? "Stop Server" : "Start Server")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Server Configuration

    private var serverConfigSection: some View {
        SettingsSection(title: "Server Configuration") {
            VStack(spacing: 12) {
                // Port
                HStack {
                    Text("Port")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    TextField("8081", text: $portText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onAppear {
                            portText = String(bridgeSettings.settings.port)
                        }
                        .onChange(of: portText) { newValue in
                            if let port = UInt16(newValue), port > 0 {
                                bridgeSettings.setServerPort(port)
                            }
                        }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)

                // Bind Address
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Allow LAN connections")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("When off, only localhost can connect.")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { bridgeSettings.settings.serverBindAddress == "0.0.0.0" },
                            set: { bridgeSettings.setServerBindAddress($0 ? "0.0.0.0" : "127.0.0.1") }
                        )
                    )
                    .labelsHidden()
                    .tint(AppColors.signalMercury)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Server Addresses

    private var serverAddressesSection: some View {
        SettingsSection(title: "Server Addresses") {
            if bridgeServer.isRunning {
                if bridgeServer.localAddresses.isEmpty {
                    Text("No LAN addresses detected. Check your network connection.")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(bridgeServer.localAddresses) { addr in
                            addressRow(addr)
                        }
                    }
                }
            } else {
                Text("Start the server to see available addresses.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
            }
        }
    }

    private func addressRow(_ addr: BridgeNetworkAddress) -> some View {
        let url = BridgeNetworkUtils.buildWebSocketURL(
            host: addr.ipAddress,
            port: bridgeSettings.settings.port,
            tlsEnabled: bridgeSettings.settings.tlsEnabled
        )
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(addr.interfaceName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                    if addr.isPrimary {
                        Text("Primary")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text(url)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button {
                #if os(iOS)
                UIPasteboard.general.string = url
                #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }

    // MARK: - QR Code

    private var qrCodeSection: some View {
        SettingsSection(title: "QR Code") {
            VStack(spacing: 12) {
                if bridgeServer.isRunning {
                    #if os(iOS)
                    if let qrImage = bridgeServer.generateQRCodeImage(size: 200) {
                        Image(uiImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity)
                    }
                    #elseif os(macOS)
                    if let qrImage = bridgeServer.generateQRCodeImage(size: 200) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity)
                    }
                    #endif

                    if let payload = bridgeServer.generateQRPayload() {
                        Text(payload)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = payload
                            #elseif os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(payload, forType: .string)
                            #endif
                            copiedPayload = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedPayload = false
                            }
                        } label: {
                            Label(
                                copiedPayload ? "Copied!" : "Copy Payload",
                                systemImage: copiedPayload ? "checkmark" : "doc.on.doc"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Scan this QR code in VS Code to connect.")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                } else {
                    Text("Start the server to generate a QR code.")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }

    // MARK: - Connected Clients

    private var connectedClientsSection: some View {
        SettingsSection(title: "Connected Clients") {
            if bridgeServer.sessions.isEmpty {
                Text("No clients connected.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(bridgeServer.sessions.values), id: \.id) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: BridgeSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.workspaceName)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)

            if !session.workspaceRoot.isEmpty {
                Text(session.workspaceRoot)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}
