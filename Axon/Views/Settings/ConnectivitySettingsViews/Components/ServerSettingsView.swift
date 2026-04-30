//
//  ServerSettingsView.swift
//  Axon
//
//  Local API Server settings with OpenAI compatibility
//

import SwiftUI

struct ServerSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var showPasswordField = false
    @State private var copiedURL = false
    @State private var copiedPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Server Status Section
            SettingsSection(title: "Server Status") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // Status indicator
                        Circle()
                            .fill(serverStatusColor)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(serverStatusText)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            if let error = viewModel.serverError {
                                Text(error)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.accentError)
                            } else if viewModel.isServerRunning {
                                Text("Accessible via HTTP")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }

                        Spacer()

                        // Start/Stop button
                        Button(action: {
                            Task {
                                if viewModel.isServerRunning {
                                    await viewModel.stopServer()
                                } else {
                                    await viewModel.startServer()
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: viewModel.isServerRunning ? "stop.circle.fill" : "play.circle.fill")
                                    .foregroundColor(.white)
                                Text(viewModel.isServerRunning ? "Stop Server" : "Start Server")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(viewModel.isServerRunning ? AppColors.accentError : AppColors.signalMercury)
                            )
                        }
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)

                    // Warning about foreground requirement
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppColors.accentWarning)
                        Text("Server requires app to be in foreground on iOS")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.horizontal)
                }
            }

            // Connection Info Section
            if viewModel.isServerRunning {
                SettingsSection(title: "Connection Info") {
                    VStack(spacing: 12) {
                        // Local URL
                        ConnectionInfoRow(
                            icon: "network",
                            title: "Local URL",
                            value: viewModel.serverLocalURL,
                            copied: $copiedURL
                        )

                        // Network URL (if external connections enabled)
                        if viewModel.settings.serverAllowExternal, !viewModel.serverNetworkURL.isEmpty {
                            ConnectionInfoRow(
                                icon: "wifi",
                                title: "Network URL",
                                value: viewModel.serverNetworkURL,
                                copied: $copiedURL
                            )
                        }

                        // Example cURL command
                        if let password = viewModel.settings.serverPassword, !password.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Example Request")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                                    .padding(.horizontal, 4)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(exampleCurlCommand)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(AppColors.textSecondary)
                                        .padding()
                                        .background(AppSurfaces.color(.controlBackground))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
            }

            // Axon Bridge Debugging
            SettingsSection(title: "Axon Bridge") {
                NavigationLink(destination: BridgeLogInspector()) {
                    HStack {
                        Image(systemName: "ladybug.circle")
                            .foregroundColor(AppColors.accentPrimary)
                        Text("Bridge Inspector")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }
            }

            // Configuration Section
            SettingsSection(title: "Configuration") {
                VStack(spacing: 16) {
                    // Port selection
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                            Text("Server will run on this port")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        Spacer()

                        Picker("Port", selection: Binding(
                            get: { viewModel.settings.serverPort },
                            set: { newPort in
                                Task { await viewModel.updateServerPort(newPort) }
                            }
                        )) {
                            Text("8080").tag(8080)
                            Text("3000").tag(3000)
                            Text("5000").tag(5000)
                            Text("8000").tag(8000)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)

                    // Password field
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Authentication")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                Text("Password required for API access")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }

                            Spacer()

                            Button(action: {
                                Task {
                                    await viewModel.generateServerPassword()
                                }
                            }) {
                                Text("Generate")
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(AppColors.signalMercury)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(AppSurfaces.color(.controlBackground))
                                    )
                            }
                        }

                        HStack(spacing: 8) {
                            if showPasswordField {
                                TextField("Enter password", text: Binding(
                                    get: { viewModel.settings.serverPassword ?? "" },
                                    set: { newPassword in
                                        Task { await viewModel.updateServerPassword(newPassword.isEmpty ? nil : newPassword) }
                                    }
                                ))
                                .textFieldStyle(.plain)
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                            } else {
                                Text(viewModel.settings.serverPassword?.isEmpty ?? true ? "No password set" : String(repeating: "•", count: 16))
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(viewModel.settings.serverPassword?.isEmpty ?? true ? AppColors.textTertiary : AppColors.textPrimary)
                            }

                            Spacer()

                            // Copy button
                            if let password = viewModel.settings.serverPassword, !password.isEmpty {
                                Button(action: {
                                    AppClipboard.copy(password)
                                    copiedPassword = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copiedPassword = false
                                    }
                                }) {
                                    Image(systemName: copiedPassword ? "checkmark" : "doc.on.doc")
                                        .foregroundColor(AppColors.signalMercury)
                                }
                            }

                            // Show/Hide button
                            Button(action: { showPasswordField.toggle() }) {
                                Image(systemName: showPasswordField ? "eye.slash" : "eye")
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .padding()
                        .background(AppSurfaces.color(.controlBackground))
                        .cornerRadius(6)
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)

                    // External connections toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow External Connections")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                            Text("Listen on all network interfaces")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { viewModel.settings.serverAllowExternal },
                            set: { newValue in
                                Task { await viewModel.updateServerAllowExternal(newValue) }
                            }
                        ))
                        .tint(AppColors.signalMercury)
                    }
                    .padding()
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }
            }

            // Documentation Section
            SettingsSection(title: "API Compatibility") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This server implements OpenAI's chat completions API format, making it compatible with tools like:")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)

                    VStack(alignment: .leading, spacing: 8) {
                        CompatibilityRow(tool: "Cline", description: "VSCode AI assistant")
                        CompatibilityRow(tool: "Continue", description: "IDE extension")
                        CompatibilityRow(tool: "OpenAI SDK", description: "Official Python/Node clients")
                        CompatibilityRow(tool: "LangChain", description: "AI application framework")
                    }
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Computed Properties

    private var serverStatusText: String {
        if viewModel.serverError != nil {
            return "Error"
        } else if viewModel.isServerRunning {
            return "Running"
        } else {
            return "Stopped"
        }
    }

    private var serverStatusColor: Color {
        if viewModel.serverError != nil {
            return AppColors.accentError
        } else if viewModel.isServerRunning {
            return AppColors.accentSuccess
        } else {
            return AppColors.textTertiary
        }
    }

    private var exampleCurlCommand: String {
        let url = viewModel.serverLocalURL
        let password = viewModel.settings.serverPassword ?? "YOUR_PASSWORD"
        return """
        curl \(url)/v1/chat/completions \\
          -H "Authorization: Bearer \(password)" \\
          -H "Content-Type: application/json" \\
          -d '{"model": "claude-sonnet-4-5", "messages": [{"role": "user", "content": "Hello!"}]}'
        """
    }
}

// MARK: - Connection Info Row

struct ConnectionInfoRow: View {
    let icon: String
    let title: String
    let value: String
    @Binding var copied: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                    Text(value)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer()

                Button(action: {
                    AppClipboard.copy(value)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                            .font(AppTypography.bodySmall(.medium))
                    }
                    .foregroundColor(copied ? AppColors.accentSuccess : AppColors.signalMercury)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppSurfaces.color(.controlBackground))
                    )
                }
            }
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
}

// MARK: - Compatibility Row

struct CompatibilityRow: View {
    let tool: String
    let description: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.accentSuccess)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(tool)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                Text(description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ServerSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppSurfaces.color(.contentBackground))
}
