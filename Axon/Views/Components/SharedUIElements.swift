//
//  SharedUIElements.swift
//  Axon
//
//  Shared UI components used across multiple settings views.
//

import SwiftUI

// MARK: - Settings Toggle Row

/// A reusable toggle row for settings views.
/// Supports both simple (title + icon) and extended (with subtitle and custom icon color) variants.
struct SettingsToggleRow: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var iconColor: Color? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: subtitle != nil ? 16 : 12) {
            // Icon with optional colored background
            if subtitle != nil {
                ZStack {
                    Circle()
                        .fill((iconColor ?? AppColors.signalMercury).opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor ?? AppColors.signalMercury)
                }
            } else {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor ?? AppColors.signalMercury)
                    .frame(width: 32)
            }

            // Title and optional subtitle
            VStack(alignment: .leading, spacing: subtitle != nil ? 4 : 0) {
                Text(title)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColors.signalMercury)
        }
        .padding(subtitle != nil ? 16 : 12)
        .background(subtitle != nil ? Color.clear : AppColors.substrateSecondary)
        .cornerRadius(subtitle != nil ? 0 : 8)
    }
}

// MARK: - Preview

#Preview("Simple Toggle") {
    VStack {
        SettingsToggleRow(
            title: "Enable Feature",
            icon: "star.fill",
            isOn: .constant(true)
        )

        SettingsToggleRow(
            title: "Another Feature",
            icon: "gear",
            isOn: .constant(false)
        )
    }
    .padding()
    .background(AppColors.substratePrimary)
}

#Preview("Extended Toggle") {
    VStack(spacing: 0) {
        SettingsToggleRow(
            title: "Enable Co-Sovereignty",
            icon: "shield.checkered",
            subtitle: "Require mutual consent for significant changes",
            iconColor: .blue,
            isOn: .constant(true)
        )

        Divider()

        SettingsToggleRow(
            title: "Audit Logging",
            icon: "doc.text.magnifyingglass",
            subtitle: "Log all consent decisions for review",
            iconColor: .green,
            isOn: .constant(false)
        )
    }
    .background(AppColors.substrateSecondary)
    .cornerRadius(12)
    .padding()
    .background(AppColors.substratePrimary)
}
