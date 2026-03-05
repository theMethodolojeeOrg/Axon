import Foundation
import LocalAuthentication
import CryptoKit
import Security
import OSLog
import Combine

/// Service responsible for managing the user's biometric identity (BioID)
/// using Secure Enclave and iCloud Keychain.
///
/// This service handles:
/// 1. Generating a stable Secure Enclave private key bound to the user's biometrics.
/// 2. Deriving a short, public-facing "BioID" (e.g., "a7f3") from the public key.
/// 3. Providing signing capabilities for attesting identity.
public class BioIDService: ObservableObject {
    public static let shared = BioIDService()
    
    @Published public var currentBioID: String?
    @Published public var isBiometricsAvailable: Bool = false
    
    private let logger = Logger(subsystem: "com.axon", category: "BioIDService")
    private let keyTag = "com.axon.identity.bioid.v1"
    
    private init() {
        checkBiometricAvailability()
        Task {
            try? await loadExistingIdentity()
        }
    }
    
    /// Checks if the device supports biometric authentication
    public func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        isBiometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if let error = error {
            logger.error("Biometrics not available: \(error.localizedDescription)")
        }
    }
    
    /// Ensures that a BioID identity exists for the user.
    /// If one exists in the Keychain, it is loaded.
    /// If not, a new Secure Enclave key is generated and stored.
    /// - Returns: The 4-character BioID string (e.g., "a7f3")
    /// - Throws: BioIDError if biometrics are unavailable or SE key generation fails
    @MainActor
    public func ensureIdentity() async throws -> String {
        if let existing = currentBioID {
            return existing
        }
        
        // 1. Try to retrieve existing key
        if let privateKey = try? retrieveKey() {
            let bioID = deriveBioID(from: privateKey.publicKey)
            self.currentBioID = bioID
            logger.info("Loaded existing BioID: \(bioID)")
            debugLog(.aipIdentity, "✅ Loaded existing BioID: \(bioID)")
            return bioID
        }
        
        // 2. Check if Secure Enclave is available (REQUIRED)
        guard SecureEnclave.isAvailable else {
            logger.error("Secure Enclave not available on this device")
            debugLog(.aipIdentity, "❌ Secure Enclave not available")
            throw BioIDError.secureEnclaveNotAvailable
        }
        
        // 3. Check if biometrics are available (REQUIRED)
        guard isBiometricsAvailable else {
            logger.error("Biometrics not available - enrollment required")
            debugLog(.aipIdentity, "❌ Biometrics not enrolled")
            throw BioIDError.biometricsNotAvailable
        }
        
        // 4. Create access control for biometric-protected key
        var cfError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &cfError
        ) else {
            let errorDesc = cfError?.takeRetainedValue().localizedDescription ?? "unknown"
            logger.error("Failed to create access control: \(errorDesc)")
            debugLog(.aipIdentity, "❌ Access control creation failed: \(errorDesc)")
            throw BioIDError.accessControlCreationFailed(errorDesc)
        }
        
        // 5. Generate key in Secure Enclave
        do {
            let privateKey = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
            
            // Store reference in Keychain
            try storeKey(privateKey)
            
            // 6. Derive BioID
            let bioID = deriveBioID(from: privateKey.publicKey)
            self.currentBioID = bioID
            logger.info("Generated new BioID (Secure Enclave): \(bioID)")
            debugLog(.aipIdentity, "✅ Generated new BioID (Secure Enclave): \(bioID)")
            return bioID
        } catch let seError as NSError {
            logger.error("Secure Enclave key generation failed: domain=\(seError.domain) code=\(seError.code) \(seError.localizedDescription)")
            debugLog(.aipIdentity, "❌ SE key generation failed: domain=\(seError.domain) code=\(seError.code) \(seError.localizedDescription)")
            throw BioIDError.secureEnclaveKeyGenerationFailed(seError.localizedDescription)
        }
    }
    
    /// Resets the BioID identity by deleting the key from keychain and clearing state.
    /// Used for development/testing purposes.
    @MainActor
    public func resetIdentity() throws {
        logger.info("Resetting BioID identity...")
        
        // Delete the SE key from keychain
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecAttrService as String: "com.axon.bioid.secureenclave"
        ]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete key from keychain: \(status)")
            throw BioIDError.keychainError(status)
        }
        
        // Also delete any software fallback key
        let softwareQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag + ".software"
        ]
        SecItemDelete(softwareQuery as CFDictionary)
        
        // Clear current state
        self.currentBioID = nil
        logger.info("BioID identity reset complete")
    }
    
    /// Software fallback for devices without Secure Enclave (e.g., Simulator)
    @MainActor
    private func ensureIdentitySoftwareFallback() async throws -> String {
        logger.info("Using software key fallback")
        
        // Generate a regular P256 key (not SE-protected)
        let privateKey = P256.Signing.PrivateKey()
        
        // Store in Keychain
        let keyData = privateKey.rawRepresentation
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag + ".software",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing and add new
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BioIDError.keychainError(status)
        }
        
        // Derive BioID from public key
        let bioID = deriveBioIDFromSoftwareKey(privateKey.publicKey)
        self.currentBioID = bioID
        logger.info("Generated new BioID (software fallback): \(bioID)")
        return bioID
    }
    
    private func deriveBioIDFromSoftwareKey(_ publicKey: P256.Signing.PublicKey) -> String {
        let data = publicKey.x963Representation
        let digest = SHA256.hash(data: data)
        let prefix = digest.prefix(2)
        let hex = prefix.map { String(format: "%02x", $0) }.joined()
        return hex
    }
    
    /// Signs the given data using the Secure Enclave private key.
    /// This requires user biometric interaction.
    public func sign(data: Data) async throws -> P256.Signing.ECDSASignature {
        guard let privateKey = try? retrieveKey() else {
            throw BioIDError.keyNotFound
        }
        
        // This call will trigger the biometric prompt (FaceID/TouchID)
        return try privateKey.signature(for: data)
    }
    
    // MARK: - Internal Helpers
    
    private func loadExistingIdentity() async throws {
        if let key = try? retrieveKey() {
            let bioID = deriveBioID(from: key.publicKey)
            DispatchQueue.main.async {
                self.currentBioID = bioID
            }
        }
    }
    
    private func deriveBioID(from publicKey: P256.Signing.PublicKey) -> String {
        // Use x963 representation for stable hashing
        let data = publicKey.x963Representation
        let digest = SHA256.hash(data: data)
        
        // Get first 2 bytes (4 hex characters)
        let prefix = digest.prefix(2)
        let hex = prefix.map { String(format: "%02x", $0) }.joined()
        return hex
    }
    
    private func storeKey(_ key: SecureEnclave.P256.Signing.PrivateKey) throws {
        // Secure Enclave keys store a reference to the key, not the key itself
        // We use dataRepresentation which contains the key reference data
        let keyData = key.dataRepresentation
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecAttrService as String: "com.axon.bioid.secureenclave",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecAttrService as String: "com.axon.bioid.secureenclave"
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to store key: \(status)")
            throw BioIDError.keychainError(status)
        }
        logger.info("Stored SE key reference in keychain")
    }
    
    private func retrieveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecAttrService as String: "com.axon.bioid.secureenclave",
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let data = item as? Data else {
            logger.info("No existing key found in keychain: \(status)")
            throw BioIDError.keyNotFound
        }
        
        // Reconstruct the SE key from the data representation
        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
    }
}

public enum BioIDError: Error, LocalizedError {
    case biometricsNotAvailable
    case secureEnclaveNotAvailable
    case accessControlCreationFailed(String)
    case secureEnclaveKeyGenerationFailed(String)
    case keyNotFound
    case keychainError(OSStatus)
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .biometricsNotAvailable:
            return "Face ID or Touch ID is not enrolled. Please enable biometrics in Settings to create your AIP identity."
        case .secureEnclaveNotAvailable:
            return "This device does not support Secure Enclave. AIP identity requires a device with hardware security."
        case .accessControlCreationFailed(let detail):
            return "Failed to create secure access control: \(detail)"
        case .secureEnclaveKeyGenerationFailed(let detail):
            return "Failed to generate secure key: \(detail)"
        case .keyNotFound:
            return "Identity key not found in keychain."
        case .keychainError(let status):
            return "Keychain error: \(status)"
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

extension BioIDService {
    /// Public Key export for external verification or address generation.
    public func getPublicKey() throws -> P256.Signing.PublicKey {
        guard let privateKey = try? retrieveKey() else {
            throw BioIDError.keyNotFound
        }
        return privateKey.publicKey
    }
}
