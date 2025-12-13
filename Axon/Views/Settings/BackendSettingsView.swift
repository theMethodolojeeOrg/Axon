//
//  BackendSettingsView.swift
//  Axon
//
//  Configuration for optional cloud backend (self-hosted or Firebase)
//

import SwiftUI

struct BackendSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var urlInput: String = ""
    @State private var tokenInput: String = ""
    @State private var showToken = false
    @State private var validationState: BackendURLValidation = .empty
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Status Section
            SettingsSection(title: "Backend Status") {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        // Status indicator
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusText)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text(statusDescription)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)

                    // Info about local-first mode
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(AppColors.signalMercury)
                        Text("Axon works fully offline. Backend is optional for cloud sync features.")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.horizontal)
                }
            }

            // URL Configuration
            SettingsSection(title: "Backend URL") {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cloud Functions URL")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        TextField("https://us-central1-your-project.cloudfunctions.net", text: $urlInput)
                            .textFieldStyle(.plain)
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.URL)
                            #endif
                            .padding()
                            .background(AppColors.substrateTertiary)
                            .cornerRadius(6)
                            .onChange(of: urlInput) { _, newValue in
                                validationState = BackendConfig.validateURL(newValue)
                            }

                        // Validation message
                        if let message = validationState.message {
                            HStack(spacing: 6) {
                                Image(systemName: validationIcon)
                                    .foregroundColor(validationColor)
                                Text(message)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(validationColor)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)

                    // Save button
                    HStack {
                        Spacer()

                        if urlInput != (viewModel.settings.backendAPIURL ?? "") {
                            Button(action: saveURL) {
                                Text("Save URL")
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(validationState.isUsable ? AppColors.signalMercury : AppColors.textTertiary)
                                    )
                            }
                            .disabled(!validationState.isUsable)
                        }

                        if viewModel.settings.backendAPIURL != nil {
                            Button(action: clearURL) {
                                Text("Clear")
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(AppColors.accentError)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppColors.accentError, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }

            // Auth Token (optional)
            SettingsSection(title: "Authentication (Optional)") {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auth Token")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Text("If your backend requires authentication")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)

                        HStack(spacing: 8) {
                            if showToken {
                                TextField("Bearer token", text: $tokenInput)
                                    .textFieldStyle(.plain)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    #endif
                            } else {
                                Text(tokenInput.isEmpty ? "No token set" : String(repeating: "•", count: min(tokenInput.count, 20)))
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(tokenInput.isEmpty ? AppColors.textTertiary : AppColors.textPrimary)
                            }

                            Spacer()

                            Button(action: { showToken.toggle() }) {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .padding()
                        .background(AppColors.substrateTertiary)
                        .cornerRadius(6)
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)

                    // Save token button
                    if tokenInput != (viewModel.settings.backendAuthToken ?? "") {
                        HStack {
                            Spacer()
                            Button(action: saveToken) {
                                Text("Save Token")
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(AppColors.signalMercury)
                                    )
                            }
                        }
                    }
                }
            }

            // Test Connection
            if viewModel.settings.backendAPIURL != nil {
                SettingsSection(title: "Connection Test") {
                    VStack(spacing: 12) {
                        Button(action: testConnection) {
                            HStack(spacing: 8) {
                                if isTestingConnection {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .foregroundColor(.white)
                                }
                                Text(isTestingConnection ? "Testing..." : "Test Connection")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(AppColors.signalMercury)
                            )
                        }
                        .disabled(isTestingConnection)

                        // Test result
                        if let result = connectionTestResult {
                            HStack(spacing: 8) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? AppColors.accentSuccess : AppColors.accentError)
                                Text(result.message)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(result.success ? AppColors.accentSuccess : AppColors.accentError)
                            }
                            .padding()
                            .background(AppColors.substrateSecondary)
                            .cornerRadius(8)
                        }
                    }
                }
            }

            // Info Section
            SettingsSection(title: "About Backend") {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(
                        icon: "server.rack",
                        title: "Self-Hosted",
                        description: "Point to your own Cloud Functions or compatible API"
                    )
                    InfoRow(
                        icon: "icloud",
                        title: "Cloud Sync",
                        description: "Enable conversation and memory sync across devices"
                    )
                    InfoRow(
                        icon: "lock.shield",
                        title: "Privacy First",
                        description: "Your data, your server, your control"
                    )
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }
        .onAppear {
            urlInput = viewModel.settings.backendAPIURL ?? ""
            tokenInput = viewModel.settings.backendAuthToken ?? ""
            validationState = BackendConfig.validateURL(urlInput)
        }
    }

    // MARK: - Computed Properties

    private var statusText: String {
        if viewModel.settings.backendAPIURL != nil {
            return "Backend Configured"
        } else {
            return "Local-Only Mode"
        }
    }

    private var statusDescription: String {
        if viewModel.settings.backendAPIURL != nil {
            return viewModel.settings.backendAPIURL ?? ""
        } else {
            return "All data stored locally on device"
        }
    }

    private var statusColor: Color {
        if viewModel.settings.backendAPIURL != nil {
            return AppColors.accentSuccess
        } else {
            return AppColors.signalMercury
        }
    }

    private var validationIcon: String {
        switch validationState {
        case .empty, .valid:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .invalid:
            return "xmark.circle"
        }
    }

    private var validationColor: Color {
        switch validationState {
        case .empty, .valid:
            return AppColors.accentSuccess
        case .warning:
            return AppColors.accentWarning
        case .invalid:
            return AppColors.accentError
        }
    }

    // MARK: - Actions

    private func saveURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await viewModel.updateBackendURL(trimmed.isEmpty ? nil : trimmed)
        }
    }

    private func clearURL() {
        urlInput = ""
        Task {
            await viewModel.updateBackendURL(nil)
        }
    }

    private func saveToken() {
        let trimmed = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await viewModel.updateBackendAuthToken(trimmed.isEmpty ? nil : trimmed)
        }
    }

    private func testConnection() {
        guard let urlString = viewModel.settings.backendAPIURL,
              let url = URL(string: urlString) else {
            return
        }

        isTestingConnection = true
        connectionTestResult = nil

        Task {
            do {
                var request = URLRequest(url: url.appendingPathComponent("health"))
                request.httpMethod = "GET"
                request.timeoutInterval = 10

                if let token = viewModel.settings.backendAuthToken, !token.isEmpty {
                    request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        connectionTestResult = ConnectionTestResult(success: true, message: "Connection successful!")
                    } else if httpResponse.statusCode == 404 {
                        // 404 is OK - means server is reachable but no health endpoint
                        connectionTestResult = ConnectionTestResult(success: true, message: "Server reachable (no health endpoint)")
                    } else {
                        connectionTestResult = ConnectionTestResult(success: false, message: "Server returned \(httpResponse.statusCode)")
                    }
                }
            } catch {
                connectionTestResult = ConnectionTestResult(success: false, message: error.localizedDescription)
            }

            isTestingConnection = false
        }
    }
}

// MARK: - Supporting Types

struct ConnectionTestResult {
    let success: Bool
    let message: String
}

struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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
        BackendSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
