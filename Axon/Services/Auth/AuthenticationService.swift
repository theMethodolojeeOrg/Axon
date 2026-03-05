//
//  AuthenticationService.swift
//  Axon
//
//  Authentication Service (Optional - only active if backend is configured)
//  In local-first mode, this service is dormant and all auth methods are no-ops
//

import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth

@MainActor
class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()

    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: AuthError?
    @Published var authToken: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    /// Whether Firebase has been initialized
    private var isFirebaseInitialized = false

    /// Check if auth service is available (Firebase initialized)
    var isAvailable: Bool { isFirebaseInitialized }

    override private init() {
        super.init()
        // Don't setup Firebase listener on init - wait until explicitly needed
        // This allows the app to run without Firebase configured
    }

    // MARK: - Firebase Initialization (Lazy)

    /// Initialize Firebase if not already done
    /// Call this only when user explicitly wants to use cloud features
    func initializeFirebaseIfNeeded() {
        guard !isFirebaseInitialized else { return }

        // Check if Firebase is already configured
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            print("[AuthService] Firebase configured")
        }

        isFirebaseInitialized = true
        setupAuthStateListener()
    }

    // MARK: - Setup

    private func setupAuthStateListener() {
        guard isFirebaseInitialized else { return }

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil

                // Refresh ID token when user changes
                if let user = user {
                    do {
                        let token = try await user.getIDToken(forcingRefresh: true)
                        self?.authToken = token
                        try? SecureTokenStorage.shared.saveIdToken(token)
                    } catch {
                        print("[AuthService] Error getting ID token: \(error.localizedDescription)")
                    }
                } else {
                    // Clear stored token when user signs out
                    try? SecureTokenStorage.shared.deleteIdToken()
                }
            }
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async throws {
        guard isFirebaseInitialized else {
            throw AuthError.notAuthenticated
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let authResult = try await Auth.auth().createUser(
                withEmail: email,
                password: password
            )

            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()

            self.user = authResult.user
            self.isAuthenticated = true

            print("[AuthService] User signed up successfully: \(authResult.user.uid)")
        } catch {
            let authError = AuthError.signUpFailed(error.localizedDescription)
            self.error = authError
            throw authError
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws {
        guard isFirebaseInitialized else {
            throw AuthError.notAuthenticated
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let authResult = try await Auth.auth().signIn(
                withEmail: email,
                password: password
            )

            self.user = authResult.user
            self.isAuthenticated = true

            // Refresh token
            let token = try await authResult.user.getIDToken(forcingRefresh: true)
            self.authToken = token
            try? SecureTokenStorage.shared.saveIdToken(token)

            print("[AuthService] User signed in successfully: \(authResult.user.uid)")
        } catch {
            let authError = AuthError.signInFailed(error.localizedDescription)
            self.error = authError
            throw authError
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        guard isFirebaseInitialized else { return }

        do {
            try Auth.auth().signOut()
            self.user = nil
            self.isAuthenticated = false
            self.authToken = nil
            self.error = nil

            // Clear stored tokens
            try? SecureTokenStorage.shared.clearAll()

            print("[AuthService] User signed out successfully")
        } catch {
            let authError = AuthError.signOutFailed(error.localizedDescription)
            self.error = authError
            throw authError
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        guard isFirebaseInitialized else {
            throw AuthError.notAuthenticated
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            print("[AuthService] Password reset email sent to: \(email)")
        } catch {
            let authError = AuthError.resetPasswordFailed(error.localizedDescription)
            self.error = authError
            throw authError
        }
    }

    // MARK: - Token Management

    func refreshToken() async throws -> String {
        guard isFirebaseInitialized else {
            throw AuthError.notAuthenticated
        }

        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }

        let token = try await user.getIDToken(forcingRefresh: true)
        self.authToken = token
        try? SecureTokenStorage.shared.saveIdToken(token)
        return token
    }

    func getIdToken() async throws -> String {
        guard isFirebaseInitialized else {
            throw AuthError.notAuthenticated
        }

        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }

        return try await user.getIDToken(forcingRefresh: false)
    }

    // MARK: - User Info

    var userId: String? {
        return user?.uid
    }

    var userEmail: String? {
        return user?.email
    }

    var displayName: String? {
        return user?.displayName
    }

    // MARK: - Cleanup

    deinit {
        if isFirebaseInitialized, let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notAuthenticated
    case signUpFailed(String)
    case signInFailed(String)
    case signOutFailed(String)
    case resetPasswordFailed(String)
    case tokenRefreshFailed(String)
    case invalidCredentials
    case userAlreadyExists
    case networkError
    case firebaseNotInitialized

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .signUpFailed(let message):
            return "Sign up failed: \(message)"
        case .signInFailed(let message):
            return "Sign in failed: \(message)"
        case .signOutFailed(let message):
            return "Sign out failed: \(message)"
        case .resetPasswordFailed(let message):
            return "Password reset failed: \(message)"
        case .tokenRefreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .invalidCredentials:
            return "Invalid email or password"
        case .userAlreadyExists:
            return "User with this email already exists"
        case .networkError:
            return "Network connection error"
        case .firebaseNotInitialized:
            return "Authentication service not available. Configure a backend first."
        }
    }
}
