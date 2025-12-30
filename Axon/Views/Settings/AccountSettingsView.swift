//
//  AccountSettingsView.swift
//  Axon
//
//  User account and profile management
//

import SwiftUI
import FirebaseAuth

struct AccountSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var bioIDService = BioIDService.shared
    @StateObject private var userDataZoneService = UserDataZoneService.shared

    @State private var showingPasswordReset = false
    @State private var showingSignOutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isSettingUpAIP = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Profile Section
            SettingsSection(title: "Profile") {
                VStack(spacing: 16) {
                    // Profile Picture
                    HStack {
                        Image("AxonLogoTemplate")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .foregroundColor(AppColors.signalMercury)

                        Spacer()
                    }
                    .padding(.bottom, 8)

                    Divider()
                        .background(AppColors.divider)

                    // Display Name
                    if let displayName = authService.displayName {
                        HStack {
                            Text("Display Name")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            Text(displayName)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    // Email
                    if let email = authService.user?.email {
                        HStack {
                            Text("Email")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            Text(email)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    // User ID
                    if let userId = authService.user?.uid {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("User ID")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textSecondary)

                            Text(userId)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
            
            // AIP Identity Section
            SettingsSection(title: "AIP Identity") {
                VStack(spacing: 16) {
                    if let bioID = bioIDService.currentBioID {
                        // BioID Display
                        HStack {
                            Text("BioID")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textSecondary)
                            
                            Spacer()
                            
                            Text(bioID)
                                .font(AppTypography.code())
                                .foregroundColor(AppColors.signalMercury)
                        }
                        
                        Divider()
                            .background(AppColors.divider)
                        
                        // AIP Address
                        if let displayName = authService.displayName {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AIP Address")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textSecondary)
                                
                                Text("ai://axon/\(displayName.lowercased()).\(bioID)/*")
                                    .font(AppTypography.code())
                                    .foregroundColor(AppColors.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        
                        Divider()
                            .background(AppColors.divider)
                        
                        // Zone Status
                        HStack {
                            Text("Data Zone")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textSecondary)
                            
                            Spacer()
                            
                            if userDataZoneService.isZoneReady {
                                Label("Ready", systemImage: "checkmark.circle.fill")
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(AppColors.accentSuccess)
                            } else {
                                Text("Not Configured")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    } else {
                        // Setup BioID
                        VStack(spacing: 12) {
                            Text("Set up your sovereign AI identity")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                Task {
                                    await setupAIPIdentity()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "faceid")
                                        .font(.system(size: 18))
                                    Text("Enroll with Biometrics")
                                        .font(AppTypography.bodyMedium(.medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(AppColors.signalMercury)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isSettingUpAIP)
                            
                            if isSettingUpAIP {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // Security Section
            SettingsSection(title: "Security") {
                VStack(spacing: 0) {
                    Button(action: {
                        showingPasswordReset = true
                    }) {
                        HStack {
                            Image(systemName: "lock.rotation")
                                .foregroundColor(AppColors.signalMercury)
                                .frame(width: 32)

                            Text("Change Password")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .padding()
                        .background(AppColors.substrateSecondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .cornerRadius(8)
            }

            // Account Actions Section
            SettingsSection(title: "Account Actions") {
                VStack(spacing: 12) {
                    // Sign Out
                    Button(action: {
                        showingSignOutConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(AppColors.signalMercury)
                                .frame(width: 32)

                            Text("Sign Out")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)

                            Spacer()
                        }
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Delete Account
                    Button(action: {
                        showingDeleteAccountConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(AppColors.accentError)
                                .frame(width: 32)

                            Text("Delete Account")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.accentError)

                            Spacer()
                        }
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // App Version
            HStack {
                Spacer()

                VStack(spacing: 4) {
                    Text("Axon")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textTertiary)

                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                        Text("Version \(version) (\(build))")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                Spacer()
            }
            .padding(.top, 16)
        }
        .alert("Reset Password", isPresented: $showingPasswordReset) {
            Button("Cancel", role: .cancel) {}
            Button("Send Reset Email") {
                Task {
                    await sendPasswordResetEmail()
                }
            }
        } message: {
            Text("A password reset link will be sent to your email address.")
        }
        .alert("Sign Out", isPresented: $showingSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await deleteAccount()
                }
            }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
    }

    // MARK: - Actions

    private func sendPasswordResetEmail() async {
        guard let email = authService.user?.email else {
            viewModel.error = "No email address found"
            return
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                Auth.auth().sendPasswordReset(withEmail: email) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            viewModel.showSuccessMessage("Password reset email sent to \(email)")
        } catch {
            viewModel.error = "Failed to send password reset email: \(error.localizedDescription)"
        }
    }

    private func signOut() async {
        do {
            try authService.signOut()
            viewModel.showSuccessMessage("Signed out successfully")
        } catch {
            viewModel.error = "Failed to sign out: \(error.localizedDescription)"
        }
    }

    private func deleteAccount() async {
        // TODO: Implement account deletion
        // This should call a backend endpoint to delete all user data
        // and then delete the Firebase Auth account
        viewModel.error = "Account deletion not yet implemented"
    }
    
    private func setupAIPIdentity() async {
        isSettingUpAIP = true
        defer { isSettingUpAIP = false }
        
        do {
            // 1. Generate or retrieve BioID
            let bioID = try await bioIDService.ensureIdentity()
            
            // 2. Get display name for the AIP address
            guard let displayName = authService.displayName else {
                viewModel.error = "Please set a display name before setting up AIP identity"
                return
            }
            
            // 3. Bootstrap the shared CloudKit zone
            let shareURL = try await userDataZoneService.bootstrapSharedZone(
                bioID: bioID,
                displayName: displayName.lowercased()
            )
            
            viewModel.showSuccessMessage("AIP identity created: ai://axon/\(displayName.lowercased()).\(bioID)/*")
            print("[AccountSettings] Share URL: \(shareURL)")
        } catch {
            viewModel.error = "Failed to set up AIP identity: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        AccountSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
