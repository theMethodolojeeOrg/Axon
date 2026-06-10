//
//  AdvancedSection.swift
//  Axon
//
//  Section with advanced options like reset to defaults.
//

import SwiftUI

struct AdvancedSection: View {
    let onReset: () -> Void

    @State private var showingResetConfirmation = false

    var body: some View {
        UnifiedSettingsSection(title: "Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(AppTypography.bodyMedium())
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accentError)

                Text("This reloads the current AxonProviderKit model catalog snapshot.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .alert("Reset to Defaults?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                onReset()
            }
        } message: {
            Text("This will reload the ProviderKit catalog used for built-in providers. Custom providers are not changed.")
        }
    }
}
