//
//  BiometricAuthService.swift
//  Axon
//
//  On-device biometric authentication service for FaceID/TouchID/Passcode
//

import Foundation
import LocalAuthentication
import Combine

/// Biometric capability types
enum BiometricType: String, Codable {
    case none = "none"
    case touchID = "touchID"
    case faceID = "faceID"
    case opticID = "opticID"  // Vision Pro

    var displayName: String {
        switch self {
        case .none: return "None"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    var icon: String {
        switch self {
        case .none: return "lock.slash"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

/// Authentication result
enum AuthenticationResult {
    case success
    case failed(BiometricError)
    case cancelled
    case fallback  // User chose passcode fallback
}

/// Biometric authentication errors
enum BiometricError: LocalizedError {
    case notAvailable
    case notEnrolled
    case lockout
    case cancelled
    case failed(String)
    case passcodeNotSet
    case invalidContext

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .notEnrolled:
            return "No biometric data enrolled. Please set up Face ID or Touch ID in Settings"
        case .lockout:
            return "Biometric authentication is locked. Please use your passcode"
        case .cancelled:
            return "Authentication was cancelled"
        case .failed(let message):
            return "Authentication failed: \(message)"
        case .passcodeNotSet:
            return "Device passcode is not set. Please set a passcode in Settings"
        case .invalidContext:
            return "Invalid authentication context"
        }
    }
}

@MainActor
class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()

    // MARK: - Published State

    @Published private(set) var biometricType: BiometricType = .none
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var lastAuthDate: Date?
    @Published var authError: BiometricError?

    // MARK: - Private Properties

    private var context: LAContext?
    private let userDefaults = UserDefaults.standard

    // Keys for UserDefaults
    private let lastAuthKey = "BiometricAuthService.lastAuthDate"
    private let authTimeoutKey = "BiometricAuthService.authTimeout"

    // MARK: - Initialization

    private init() {
        checkBiometricAvailability()
        loadLastAuthDate()
    }

    // MARK: - Public API

    /// Check what biometric type is available
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if canEvaluate {
            isAvailable = true
            switch context.biometryType {
            case .touchID:
                biometricType = .touchID
            case .faceID:
                biometricType = .faceID
            case .opticID:
                biometricType = .opticID
            case .none:
                biometricType = .none
                isAvailable = false
            @unknown default:
                biometricType = .none
                isAvailable = false
            }
        } else {
            isAvailable = false
            biometricType = .none

            if let error = error {
                switch error.code {
                case LAError.biometryNotEnrolled.rawValue:
                    authError = .notEnrolled
                case LAError.biometryNotAvailable.rawValue:
                    authError = .notAvailable
                case LAError.passcodeNotSet.rawValue:
                    authError = .passcodeNotSet
                default:
                    break
                }
            }
        }

        print("[BiometricAuth] Availability: \(isAvailable), Type: \(biometricType.displayName)")
    }

    /// Authenticate with biometrics (FaceID/TouchID)
    func authenticateWithBiometrics(reason: String = "Unlock Axon") async -> AuthenticationResult {
        guard isAvailable else {
            authError = .notAvailable
            return .failed(.notAvailable)
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        self.context = context

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                isAuthenticated = true
                lastAuthDate = Date()
                saveLastAuthDate()
                authError = nil
                print("[BiometricAuth] Authentication successful")
                return .success
            } else {
                isAuthenticated = false
                return .failed(.failed("Unknown error"))
            }
        } catch let error as LAError {
            isAuthenticated = false
            return handleLAError(error)
        } catch {
            isAuthenticated = false
            authError = .failed(error.localizedDescription)
            return .failed(.failed(error.localizedDescription))
        }
    }

    /// Authenticate with device passcode (fallback)
    func authenticateWithPasscode(reason: String = "Enter your passcode to unlock Axon") async -> AuthenticationResult {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        self.context = context

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // This allows passcode fallback
                localizedReason: reason
            )

            if success {
                isAuthenticated = true
                lastAuthDate = Date()
                saveLastAuthDate()
                authError = nil
                print("[BiometricAuth] Passcode authentication successful")
                return .success
            } else {
                isAuthenticated = false
                return .failed(.failed("Unknown error"))
            }
        } catch let error as LAError {
            isAuthenticated = false
            return handleLAError(error)
        } catch {
            isAuthenticated = false
            authError = .failed(error.localizedDescription)
            return .failed(.failed(error.localizedDescription))
        }
    }

    /// Combined authentication - tries biometrics first, falls back to passcode
    func authenticate(reason: String = "Unlock Axon") async -> AuthenticationResult {
        // First try biometrics if available
        if isAvailable {
            let result = await authenticateWithBiometrics(reason: reason)
            switch result {
            case .success:
                return .success
            case .fallback:
                // User requested passcode fallback
                return await authenticateWithPasscode(reason: reason)
            case .cancelled:
                return .cancelled
            case .failed(let error):
                // For lockout, use passcode
                if case .lockout = error {
                    return await authenticateWithPasscode(reason: reason)
                }
                // For other failures, try passcode as fallback
                return await authenticateWithPasscode(reason: reason)
            }
        } else {
            // No biometrics available, use passcode
            return await authenticateWithPasscode(reason: reason)
        }
    }

    /// Check if authentication is still valid (within timeout)
    func isAuthenticationValid(timeoutMinutes: Int = 5) -> Bool {
        guard let lastAuth = lastAuthDate else { return false }
        let timeout = TimeInterval(timeoutMinutes * 60)
        return Date().timeIntervalSince(lastAuth) < timeout
    }

    /// Invalidate current authentication
    func invalidateAuthentication() {
        isAuthenticated = false
        context?.invalidate()
        context = nil
        print("[BiometricAuth] Authentication invalidated")
    }

    /// Reset authentication state (for testing or logout)
    func reset() {
        isAuthenticated = false
        lastAuthDate = nil
        authError = nil
        context?.invalidate()
        context = nil
        userDefaults.removeObject(forKey: lastAuthKey)
        print("[BiometricAuth] Service reset")
    }

    // MARK: - Private Helpers

    private func handleLAError(_ error: LAError) -> AuthenticationResult {
        switch error.code {
        case .userCancel:
            authError = .cancelled
            return .cancelled

        case .userFallback:
            return .fallback

        case .biometryLockout:
            authError = .lockout
            return .failed(.lockout)

        case .biometryNotEnrolled:
            authError = .notEnrolled
            return .failed(.notEnrolled)

        case .biometryNotAvailable:
            authError = .notAvailable
            return .failed(.notAvailable)

        case .passcodeNotSet:
            authError = .passcodeNotSet
            return .failed(.passcodeNotSet)

        case .authenticationFailed:
            authError = .failed("Authentication failed")
            return .failed(.failed("Authentication failed"))

        case .invalidContext:
            authError = .invalidContext
            return .failed(.invalidContext)

        default:
            authError = .failed(error.localizedDescription)
            return .failed(.failed(error.localizedDescription))
        }
    }

    private func loadLastAuthDate() {
        if let date = userDefaults.object(forKey: lastAuthKey) as? Date {
            lastAuthDate = date
        }
    }

    private func saveLastAuthDate() {
        userDefaults.set(lastAuthDate, forKey: lastAuthKey)
    }
}
