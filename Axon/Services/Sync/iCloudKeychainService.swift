//
//  iCloudKeychainService.swift
//  Axon
//
//  iCloud Keychain-backed secret sync
//
//  Stores selected secrets in the Keychain with kSecAttrSynchronizable=true
//  so they roam across the user\'s Apple devices (same Apple ID).
//

import Foundation
import Security

final class iCloudKeychainService {
    static let shared = iCloudKeychainService()

    /// Use a dedicated service namespace so these items don\'t collide with existing Keychain items.
    private let service = "com.neurx.axon.secrets.sync"

    private init() {}

    enum SyncError: LocalizedError {
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .saveFailed(let status):
                return "Failed to save to iCloud Keychain: \(status)"
            case .readFailed(let status):
                return "Failed to read from iCloud Keychain: \(status)"
            case .deleteFailed(let status):
                return "Failed to delete from iCloud Keychain: \(status)"
            case .decodingFailed:
                return "Failed to decode iCloud Keychain value"
            }
        }
    }

    // MARK: - Public API (APIProvider)

    func saveAPIKey(_ key: String, for provider: APIProvider) throws {
        try save(key, account: accountKey(for: provider))
    }

    func getAPIKey(for provider: APIProvider) throws -> String? {
        try read(account: accountKey(for: provider))
    }

    func deleteAPIKey(for provider: APIProvider) throws {
        try delete(account: accountKey(for: provider))
    }

    // MARK: - Implementation

    private func accountKey(for provider: APIProvider) -> String {
        "apikey.\(provider.rawValue)"
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            // This is the important part: make the item roam via iCloud Keychain.
            kSecAttrSynchronizable: kCFBooleanTrue as Any
        ]
    }

    private func save(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SyncError.decodingFailed
        }

        // Delete existing item first (idempotent)
        try? delete(account: account)

        var query = baseQuery(account: account)
        query[kSecValueData] = data
        // Use normal accessible class (not ThisDeviceOnly) so it can roam.
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SyncError.saveFailed(status)
        }
    }

    private func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SyncError.readFailed(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SyncError.decodingFailed
        }

        return value
    }

    private func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SyncError.deleteFailed(status)
        }
    }
}
