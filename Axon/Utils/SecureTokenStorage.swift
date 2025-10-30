//
//  SecureTokenStorage.swift
//  Axon
//
//  Secure token storage using Keychain
//

import Foundation
import Security

class SecureTokenStorage {
    static let shared = SecureTokenStorage()

    private let service = "com.neurx.axon.firebase"

    private enum KeychainKeys: String {
        case idToken = "firebase_id_token"
        case refreshToken = "firebase_refresh_token"
        case apiKey = "admin_api_key"
    }

    private init() {}

    // MARK: - ID Token

    func saveIdToken(_ token: String) throws {
        try save(token, forKey: KeychainKeys.idToken.rawValue)
    }

    func getIdToken() throws -> String? {
        try retrieve(forKey: KeychainKeys.idToken.rawValue)
    }

    func deleteIdToken() throws {
        try delete(forKey: KeychainKeys.idToken.rawValue)
    }

    // MARK: - API Key

    func saveApiKey(_ key: String) throws {
        try save(key, forKey: KeychainKeys.apiKey.rawValue)
    }

    func getApiKey() throws -> String? {
        try retrieve(forKey: KeychainKeys.apiKey.rawValue)
    }

    func deleteApiKey() throws {
        try delete(forKey: KeychainKeys.apiKey.rawValue)
    }

    // MARK: - Clear All

    func clearAll() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.clearFailed(status)
        }
    }

    // MARK: - Private Methods

    func save(_ value: String, forKey key: String) throws {
        let data = value.data(using: .utf8)!

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieve(forKey key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrieveFailed(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return string
    }

    func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case clearFailed(OSStatus)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .retrieveFailed(let status):
            return "Failed to retrieve from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        case .clearFailed(let status):
            return "Failed to clear keychain: \(status)"
        case .decodingFailed:
            return "Failed to decode keychain data"
        }
    }
}

