//
//  GenerativeUISection.swift
//  Axon
//
//  Section linking to the Generative UI Sandbox.
//

import SwiftUI

struct GenerativeUISection: View {
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: GenerativeUITestView()) {
                HStack {
                    Image(systemName: "rectangle.3.group")
                        .foregroundColor(AppColors.signalLichen)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Generative UI Sandbox")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Test JSON-driven UI rendering")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            Divider()
                .background(AppColors.divider)

            // Info about what the sandbox does
            VStack(alignment: .leading, spacing: 8) {
                Text("Test the experimental generative UI system:")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    SettingsFeatureRow(icon: "curlybraces", text: "Edit JSON layouts in real-time", iconColor: AppColors.signalLichen)
                    SettingsFeatureRow(icon: "eye", text: "See live preview of rendered UI", iconColor: AppColors.signalLichen)
                    SettingsFeatureRow(icon: "square.stack.3d.up", text: "VStack, HStack, Text, Button, Image", iconColor: AppColors.signalLichen)
                }
            }
            .padding()
        }
        .cornerRadius(8)
    }
}

#Preview {
    SettingsSection(title: "Generative UI") {
        GenerativeUISection()
    }
    .background(AppColors.substratePrimary)
}
