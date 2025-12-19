//
//  ToolApprovalView.swift
//  Axon
//
//  UI components for biometric tool approval in chat messages.
//  Displays approval requests and signed approval badges.
//

import SwiftUI
import Combine

// MARK: - Tool Approval Request View

/// Inline approval request shown in chat when a tool needs biometric authorization
struct ToolApprovalRequestView: View {
    let approval: PendingToolApproval
    let onApprove: () async -> Void
    let onApproveForSession: () async -> Void
    let onDeny: () -> Void
    let onStop: () -> Void

    @State private var isAuthenticating = false
    @State private var isExpanded = true
    @EnvironmentObject var biometricService: BiometricAuthService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.signalHematite)

                    Text("Approval Required")
                        .font(AppTypography.titleSmall())
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(AppColors.signalHematite.opacity(0.1))
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Tool info
                    HStack(spacing: 10) {
                        Image(systemName: approval.tool.icon)
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32, height: 32)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(approval.tool.name)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text(approval.tool.description)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                    }

                    // Scopes - what the tool will access
                    if !approval.resolvedScopes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This tool will:")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)

                            ForEach(approval.resolvedScopes, id: \.self) { scope in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppColors.signalLichen)

                                    Text(scope)
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(AppColors.substrateTertiary)
                        .cornerRadius(8)
                    }

                    // Input preview (if any)
                    if !approval.displayInputs.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(approval.displayInputs.keys.sorted()), id: \.self) { key in
                                    HStack(alignment: .top) {
                                        Text(key + ":")
                                            .font(AppTypography.labelSmall())
                                            .foregroundColor(AppColors.textTertiary)
                                            .frame(width: 80, alignment: .leading)

                                        Text(approval.displayInputs[key] ?? "")
                                            .font(AppTypography.bodySmall())
                                            .foregroundColor(AppColors.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        } label: {
                            Text("Parameters")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .tint(AppColors.textTertiary)
                    }

                    Divider()
                        .background(AppColors.divider)

                    // Claude Code-style action buttons
                    VStack(spacing: 8) {
                        // Primary row: Allow Once / Allow for Session
                        HStack(spacing: 8) {
                            // Allow Once button
                            Button {
                                Task {
                                    isAuthenticating = true
                                    await onApprove()
                                    isAuthenticating = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if isAuthenticating {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: biometricService.biometricType.icon)
                                            .font(.system(size: 14))
                                    }
                                    Text("Allow Once")
                                        .font(AppTypography.bodySmall(.medium))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppColors.signalMercury)
                                .cornerRadius(8)
                            }
                            .disabled(isAuthenticating)

                            // Allow for Session button
                            Button {
                                Task {
                                    isAuthenticating = true
                                    await onApproveForSession()
                                    isAuthenticating = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                    Text("Allow for Session")
                                        .font(AppTypography.bodySmall(.medium))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppColors.signalLichen)
                                .cornerRadius(8)
                            }
                            .disabled(isAuthenticating)
                        }

                        // Secondary row: Deny / Stop
                        HStack(spacing: 8) {
                            // Deny button
                            Button(action: onDeny) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Deny")
                                        .font(AppTypography.bodySmall(.medium))
                                }
                                .foregroundColor(AppColors.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppColors.substrateTertiary)
                                .cornerRadius(8)
                            }
                            .disabled(isAuthenticating)

                            // Stop button (stops all tool execution)
                            Button(action: onStop) {
                                HStack(spacing: 6) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 10))
                                    Text("Stop")
                                        .font(AppTypography.bodySmall(.medium))
                                }
                                .foregroundColor(AppColors.signalHematite)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppColors.signalHematite.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .disabled(isAuthenticating)
                        }
                    }

                    // Timeout indicator
                    if !approval.isExpired {
                        TimeoutIndicator(
                            startTime: approval.requestedAt,
                            timeoutSeconds: approval.timeoutSeconds
                        )
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.signalHematite.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Timeout Indicator

private struct TimeoutIndicator: View {
    let startTime: Date
    let timeoutSeconds: Int

    @State private var remainingSeconds: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.system(size: 10))

            Text("Expires in \(formatTime(remainingSeconds))")
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(remainingSeconds < 30 ? AppColors.signalHematite : AppColors.textTertiary)
        .onAppear {
            updateRemaining()
        }
        .onReceive(timer) { _ in
            updateRemaining()
        }
    }

    private func updateRemaining() {
        let elapsed = Int(Date().timeIntervalSince(startTime))
        remainingSeconds = max(0, timeoutSeconds - elapsed)
    }

    private func formatTime(_ seconds: Int) -> String {
        if seconds >= 60 {
            let minutes = seconds / 60
            let secs = seconds % 60
            return "\(minutes):\(String(format: "%02d", secs))"
        }
        return "\(seconds)s"
    }
}

// MARK: - Tool Approval Badge (Compact)

/// Compact badge shown after a tool has been approved
struct ToolApprovalBadge: View {
    let record: ToolApprovalRecord
    @State private var showDetails = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                showDetails.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.signalLichen)

                Text("Approved")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalLichen)

                Text("•")
                    .foregroundColor(AppColors.textTertiary)

                Text(record.formattedTime)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.signalLichen.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetails) {
            ToolApprovalDetailSheet(record: record)
        }
    }
}

// MARK: - Tool Approval Detail Sheet

struct ToolApprovalDetailSheet: View {
    let record: ToolApprovalRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with checkmark
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 48))
                                .foregroundColor(AppColors.signalLichen)

                            Text("Tool Approved")
                                .font(AppTypography.titleMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text(record.formattedDateTime)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.top, 20)

                    Divider()

                    // Tool info
                    DetailSection(title: "Tool") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.toolName)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text(record.toolId)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    // Scopes
                    if !record.scopes.isEmpty {
                        DetailSection(title: "Authorized Actions") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(record.scopes, id: \.self) { scope in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.signalLichen)

                                        Text(scope)
                                            .font(AppTypography.bodySmall())
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    // Authentication method
                    DetailSection(title: "Authentication") {
                        HStack(spacing: 8) {
                            Image(systemName: biometricIcon(for: record.biometricType))
                                .font(.system(size: 16))
                                .foregroundColor(AppColors.signalMercury)

                            Text(biometricDisplayName(for: record.biometricType))
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    // Device info
                    DetailSection(title: "Device") {
                        Text("ID: \(record.deviceShortId)...")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    // Cryptographic signature
                    DetailSection(title: "Signature") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("This cryptographic signature proves the tool was authorized by the device owner at the specified time.")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textTertiary)

                            Text(record.signature)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(AppColors.textSecondary)
                                .textSelection(.enabled)
                                .padding(10)
                                .background(AppColors.substrateTertiary)
                                .cornerRadius(8)

                            Button {
                                AppClipboard.copy(record.signature)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 12))
                                    Text("Copy Signature")
                                        .font(AppTypography.labelSmall())
                                }
                                .foregroundColor(AppColors.signalMercury)
                            }
                        }
                    }

                    // Parameters
                    if !record.inputs.isEmpty {
                        DetailSection(title: "Parameters") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(record.inputs.keys.sorted()), id: \.self) { key in
                                    HStack(alignment: .top) {
                                        Text(key + ":")
                                            .font(AppTypography.labelSmall())
                                            .foregroundColor(AppColors.textTertiary)
                                            .frame(width: 100, alignment: .leading)

                                        Text(record.inputs[key] ?? "")
                                            .font(AppTypography.bodySmall())
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.substratePrimary)
            .navigationTitle("Approval Details")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 450, idealWidth: 500, minHeight: 500, idealHeight: 600)
        #endif
    }

    private func biometricIcon(for type: String) -> String {
        switch type {
        case "faceID": return "faceid"
        case "touchID": return "touchid"
        case "opticID": return "opticid"
        default: return "lock.fill"
        }
    }

    private func biometricDisplayName(for type: String) -> String {
        switch type {
        case "faceID": return "Face ID"
        case "touchID": return "Touch ID"
        case "opticID": return "Optic ID"
        default: return "Passcode"
        }
    }
}

// MARK: - Detail Section

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

            content
        }
    }
}

// MARK: - Expired Approval View

/// Shown when an approval request has expired
struct ToolApprovalExpiredView: View {
    let toolName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalHematite)

            Text("Approval expired for \(toolName)")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.signalHematite.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Denied Approval View

/// Shown when a tool was denied
struct ToolApprovalDeniedView: View {
    let toolName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalHematite)

            Text("\(toolName) was not authorized")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.signalHematite.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Stopped View

/// Shown when the user stopped all tool execution
struct ToolApprovalStoppedView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "stop.fill")
                .font(.system(size: 12))
                .foregroundColor(AppColors.signalHematite)

            Text("Tool execution stopped")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.signalHematite.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Session Approval Badge

/// Compact badge shown when a tool was auto-approved via session
struct ToolSessionApprovalBadge: View {
    let record: ToolApprovalRecord

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(AppColors.signalLichen)

            Text("Session Approved")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.signalLichen)

            Text("•")
                .foregroundColor(AppColors.textTertiary)

            Text(record.formattedTime)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppColors.signalLichen.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Pending approval
        ToolApprovalRequestView(
            approval: PendingToolApproval(
                id: UUID(),
                tool: DynamicToolConfig(
                    id: "jules-create-task",
                    name: "Create Jules Task",
                    description: "Assign a coding task to Google Jules AI agent",
                    category: .integration,
                    enabled: true,
                    icon: "figure.wave",
                    requiredSecrets: ["jules_api_key"],
                    pipeline: [],
                    parameters: [:],
                    requiresApproval: true,
                    approvalScopes: ["Create tasks in GitHub repositories", "Access repository: owner/repo"]
                ),
                inputs: ["task_description": "Fix the login bug", "repo_source": "sources/github/owner/repo"],
                resolvedScopes: ["Create tasks in GitHub repositories", "Access repository: owner/repo"],
                requestedAt: Date(),
                timeoutSeconds: 300
            ),
            onApprove: {},
            onApproveForSession: {},
            onDeny: {},
            onStop: {}
        )
        .environmentObject(BiometricAuthService.shared)

        // Approved badge
        ToolApprovalBadge(
            record: ToolApprovalRecord(
                id: UUID(),
                toolId: "jules-create-task",
                toolName: "Create Jules Task",
                inputs: ["task_description": "Fix the login bug"],
                scopes: ["Create tasks in GitHub repositories"],
                approvedAt: Date(),
                deviceId: "abc123def456",
                deviceShortId: "abc123de",
                signature: "QWJjMTIzRGVmNDU2R2hpNzg5SnVsTW5PcFFyU3R1Vnd4WXo=",
                biometricType: "faceID"
            )
        )

        // Expired
        ToolApprovalExpiredView(toolName: "Create Jules Task")

        // Denied
        ToolApprovalDeniedView(toolName: "Create Jules Task")
    }
    .padding()
    .background(AppColors.substratePrimary)
}
