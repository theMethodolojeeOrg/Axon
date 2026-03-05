//
//  PortApprovalView.swift
//  Axon
//
//  Approval sheet for external app invocations.
//  Shows what app/action will be invoked and allows user to approve.
//

import SwiftUI

struct PortApprovalView: View {
    @StateObject private var invocationService = ShortcutInvocationService.shared
    @StateObject private var portRegistry = PortRegistry.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let request = invocationService.pendingRequest {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: request.port.icon)
                        .font(.system(size: 40))
                        .foregroundColor(AppColors.signalMercury)

                    Text("Open External App")
                        .font(AppTypography.displayMedium())
                        .foregroundColor(AppColors.textPrimary)

                    Text("Axon wants to open \(request.port.appName)")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.top)

                // Action details
                VStack(alignment: .leading, spacing: 16) {
                    DetailRow(label: "Action", value: request.port.name)
                    DetailRow(label: "App", value: request.port.appName)

                    if !request.parameters.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PARAMETERS")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)

                            ForEach(Array(request.parameters.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                                HStack(alignment: .top) {
                                    Text(key)
                                        .font(AppTypography.bodySmall(.medium))
                                        .foregroundColor(AppColors.textSecondary)
                                        .frame(width: 80, alignment: .leading)

                                    Text(value)
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(3)

                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(10)
                    }

                    // URL preview
                    if let url = request.port.generateUrl(with: request.parameters) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)

                            Text(url.absoluteString)
                                .font(AppTypography.codeSmall())
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Approve for session
                    Button(action: {
                        Task {
                            invocationService.approveForSession()
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                            Text("Approve for Session")
                        }
                        .font(AppTypography.bodyMedium(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.signalMercury)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }

                    // One-time approve
                    Button(action: {
                        Task {
                            invocationService.approve()
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Approve Once")
                        }
                        .font(AppTypography.bodyMedium(.medium))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .foregroundColor(AppColors.textPrimary)
                        .cornerRadius(10)
                    }

                    // Deny
                    Button(action: {
                        invocationService.deny()
                    }) {
                        Text("Deny")
                            .font(AppTypography.bodyMedium(.medium))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.clear)
                            .foregroundColor(AppColors.accentWarning)
                    }
                }
                .padding()
            }
            .background(AppColors.substratePrimary)
        } else {
            // No pending request
            VStack {
                Text("No pending request")
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.substratePrimary)
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)

            Spacer()
        }
    }
}

// MARK: - Inline Port Approval View (for chat)

struct InlinePortApprovalView: View {
    @StateObject private var invocationService = ShortcutInvocationService.shared

    var body: some View {
        if let request = invocationService.pendingRequest {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: request.port.icon)
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.signalMercury)

                    Text("Open \(request.port.appName)")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Text(request.port.invocationType.displayName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(4)
                }

                // Action description
                Text(request.port.name)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                // Parameters preview
                if !request.parameters.isEmpty {
                    let previewParams = request.parameters.prefix(3)
                    HStack(spacing: 8) {
                        ForEach(Array(previewParams), id: \.key) { key, value in
                            Text("\(key): \(value.prefix(20))\(value.count > 20 ? "..." : "")")
                                .font(AppTypography.codeSmall())
                                .foregroundColor(AppColors.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColors.substratePrimary)
                                .cornerRadius(4)
                        }
                    }
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button(action: {
                        Task {
                            invocationService.approveForSession()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 12))
                            Text("Session")
                        }
                        .font(AppTypography.labelSmall())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.signalMercury)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }

                    Button(action: {
                        Task {
                            invocationService.approve()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12))
                            Text("Once")
                        }
                        .font(AppTypography.labelSmall())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.substrateSecondary)
                        .foregroundColor(AppColors.textPrimary)
                        .cornerRadius(6)
                    }

                    Button(action: {
                        invocationService.deny()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                            Text("Deny")
                        }
                        .font(AppTypography.labelSmall())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.clear)
                        .foregroundColor(AppColors.accentWarning)
                        .cornerRadius(6)
                    }

                    Spacer()
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(12)
        }
    }
}

// MARK: - Preview

#Preview("Full Sheet") {
    PortApprovalView()
}

#Preview("Inline") {
    InlinePortApprovalView()
        .padding()
        .background(AppColors.substratePrimary)
}
