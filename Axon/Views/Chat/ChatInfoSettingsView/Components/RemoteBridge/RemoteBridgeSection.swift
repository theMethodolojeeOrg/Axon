//
//  RemoteBridgeSection.swift
//  Axon
//
//  iOS Remote Bridge section for VS Code connection
//

import SwiftUI

#if !os(macOS)
struct RemoteBridgeSection: View {
    @ObservedObject var bridgeManager = BridgeConnectionManager.shared
    @ObservedObject var bridgeSettings = BridgeSettingsStorage.shared
    
    @Binding var remoteHost: String
    @Binding var remotePort: String
    
    var body: some View {
        VStack(spacing: 12) {
            // Connection Status Header
            connectionStatusHeader
            
            // Server Address Inputs (only show when not connected)
            if !bridgeManager.isConnected {
                serverAddressInputs
            }
            
            // Connected Session Info
            if let session = bridgeManager.connectedSession {
                connectedSessionInfo(session)
            }
            
            // Error Message
            if let error = bridgeManager.lastError {
                errorMessage(error)
            }
            
            // Connect/Disconnect Button
            connectButton
        }
    }
    
    // MARK: - Connection Status Header
    
    private var connectionStatusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: bridgeStatusIcon)
                .font(.system(size: 16))
                .foregroundColor(bridgeStatusColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("VS Code Bridge")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                
                Text(bridgeStatusText)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(bridgeStatusColor)
            }
            
            Spacer()
            
            // Connection status indicator
            Circle()
                .fill(bridgeStatusColor)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
    
    // MARK: - Server Address Inputs
    
    private var serverAddressInputs: some View {
        VStack(spacing: 8) {
            // Host input
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(width: 24)
                
                TextField("VS Code IP (e.g., 192.168.1.100)", text: $remoteHost)
                    .font(AppTypography.bodySmall())
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.numbersAndPunctuation)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
            
            // Port input
            HStack {
                Image(systemName: "number")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(width: 24)
                
                TextField("Port (default: 8082)", text: $remotePort)
                    .font(AppTypography.bodySmall())
                    .textFieldStyle(.plain)
                    .keyboardType(.numberPad)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
    
    // MARK: - Connected Session Info
    
    private func connectedSessionInfo(_ session: BridgeSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalLichen)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.workspaceName)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                
                Text(session.workspaceRoot)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
    
    // MARK: - Error Message
    
    private func errorMessage(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(AppColors.accentError)
            
            Text(error)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.accentError)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.accentError.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Connect Button
    
    private var connectButton: some View {
        Button {
            Task {
                await toggleRemoteConnection()
            }
        } label: {
            HStack {
                if bridgeManager.isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: bridgeManager.isConnected ? "xmark.circle" : "link")
                }
                
                Text(bridgeButtonText)
                    .font(AppTypography.bodySmall(.medium))
            }
            .foregroundColor(bridgeManager.isConnected ? AppColors.accentError : AppColors.signalMercury)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                (bridgeManager.isConnected ? AppColors.accentError : AppColors.signalMercury)
                    .opacity(0.15)
            )
            .cornerRadius(8)
        }
        .disabled(bridgeManager.isConnecting || (!bridgeManager.isConnected && remoteHost.isEmpty))
    }
    
    // MARK: - Helpers
    
    private var bridgeStatusIcon: String {
        if bridgeManager.isConnected {
            return "personalhotspot"
        } else if bridgeManager.isConnecting {
            return "antenna.radiowaves.left.and.right"
        } else {
            return "personalhotspot.slash"
        }
    }
    
    private var bridgeStatusColor: Color {
        if bridgeManager.isConnected {
            return AppColors.signalLichen
        } else if bridgeManager.isConnecting {
            return AppColors.accentWarning
        } else {
            return AppColors.textTertiary
        }
    }
    
    private var bridgeStatusText: String {
        if bridgeManager.isConnected {
            if let session = bridgeManager.connectedSession {
                return "Connected to \(session.workspaceName)"
            }
            return "Connected"
        } else if bridgeManager.isConnecting {
            return "Connecting..."
        } else {
            return "Not connected"
        }
    }
    
    private var bridgeButtonText: String {
        if bridgeManager.isConnecting {
            return "Connecting..."
        } else if bridgeManager.isConnected {
            return "Disconnect"
        } else {
            return "Connect to VS Code"
        }
    }
    
    private func toggleRemoteConnection() async {
        if bridgeManager.isConnected {
            await bridgeManager.stop()
        } else {
            // Save settings
            let port = UInt16(remotePort) ?? 8082
            bridgeSettings.setRemoteConfig(host: remoteHost, port: port)
            
            // Ensure we're in remote mode
            await bridgeManager.setMode(.remote)
            
            // Connect
            await bridgeManager.start()
        }
    }
}

#Preview {
    RemoteBridgeSection(
        remoteHost: .constant("192.168.1.100"),
        remotePort: .constant("8082")
    )
    .padding()
    .background(AppColors.substratePrimary)
}
#endif
