//
//  SecureVault.swift
//  Axon
//
//  CryptoKit-based secure local storage for sensitive data
//  All data stays on-device, encrypted with keys derived from device identity
//

import Foundation
import CryptoKit
import Security

/// Errors for SecureVault operations
enum SecureVaultError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    case invalidData
    case storageError(String)
    case keyNotFound
    case dataCorrupted

    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        case .keyGenerationFailed:
            return "Failed to generate encryption key"
        case .invalidData:
            return "Invalid data format"
        case .storageError(let message):
            return "Storage error: \(message)"
        case .keyNotFound:
            return "Encryption key not found"
        case .dataCorrupted:
            return "Stored data is corrupted"
        }
    }
}

/// A vault item stored in the secure vault
struct VaultItem: Codable {
    let key: String
    let encryptedData: Data
    let nonce: Data
    let tag: Data
    let createdAt: Date
    let updatedAt: Date
}

/// SecureVault - Local-first encrypted storage using CryptoKit
class SecureVault {
    static let shared = SecureVault()

    // MARK: - Constants

    private let vaultKeyIdentifier = "com.axon.securevault.key"
    private let vaultStorageKey = "SecureVault.items"
    private let appSalt = "AxonSecureVault_V1"

    // MARK: - Private Properties

    private var encryptionKey: SymmetricKey?
    private let fileManager = FileManager.default

    // MARK: - Initialization

    private init() {
        loadOrCreateEncryptionKey()
    }

    // MARK: - Public API

    /// Store a string value securely
    func store(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecureVaultError.invalidData
        }
        try store(data, forKey: key)
    }

    /// Store data securely
    func store(_ data: Data, forKey key: String) throws {
        guard let encryptionKey = encryptionKey else {
            throw SecureVaultError.keyNotFound
        }

        // Encrypt using ChaCha20-Poly1305
        let nonce = ChaChaPoly.Nonce()
        let sealedBox = try ChaChaPoly.seal(data, using: encryptionKey, nonce: nonce)

        let item = VaultItem(
            key: key,
            encryptedData: sealedBox.ciphertext,
            nonce: Data(nonce),
            tag: sealedBox.tag,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Store in Keychain for maximum security
        try storeInKeychain(item)

        debugLog(.secureVault, "Stored item: \(key)")
    }

    /// Retrieve a string value
    func retrieveString(forKey key: String) throws -> String? {
        guard let data = try retrieve(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieve data
    func retrieve(forKey key: String) throws -> Data? {
        guard let encryptionKey = encryptionKey else {
            throw SecureVaultError.keyNotFound
        }

        guard let item = try retrieveFromKeychain(key: key) else {
            return nil
        }

        // Decrypt using ChaCha20-Poly1305
        let nonce = try ChaChaPoly.Nonce(data: item.nonce)
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: item.encryptedData,
            tag: item.tag
        )

        let decryptedData = try ChaChaPoly.open(sealedBox, using: encryptionKey)

        debugLog(.secureVault, "Retrieved item: \(key)")
        return decryptedData
    }

    /// Delete a stored item
    func delete(forKey key: String) throws {
        try deleteFromKeychain(key: key)
        debugLog(.secureVault, "Deleted item: \(key)")
    }

    /// Check if a key exists
    func exists(forKey key: String) -> Bool {
        do {
            return try retrieveFromKeychain(key: key) != nil
        } catch {
            return false
        }
    }

    /// List all stored keys
    func listKeys() throws -> [String] {
        return try listKeychainItems()
    }

    /// Clear all stored items (dangerous!)
    func clearAll() throws {
        let keys = try listKeys()
        for key in keys {
            try delete(forKey: key)
        }
        debugLog(.secureVault, "Cleared all items")
    }

    /// Store a Codable object securely
    func storeObject<T: Codable>(_ object: T, forKey key: String) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(object)
        try store(data, forKey: key)
    }

    /// Retrieve a Codable object
    func retrieveObject<T: Codable>(forKey key: String, type: T.Type) throws -> T? {
        guard let data = try retrieve(forKey: key) else {
            return nil
        }
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Key Management

    /// Regenerate the encryption key (will invalidate all stored data!)
    func regenerateKey() throws {
        // Clear existing data
        try clearAll()

        // Delete old key
        deleteKeyFromKeychain()

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        try saveKeyToKeychain(newKey)
        encryptionKey = newKey

        debugLog(.secureVault, "Regenerated encryption key")
    }

    // MARK: - Private Key Management

    private func loadOrCreateEncryptionKey() {
        // Try to load existing key from Keychain
        if let existingKey = loadKeyFromKeychain() {
            encryptionKey = existingKey
            debugLog(.secureVault, "Loaded existing encryption key")
            return
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        do {
            try saveKeyToKeychain(newKey)
            encryptionKey = newKey
            debugLog(.secureVault, "Generated new encryption key")
        } catch {
            debugLog(.secureVault, "Error saving key to keychain: \(error)")
        }
    }

    private func loadKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: vaultKeyIdentifier,
            kSecAttrAccount as String: "masterKey",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let keyData = result as? Data else {
            return nil
        }

        return SymmetricKey(data: keyData)
    }

    private func saveKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        // First delete any existing key
        deleteKeyFromKeychain()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: vaultKeyIdentifier,
            kSecAttrAccount as String: "masterKey",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw SecureVaultError.keyGenerationFailed
        }
    }

    private func deleteKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: vaultKeyIdentifier,
            kSecAttrAccount as String: "masterKey"
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain Item Storage

    private func storeInKeychain(_ item: VaultItem) throws {
        let encoder = JSONEncoder()
        let itemData = try encoder.encode(item)

        // Delete existing item first
        try? deleteFromKeychain(key: item.key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.axon.securevault.item",
            kSecAttrAccount as String: item.key,
            kSecValueData as String: itemData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw SecureVaultError.storageError("Failed to store item: OSStatus \(status)")
        }
    }

    private func retrieveFromKeychain(key: String) throws -> VaultItem? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.axon.securevault.item",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let itemData = result as? Data else {
            throw SecureVaultError.storageError("Failed to retrieve item: OSStatus \(status)")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(VaultItem.self, from: itemData)
    }

    private func deleteFromKeychain(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.axon.securevault.item",
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SecureVaultError.storageError("Failed to delete item: OSStatus \(status)")
        }
    }

    private func listKeychainItems() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.axon.securevault.item",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            throw SecureVaultError.storageError("Failed to list items: OSStatus \(status)")
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }
}

// MARK: - Convenience Extensions

extension SecureVault {
    /// Store an API key securely
    func storeAPIKey(_ key: String, provider: String) throws {
        try store(key, forKey: "apikey.\(provider)")
    }

    /// Retrieve an API key
    func retrieveAPIKey(provider: String) throws -> String? {
        return try retrieveString(forKey: "apikey.\(provider)")
    }

    /// Delete an API key
    func deleteAPIKey(provider: String) throws {
        try delete(forKey: "apikey.\(provider)")
    }

    /// Check if an API key exists
    func hasAPIKey(provider: String) -> Bool {
        return exists(forKey: "apikey.\(provider)")
    }
}
