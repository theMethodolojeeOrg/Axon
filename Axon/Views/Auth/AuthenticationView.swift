//
//  AuthenticationView.swift
//  Axon
//
//  Authentication screen with sign in and sign up
//

import SwiftUI

struct AuthenticationView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Background
            AppColors.substratePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Logo and title
                    VStack(spacing: 16) {
                        Image("AxonMercury")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .shadow(color: AppColors.shadow, radius: 8, x: 0, y: 4)

                        Text("Axon")
                            .font(AppTypography.displaySmall())
                            .foregroundColor(AppColors.textPrimary)

                        Text("Memory-Augmented AI Chat")
                            .font(AppTypography.bodyLarge())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.top, 60)

                    // Auth form
                    AxonCard(padding: 24) {
                        VStack(spacing: 24) {
                            // Toggle between sign in and sign up
                            Picker("", selection: $isSignUp) {
                                Text("Sign In").tag(false)
                                Text("Sign Up").tag(true)
                            }
                            .pickerStyle(SegmentedPickerStyle())

                            // Display name field (only for sign up)
                            if isSignUp {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Display Name")
                                        .font(AppTypography.labelMedium())
                                        .foregroundColor(AppColors.textSecondary)

                                    TextField("Enter your name", text: $displayName)
                                        .textFieldStyle(AppTextFieldStyle())
                                        #if os(iOS)
                                        .textInputAutocapitalization(.words)
                                        #endif
                                        .disabled(authService.isLoading)
                                }
                                .transition(AppAnimations.slideFromTop)
                            }

                            // Email field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textSecondary)

                                TextField("Enter your email", text: $email)
                                    .textFieldStyle(AppTextFieldStyle())
                                    .textContentType(.emailAddress)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.emailAddress)
                                    #endif
                                    .disabled(authService.isLoading)
                            }

                            // Password field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(AppTypography.labelMedium())
                                    .foregroundColor(AppColors.textSecondary)

                                SecureField("Enter your password", text: $password)
                                    .textFieldStyle(AppTextFieldStyle())
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .disabled(authService.isLoading)
                            }

                            // Action button
                            Button(action: handleAuth) {
                                HStack {
                                    if authService.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Text(isSignUp ? "Create Account" : "Sign In")
                                            .font(AppTypography.titleMedium())
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColors.signalMercury)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(authService.isLoading || !isFormValid)
                            .opacity(isFormValid ? 1.0 : 0.5)
                        }
                    }

                    // Error message
                    if showError {
                        AxonCard(padding: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(AppColors.accentError)

                                Text(errorMessage)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textPrimary)

                                Spacer()

                                Button(action: { showError = false }) {
                                    Image(systemName: "xmark")
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                        .transition(AppAnimations.slideFromTop)
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
        }
        .animation(AppAnimations.standardEasing, value: isSignUp)
        .animation(AppAnimations.standardEasing, value: showError)
    }

    private var isFormValid: Bool {
        if isSignUp {
            return !email.isEmpty && !password.isEmpty && !displayName.isEmpty && password.count >= 6
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }

    private func handleAuth() {
        showError = false

        Task {
            do {
                if isSignUp {
                    try await authService.signUp(
                        email: email,
                        password: password,
                        displayName: displayName
                    )
                } else {
                    try await authService.signIn(
                        email: email,
                        password: password
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Custom Text Field Style

struct AppTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
            .foregroundColor(AppColors.textPrimary)
            .font(AppTypography.bodyMedium())
    }
}

// MARK: - Preview

#Preview {
    AuthenticationView()
}
