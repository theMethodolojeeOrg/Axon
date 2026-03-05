//
//  QuickActionsRow.swift
//  Axon
//
//  Quick action buttons for enabling/disabling all log categories.
//

import SwiftUI

struct QuickActionsRow: View {
    let onEnableAll: () -> Void
    let onDisableAll: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEnableAll) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Enable All")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.signalLichen)
            }
            .buttonStyle(.plain)

            Button(action: onDisableAll) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Disable All")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(AppColors.substrateTertiary.opacity(0.5))
    }
}

#Preview {
    QuickActionsRow(
        onEnableAll: {},
        onDisableAll: {}
    )
}
