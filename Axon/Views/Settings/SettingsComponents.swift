//
//  SettingsComponents.swift
//  Axon
//
//  Shared components to keep Settings screens visually consistent.
//

import SwiftUI

/// General-style section used by Settings screens.
///
/// This intentionally matches the look/spacing used in `GeneralSettingsView`.
struct UnifiedSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTypography.headlineSmall())
                .foregroundColor(AppColors.textPrimary)

            content
        }
    }
}

/// A reusable “banner” card for short informational messages at the top of a settings screen.
struct SettingsInfoBanner: View {
    let icon: String
    let text: String
    var tint: Color = AppColors.signalMercury

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(tint)

            Text(text)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
        .background(tint.opacity(0.1))
        .cornerRadius(8)
    }
}

/// A consistent container card for setting blocks/rows.
struct SettingsCard<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
}
