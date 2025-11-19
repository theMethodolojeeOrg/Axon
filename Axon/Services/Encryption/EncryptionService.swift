//
//  EncryptionService.swift
//  Axon
//
//  Handles encryption of sensitive data for backend synchronization
//

import Foundation
import Security
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

class EncryptionService {
    static let shared = EncryptionService()
    
    private let appSalt = "NeurXAxonChat_Encryption_V1"
    private let db = Firestore.firestore()
    
    private let chachaNonceSize = 12 // ChaChaPoly.Nonce size in bytes

    // MARK: - Encoding Helpers (ciphertext formatting)
    /// Encode ChaChaPoly sealed box as legacy colon-separated format: "<base64-ct>:<base64-tag>"
    /// This matches the backend's expected format
    private func combinedCiphertextB64(from sealed: ChaChaPoly.SealedBox) -> String {
        let ctB64 = sealed.ciphertext.base64EncodedString()
        let tagB64 = sealed.tag.base64EncodedString()
        return "\(ctB64):\(tagB64)"
    }

    /// Decode ciphertext into (ciphertext, tag) supporting both formats:
    ///  - Legacy: "<base64-ct>:<base64-tag>"
    ///  - Combined: single Base64 of (ct || tag)
    private func decodeCiphertextParts(from ciphertextB64: String) throws -> (ct: Data, tag: Data) {
        if ciphertextB64.contains(":") {
            // Legacy format: split on ':'
            let parts = ciphertextB64.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let ct = Data(base64Encoded: parts[0]), let tag = Data(base64Encoded: parts[1]) else {
                throw EncryptionError.invalidKeyFormat
            }
            return (ct, tag)
        } else {
            // Combined format: last 16 bytes are tag
            guard let combined = Data(base64Encoded: ciphertextB64), combined.count >= 16 else {
                throw EncryptionError.invalidKeyFormat
            }
            let tagRange = (combined.count - 16)..<combined.count
            let ct = combined.subdata(in: 0..<(combined.count - 16))
            let tag = combined.subdata(in: tagRange)
            return (ct, tag)
        }
    }
    
    private func secureRandomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        if result != errSecSuccess {
            throw EncryptionError.encryptionFailed
        }
        return data
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Encrypts the ElevenLabs API key payload and syncs it to Firestore
    func encryptAndSyncElevenLabsKey(_ apiKey: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("[EncryptionService] Error: User not authenticated")
            throw EncryptionError.notAuthenticated
        }

        print("[EncryptionService] Starting encryption for user: \(userId)")

        // 1. Construct JSON Payload
        let payload: [String: Any] = [
            "tts": [
                "elevenLabsApiKey": apiKey
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        let messageBytes = Array(jsonData)
        print("[EncryptionService] Payload constructed, size: \(messageBytes.count) bytes")

        // 2. Get Data Key
        do {
            let dataKey = try await getOrFetchDataKey(userId: userId)
            print("[EncryptionService] Data key retrieved successfully")

            // 3. Encrypt Payload using ChaCha20-Poly1305
            let key = SymmetricKey(data: Data(dataKey))
            let nonceData = try secureRandomBytes(count: chachaNonceSize)
            let nonce = try ChaChaPoly.Nonce(data: nonceData)
            let sealed = try ChaChaPoly.seal(Data(messageBytes), using: key, nonce: nonce)
            // Store a single Base64 of (ciphertext || tag) to match server contract
            let ciphertextB64 = combinedCiphertextB64(from: sealed)
            let nonceB64 = nonceData.base64EncodedString()
            print("[EncryptionService] Encryption successful")

            // 4. Sync to Firestore
            let settingsData: [String: Any] = [
                "encrypted": [
                    "ciphertext": ciphertextB64,
                    "nonce": nonceB64,
                    "version": 1
                ],
                "updatedAt": FieldValue.serverTimestamp()
            ]

            let docRef = db.collection("users").document(userId)
                .collection("settings").document("appSettings")

            try await docRef.setData(settingsData, merge: true)
            print("[EncryptionService] Successfully synced encrypted key to Firestore at users/\(userId)/settings/appSettings")

            // Verify the write by reading it back
            let snapshot = try await docRef.getDocument()
            if snapshot.exists {
                print("[EncryptionService] Verification: Document exists in Firestore")
                if let data = snapshot.data(), let encrypted = data["encrypted"] as? [String: Any] {
                    print("[EncryptionService] Verification: Encrypted data structure is valid")
                } else {
                    print("[EncryptionService] WARNING: Document exists but encrypted structure is missing!")
                }
            } else {
                print("[EncryptionService] WARNING: Document write appeared to succeed but document doesn't exist!")
            }
        } catch {
            print("[EncryptionService] Error during encryption/sync: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Key Management
    
    private func getOrFetchDataKey(userId: String) async throws -> [UInt8] {
        print("[EncryptionService] Fetching or generating Data Key for user: \(userId)")

        // 1. Derive Master Key
        let masterKey = deriveMasterKey(userId: userId)
        print("[EncryptionService] Master Key derived from user ID")

        // 2. Fetch Encrypted Data Key from Firestore
        let docRef = db.collection("users").document(userId)
            .collection("encryption").document("key")

        let doc = try await docRef.getDocument()

        if !doc.exists {
            // If key doesn't exist, we should generate one
            print("[EncryptionService] Data Key doesn't exist in Firestore, generating new one")
            return try await generateAndStoreDataKey(userId: userId, masterKey: masterKey)
        }

        print("[EncryptionService] Data Key document exists, decrypting")

        guard let data = doc.data(),
              let encryptedKey = data["encryptedKey"] as? [String: Any],
              let ciphertextB64 = encryptedKey["ciphertext"] as? String,
              let nonceB64 = encryptedKey["nonce"] as? String else {
            print("[EncryptionService] Error: Invalid Data Key format in Firestore")
            throw EncryptionError.invalidKeyFormat
        }

        // 3. Decrypt Data Key using ChaCha20-Poly1305 (supports legacy and combined formats)
        let key = SymmetricKey(data: Data(masterKey))
        let (ct, tag) = try decodeCiphertextParts(from: ciphertextB64)
        guard let nonceData = Data(base64Encoded: nonceB64) else {
            print("[EncryptionService] Error: Invalid nonce in Data Key")
            throw EncryptionError.invalidKeyFormat
        }
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let sealedBox = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let opened = try ChaChaPoly.open(sealedBox, using: key)
        print("[EncryptionService] Data Key decrypted successfully")
        return Array(opened)
    }
    
    private func generateAndStoreDataKey(userId: String, masterKey: [UInt8]) async throws -> [UInt8] {
        print("[EncryptionService] Generating new Data Key for user: \(userId)")

        // Generate new random Data Key (32 bytes)
        let dataKeyData = try secureRandomBytes(count: 32)
        let dataKey = Array(dataKeyData)
        print("[EncryptionService] Generated 32-byte random Data Key")

        // Encrypt it with Master Key using ChaCha20-Poly1305
        let key = SymmetricKey(data: Data(masterKey))
        let nonceData = try secureRandomBytes(count: chachaNonceSize)
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let sealed = try ChaChaPoly.seal(dataKeyData, using: key, nonce: nonce)
        let ciphertextB64 = combinedCiphertextB64(from: sealed)
        let nonceB64 = nonceData.base64EncodedString()
        print("[EncryptionService] Data Key encrypted with Master Key")

        let keyDataDict: [String: Any] = [
            "encryptedKey": [
                "ciphertext": ciphertextB64,
                "nonce": nonceB64,
                "version": 1
            ],
            "version": 1,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let docRef = db.collection("users").document(userId)
            .collection("encryption").document("key")

        try await docRef.setData(keyDataDict)
        print("[EncryptionService] Data Key stored in Firestore at users/\(userId)/encryption/key")

        return dataKey
    }
    
    private func deriveMasterKey(userId: String) -> [UInt8] {
        let input = "\(userId):\(appSalt)"
        let inputData = Data(input.utf8)
        let digest = SHA256.hash(data: inputData)
        return Array(digest) // 32 bytes
    }
}

enum EncryptionError: LocalizedError {
    case notAuthenticated
    case invalidKeyFormat
    case decryptionFailed
    case encryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "User not authenticated"
        case .invalidKeyFormat: return "Invalid encryption key format"
        case .decryptionFailed: return "Failed to decrypt data key"
        case .encryptionFailed: return "Failed to encrypt data"
        }
    }
}

