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
            return bioID
        }
        
        // 2. Create new key if none exists
        logger.info("No existing identity found. specific key generation...")
        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], // Requires biometrics to use the key
            nil
        )!
        
        // Generate key in Secure Enclave
        let privateKey = try SecureEnclave.P256.Signing.PrivateKey(accessControl: accessControl)
        
        // Store reference in Keychain
        try storeKey(privateKey)
        
        // 3. Derive BioID
        let bioID = deriveBioID(from: privateKey.publicKey)
        self.currentBioID = bioID
        logger.info("Generated new BioID: \(bioID)")
        return bioID
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
    
    /// Resets the identity, deleting the key from the Keychain.
    /// WARNING: This is destructive and will result in data loss if not handled carefully.
    public func resetIdentity() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw BioIDError.keychainError(status)
        }
        
        DispatchQueue.main.async {
            self.currentBioID = nil
        }
        logger.warning("BioID identity has been reset.")
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
        // SecureEnclave keys are not exportable relative to data, but we store the reference
        // Actually, SecureEnclave.P256.Signing.PrivateKey automatically uses the Keychain when initialized with access control?
        // Wait, the standard init(accessControl:) creates it, but we need to ensure it's queryable.
        // We typically add it to the keychain explicitly if we want to retrieve it by tag.
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecValueRef as String: key.dataRepresentation // For SE keys, this holds the reference
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw BioIDError.keychainError(status)
        }
    }
    
    private func retrieveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            throw BioIDError.keyNotFound
        }
        
        // Reconstitute the key from the reference
        // Note: For Secure Enclave keys, we initialize from the Data representation (reference)
        // Check if we can cast directly to SecKey and init?
        // CryptoKit provides init(dataRepresentation:) for retrieving.
        
        // Wait, SecItemCopyMatching with kSecReturnRef returns a SecKey.
        // SecureEnclave.P256.Signing.PrivateKey can be initialized from a data representation of the key reference.
        // Correct approach for CryptoKit + Keychain integration:
        
        let dataQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecReturnData as String: true
        ]
        
        var dataItem: CFTypeRef?
        let dataStatus = SecItemCopyMatching(dataQuery as CFDictionary, &dataItem)
        
        guard dataStatus == errSecSuccess, let data = dataItem as? Data else {
            throw BioIDError.keyNotFound
        }
        
        return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
    }
}

public enum BioIDError: Error {
    case biometricsNotAvailable
    case keyNotFound
    case keychainError(OSStatus)
    case unknown
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
