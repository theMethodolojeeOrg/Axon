//
//  SharedUIElements.swift
//  Axon
//
//  Shared UI components used across multiple views.
//

import SwiftUI

// MARK: - Covenant Restriction Banner

/// A banner that displays when an action is restricted by the covenant.
/// Shows the restriction reason and optionally provides a renegotiation action.
struct CovenantRestrictionBanner: View {
    let icon: String
    let message: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Lock icon
            ZStack {
                Circle()
                    .fill(AppColors.accentWarning.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.accentWarning)
            }

            // Message
            VStack(alignment: .leading, spacing: 4) {
                Text("Restricted by Covenant")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.accentWarning)

                Text(message)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Optional action button
            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(AppTypography.labelSmall(.medium))
                        .foregroundColor(AppColors.accentWarning)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.accentWarning, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.accentWarning.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.accentWarning.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview("Covenant Banner") {
    VStack {
        CovenantRestrictionBanner(
            icon: "lock.shield",
            message: "This action requires mutual consent"
        )

        CovenantRestrictionBanner(
            icon: "lock.shield",
            message: "Memory deletion is restricted",
            actionLabel: "Renegotiate",
            action: {}
        )
    }
    .padding()
    .background(AppColors.substratePrimary)
}
