//
//  MacDetailEmptyStateView.swift
//  Axon
//
//  Simple, centered empty state for macOS detail panes.
//

import SwiftUI

#if os(macOS)

struct MacDetailEmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let primaryActionTitle: String?
    let primaryAction: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        primaryActionTitle: String? = nil,
        primaryAction: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryAction = primaryAction
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .regular))
                .foregroundColor(AppColors.textTertiary)

            Text(title)
                .font(AppTypography.titleLarge())
                .foregroundColor(AppColors.textPrimary)

            Text(message)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let primaryActionTitle, let primaryAction {
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.signalMercury)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.substratePrimary)
    }
}

#Preview {
    MacDetailEmptyStateView(
        icon: "bubble.left.and.bubble.right",
        title: "No Chat Selected",
        message: "Choose a conversation from the sidebar, or start a new one.",
        primaryActionTitle: "New Chat",
        primaryAction: {}
    )
}

#endif
