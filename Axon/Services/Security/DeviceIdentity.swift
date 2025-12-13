//
//  DeviceIdentity.swift
//  Axon
//
//  Stable device identity generation and management
//  Creates a unique, persistent device identifier that stays local
//

import Foundation
import Security
import CryptoKit
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Device information for identity purposes
struct DeviceInfo: Codable, Equatable {
    let deviceId: String           // Stable UUID
    let deviceModel: String        // e.g., "iPhone14,5"
    let systemName: String         // e.g., "iOS"
    let systemVersion: String      // e.g., "17.0"
    let deviceName: String         // User's device name
    let createdAt: Date
    let fingerprint: String        // Hash of device characteristics

    /// Short ID for display (first 8 chars)
    var shortId: String {
        String(deviceId.prefix(8))
    }
}

/// Device identity errors
enum DeviceIdentityError: LocalizedError {
    case generationFailed
    case storageFailed
    case invalidIdentity

    var errorDescription: String? {
        switch self {
        case .generationFailed:
            return "Failed to generate device identity"
        case .storageFailed:
            return "Failed to store device identity"
        case .invalidIdentity:
            return "Invalid device identity"
        }
    }
}

/// DeviceIdentity - Generates and manages a stable device identifier
class DeviceIdentity {
    static let shared = DeviceIdentity()

    // MARK: - Constants

    private let keychainService = "com.axon.deviceidentity"
    private let identityKey = "deviceId"
    private let infoKey = "deviceInfo"

    // MARK: - Properties

    private(set) var deviceId: String?
    private(set) var deviceInfo: DeviceInfo?

    // MARK: - Initialization

    private init() {
        loadOrCreateIdentity()
    }

    // MARK: - Public API

    /// Get the stable device ID
    func getDeviceId() -> String {
        if let deviceId = deviceId {
            return deviceId
        }
        loadOrCreateIdentity()
        return deviceId ?? UUID().uuidString
    }

    /// Get full device information
    func getDeviceInfo() -> DeviceInfo? {
        if deviceInfo == nil {
            loadOrCreateIdentity()
        }
        return deviceInfo
    }

    /// Generate a signature for this device (useful for API auth)
    func generateDeviceSignature(data: String) -> String {
        let key = SymmetricKey(data: Data(getDeviceId().utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key)
        return Data(signature).base64EncodedString()
    }

    /// Verify a device signature
    func verifyDeviceSignature(_ signature: String, data: String) -> Bool {
        let expectedSignature = generateDeviceSignature(data: data)
        return signature == expectedSignature
    }

    /// Generate a device fingerprint from hardware characteristics
    func generateFingerprint() -> String {
        let components = DevicePlatformInfo.fingerprintComponents(
            modelIdentifier: getDeviceModelIdentifier()
        )
        let combined = components.joined(separator: "|")
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Reset device identity (creates new identity)
    func resetIdentity() throws {
        // Delete existing identity
        deleteFromKeychain(key: identityKey)
        deleteFromKeychain(key: infoKey)

        // Generate new identity
        deviceId = nil
        deviceInfo = nil
        loadOrCreateIdentity()

        print("[DeviceIdentity] Identity reset. New ID: \(deviceId ?? "nil")")
    }

    /// Export device info as JSON (for debugging/support)
    func exportDeviceInfo() -> String? {
        guard let info = deviceInfo else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(info) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Private Implementation

    private func loadOrCreateIdentity() {
        // Try to load existing identity
        if let existingId = loadFromKeychain(key: identityKey),
           let idString = String(data: existingId, encoding: .utf8) {
            deviceId = idString

            // Try to load device info
            if let infoData = loadFromKeychain(key: infoKey) {
                let decoder = JSONDecoder()
                deviceInfo = try? decoder.decode(DeviceInfo.self, from: infoData)
            }

            print("[DeviceIdentity] Loaded existing identity: \(deviceId ?? "nil")")
            return
        }

        // Generate new identity
        let newId = generateStableDeviceId()
        deviceId = newId

        // Save to Keychain
        if !saveToKeychain(key: identityKey, data: Data(newId.utf8)) {
            print("[DeviceIdentity] Warning: Failed to save device ID to Keychain")
        }

        // Create device info
        let info = createDeviceInfo(id: newId)
        deviceInfo = info

        // Save device info
        let encoder = JSONEncoder()
        if let infoData = try? encoder.encode(info) {
            _ = saveToKeychain(key: infoKey, data: infoData)
        }

        print("[DeviceIdentity] Generated new identity: \(newId)")
    }

    private func generateStableDeviceId() -> String {
        // Prefer a stable, privacy-preserving vendor identifier when available (iOS).
        if let vendorId = DevicePlatformInfo.vendorIdentifier {
            let hash = SHA256.hash(data: Data(vendorId.utf8))
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }

        // Fallback to random UUID (will persist in Keychain)
        return UUID().uuidString
    }

    private func createDeviceInfo(id: String) -> DeviceInfo {
        return DeviceInfo(
            deviceId: id,
            deviceModel: getDeviceModelIdentifier(),
            systemName: DevicePlatformInfo.systemName,
            systemVersion: DevicePlatformInfo.systemVersion,
            deviceName: DevicePlatformInfo.deviceName,
            createdAt: Date(),
            fingerprint: generateFingerprint()
        )
    }

    private func getDeviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(key: String, data: Data) -> Bool {
        // Delete existing item first
        deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Platform Info

private enum DevicePlatformInfo {
    #if os(iOS)
    static var systemName: String { UIDevice.current.systemName }
    static var systemVersion: String { UIDevice.current.systemVersion }
    static var deviceName: String { UIDevice.current.name }

    /// A stable identifier tied to the app vendor (iOS only). We hash it before storing.
    static var vendorIdentifier: String? {
        UIDevice.current.identifierForVendor?.uuidString
    }

    static func fingerprintComponents(modelIdentifier: String) -> [String] {
        let device = UIDevice.current
        return [
            device.model,
            device.systemName,
            device.systemVersion,
            modelIdentifier,
            UIScreen.main.bounds.width.description,
            UIScreen.main.bounds.height.description,
            UIScreen.main.scale.description
        ]
    }
    #elseif os(macOS)
    static var systemName: String { "macOS" }
    static var systemVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }
    static var deviceName: String { Host.current().localizedName ?? "Mac" }

    /// No direct equivalent on macOS; return nil so we fall back to Keychain-persisted UUID.
    static var vendorIdentifier: String? { nil }

    static func fingerprintComponents(modelIdentifier: String) -> [String] {
        let screen = NSScreen.main
        let frame = screen?.frame ?? .zero
        let scale = screen?.backingScaleFactor ?? 1
        return [
            "Mac",
            systemName,
            systemVersion,
            modelIdentifier,
            frame.width.description,
            frame.height.description,
            scale.description
        ]
    }
    #else
    static var systemName: String { "Unknown" }
    static var systemVersion: String { "Unknown" }
    static var deviceName: String { "Unknown" }
    static var vendorIdentifier: String? { nil }

    static func fingerprintComponents(modelIdentifier: String) -> [String] {
        [systemName, systemVersion, deviceName, modelIdentifier]
    }
    #endif
}

// MARK: - DeviceIdentity Extensions

extension DeviceIdentity {
    /// Generate a time-based token for API requests
    func generateRequestToken() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let data = "\(getDeviceId()):\(timestamp)"
        let signature = generateDeviceSignature(data: data)
        return "\(timestamp):\(signature)"
    }

    /// Verify a request token (within 5 minute window)
    func verifyRequestToken(_ token: String, windowSeconds: Int = 300) -> Bool {
        let parts = token.split(separator: ":")
        guard parts.count == 2,
              let timestamp = Int(parts[0]) else {
            return false
        }

        // Check time window
        let now = Int(Date().timeIntervalSince1970)
        guard abs(now - timestamp) <= windowSeconds else {
            return false
        }

        // Verify signature
        let data = "\(getDeviceId()):\(timestamp)"
        let expectedSignature = generateDeviceSignature(data: data)
        return String(parts[1]) == expectedSignature
    }

    /// Check if this is the first launch (new device identity)
    var isFirstLaunch: Bool {
        guard let info = deviceInfo else { return true }
        // Consider "first launch" if identity was created within last 10 seconds
        return Date().timeIntervalSince(info.createdAt) < 10
    }
}
