//
//  UserSignature.swift
//  Axon
//
//  User signature represents the user's biometric-backed consent.
//  It provides cryptographic proof that the user authorized an action.
//

import Foundation


// MARK: - User Signature

/// The user's biometric-backed consent, providing cryptographic proof of authorization
struct UserSignature: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let deviceId: String
    let deviceShortId: String

    // What was signed
    let signedDataHash: String
    let signedItemType: SignedItemType
    let signedItemId: String

    // Authentication method (stored as String to handle all auth types including passcode)
    let biometricType: String

    // Cryptographic proof
    let signature: String

    // Context
    let conversationId: String?
    let covenantId: String?

    // MARK: - Computed Properties

    /// Short signature for display
    var shortSignature: String {
        String(signature.prefix(12))
    }

    /// Formatted timestamp
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Formatted date and time
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Display name for the authentication type
    var biometricDisplayName: String {
        switch biometricType {
        case "faceID": return "Face ID"
        case "touchID": return "Touch ID"
        case "opticID": return "Optic ID"
        case "passcode": return "Passcode"
        default: return biometricType.capitalized
        }
    }

    /// System image name for the authentication type
    var biometricSystemImage: String {
        switch biometricType {
        case "faceID": return "faceid"
        case "touchID": return "touchid"
        case "opticID": return "opticid"
        case "passcode": return "lock.fill"
        default: return "lock.fill"
        }
    }

    /// Whether this is a biometric method (vs passcode)
    var isBiometricAuth: Bool {
        switch biometricType {
        case "faceID", "touchID", "opticID":
            return true
        default:
            return false
        }
    }
}

// MARK: - Signed Item Type

/// What type of item was signed by the user
enum SignedItemType: String, Codable, Equatable {
    case covenant               // Initial covenant or covenant update
    case trustTier              // A specific trust tier
    case covenantProposal       // A proposal for covenant changes
    case actionApproval         // Approval of a specific action
    case memoryModification     // Modification to AI memories
    case settingsChange         // Change to AI-affecting settings
    case deadlockResolution     // Resolution of a deadlock

    var displayName: String {
        switch self {
        case .covenant: return "Covenant"
        case .trustTier: return "Trust Tier"
        case .covenantProposal: return "Proposal"
        case .actionApproval: return "Action Approval"
        case .memoryModification: return "Memory Modification"
        case .settingsChange: return "Settings Change"
        case .deadlockResolution: return "Deadlock Resolution"
        }
    }
}

// MARK: - User Signature Factory

extension UserSignature {
    /// Create a user signature
    /// - Parameters:
    ///   - biometricType: The authentication type as a string (e.g., "faceID", "touchID", "passcode")
    static func create(
        signedItemType: SignedItemType,
        signedItemId: String,
        signedDataHash: String,
        biometricType: String,
        deviceId: String,
        covenantId: String? = nil,
        conversationId: String? = nil,
        signatureGenerator: (String) -> String
    ) -> UserSignature {
        let id = UUID().uuidString
        let timestamp = Date()

        // Generate signature
        let signatureData = "\(id):\(timestamp.timeIntervalSince1970):\(signedDataHash):\(deviceId)"
        let signature = signatureGenerator(signatureData)

        return UserSignature(
            id: id,
            timestamp: timestamp,
            deviceId: deviceId,
            deviceShortId: String(deviceId.prefix(8)),
            signedDataHash: signedDataHash,
            signedItemType: signedItemType,
            signedItemId: signedItemId,
            biometricType: biometricType,
            signature: signature,
            conversationId: conversationId,
            covenantId: covenantId
        )
    }

    /// Create from BiometricType enum (convenience)
    static func create(
        signedItemType: SignedItemType,
        signedItemId: String,
        signedDataHash: String,
        biometricType: BiometricType,
        deviceId: String,
        covenantId: String? = nil,
        conversationId: String? = nil,
        signatureGenerator: (String) -> String
    ) -> UserSignature {
        create(
            signedItemType: signedItemType,
            signedItemId: signedItemId,
            signedDataHash: signedDataHash,
            biometricType: biometricType.rawValue,
            deviceId: deviceId,
            covenantId: covenantId,
            conversationId: conversationId,
            signatureGenerator: signatureGenerator
        )
    }
}

// MARK: - Signature Verification

extension UserSignature {
    /// Verify that this signature matches the expected data
    func verify(
        expectedDataHash: String,
        expectedDeviceId: String,
        verifier: (String, String) -> Bool
    ) -> Bool {
        // Check basic fields match
        guard signedDataHash == expectedDataHash else { return false }
        guard deviceId == expectedDeviceId else { return false }

        // Verify cryptographic signature
        let signatureData = "\(id):\(timestamp.timeIntervalSince1970):\(signedDataHash):\(deviceId)"
        return verifier(signatureData, signature)
    }
}
