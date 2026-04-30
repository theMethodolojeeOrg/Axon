//
//  AIPIdentitySection.swift
//  Axon
//
//  AIP Identity display and reset for testing.
//

import SwiftUI

struct AIPIdentitySection: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingAIPResetConfirmation = false
    @State private var isResettingAIP = false

    var body: some View {
        VStack(spacing: 0) {
            // Current identity display
            HStack {
                Image(systemName: "person.badge.key.fill")
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("BioID")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if let bioID = BioIDService.shared.currentBioID {
                        Text(bioID)
                            .font(AppTypography.code())
                            .foregroundColor(AppColors.signalMercury)
                    } else {
                        Text("Not enrolled")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()
            }
            .padding()

            Divider()
                .background(AppColors.divider)

            // Reset button
            Button(action: {
                showingAIPResetConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle")
                        .foregroundColor(AppColors.accentError)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset AIP Identity")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.accentError)
                        
                        Text("Clears BioID and zone for re-testing enrollment")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    if isResettingAIP {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
            }
            .disabled(isResettingAIP || BioIDService.shared.currentBioID == nil)
        }
        .cornerRadius(8)
        .alert("Reset AIP Identity?", isPresented: $showingAIPResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Identity", role: .destructive) {
                Task {
                    await resetAIPIdentity()
                }
            }
        } message: {
            Text("This will delete your BioID from keychain and reset the Data Zone status. CloudKit records will remain (delete manually in dashboard if needed).")
        }
    }

    // MARK: - Actions

    private func resetAIPIdentity() async {
        isResettingAIP = true

        do {
            // 1. Clear BioID from keychain
            try BioIDService.shared.resetIdentity()

            // 2. Reset zone status
            await UserDataZoneService.shared.resetZoneStatus()

            viewModel.showSuccessMessage("AIP identity cleared. You can now re-enroll.")
            print("[AIPIdentitySection] AIP identity reset complete")
        } catch {
            print("[AIPIdentitySection] Error resetting AIP identity: \(error)")
            viewModel.error = "Failed to reset AIP identity: \(error.localizedDescription)"
        }

        isResettingAIP = false
    }
}

#Preview {
    SettingsSection(title: "AIP Identity (Testing)") {
        AIPIdentitySection(viewModel: SettingsViewModel())
    }
    .background(AppSurfaces.color(.contentBackground))
}
