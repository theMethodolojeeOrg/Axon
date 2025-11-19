# End-to-End Encryption Flow Guide

This document details the encryption standards and flow used in NeurXAxonChat. It is intended for developers implementing client-side applications (e.g., iOS, Android) that need to interact with the system's encrypted data.

## Encryption Standards

The system uses **ChaCha20-Poly1305** (IETF variant) for symmetric encryption, matching the iOS client's **CryptoKit** implementation.

*   **Algorithm**: ChaCha20-Poly1305 (Authenticated Encryption)
*   **Key Length**: 32 bytes (256 bits)
*   **Nonce Length**: 12 bytes (96 bits)
*   **MAC Length**: 16 bytes (128 bits) - *Note: Appended to the ciphertext.*
*   **Encoding**: Base64 for storage of ciphertext, nonces, and tags.

## Key Hierarchy

The system uses a two-tier key architecture:

1.  **Master Key (Derived)**: Derived deterministically from the User ID. Used **only** to encrypt/decrypt the Data Key.
2.  **Data Key (Random)**: A randomly generated 32-byte key. Used to encrypt/decrypt actual user data (settings, API keys, etc.).

### 1. Master Key Derivation

The Master Key is derived using SHA-256 to ensure consistency across devices without storing the key itself.

*   **Input**: `${userId}:${APP_SALT}`
*   **App Salt**: `"NeurXAxonChat_Encryption_V1"` (Constant string)
*   **Algorithm**: SHA-256
*   **Output**: First 32 bytes of the hash.

**Pseudocode:**
```
string input = userId + ":" + "NeurXAxonChat_Encryption_V1"
bytes hash = SHA256(input)
bytes masterKey = hash.slice(0, 32)
```

### 2. Data Key Retrieval

The Data Key is stored in Firestore, encrypted by the Master Key.

*   **Firestore Path**: `users/{userId}/encryption/key`
*   **Document Structure**:
    ```json
    {
      "encryptedKey": {
        "ciphertext": "BASE64_STRING",
        "nonce": "BASE64_STRING",
        "version": 1
      },
      "version": 1,
      "createdAt": 1234567890,
      "updatedAt": 1234567890
    }
    ```

**To retrieve the Data Key:**
1.  Fetch the document from `users/{userId}/encryption/key`.
2.  Derive the **Master Key** (as above).
3.  Decrypt `encryptedKey` using the **Master Key**.
4.  The result is the raw 32-byte **Data Key**.

## Encrypting User Settings

To securely store the ElevenLabs API key (and other sensitive settings), you must encrypt the settings JSON using the **Data Key**.

### 1. Construct the Payload

Create a JSON object with the settings.

```json
{
  "tts": {
    "elevenLabsApiKey": "sk_..."
  },
  "openai": { ... }
}
```

### 2. Encrypt the Payload

1.  Generate a random 12-byte **Nonce**.
2.  Encrypt the JSON string using **ChaCha20-Poly1305** with the **Data Key** and **Nonce**.
3.  Encode the resulting Ciphertext (with appended Tag) and Nonce as Base64 strings.

### 3. Store in Firestore

*   **Firestore Path**: `users/{userId}/settings/appSettings`
*   **Document Structure**:
    ```json
    {
      "encrypted": {
        "ciphertext": "BASE64_CIPHERTEXT",
        "nonce": "BASE64_NONCE",
        "version": 1
      },
      "updatedAt": 1234567890
    }
    ```

## iOS Implementation Notes

For iOS development, use **CryptoKit** (native to iOS 13+).

### Example (Conceptual Swift)

```swift
import CryptoKit
import Foundation

let userId = "user_123"
let appSalt = "NeurXAxonChat_Encryption_V1"

// 1. Derive Master Key
let input = "\(userId):\(appSalt)".data(using: .utf8)!
let hash = SHA256.hash(data: input)
let masterKey = SymmetricKey(data: hash.prefix(32))

// 2. Decrypt Data Key (fetched from Firestore)
// Assume ciphertext is "base64Cipher:base64Tag"
let encryptedDataKey = ... 
let nonceData = ... // 12 bytes
let sealedBox = try ChaChaPoly.SealedBox(nonce: AES.GCM.Nonce(data: nonceData), ciphertext: ciphertext, tag: tag)
let dataKey = try ChaChaPoly.open(sealedBox, using: masterKey)

// 3. Encrypt Settings
let settingsJson = "{\"tts\":{\"elevenLabsApiKey\":\"sk_...\"}}"
let settingsData = settingsJson.data(using: .utf8)!
let newNonce = AES.GCM.Nonce() // 12 bytes
let sealedBoxSettings = try ChaChaPoly.seal(settingsData, using: SymmetricKey(data: dataKey), nonce: newNonce)

// 4. Upload to Firestore
// Store base64 encoded ciphertext:tag and nonce
```

## Important Security Notes

1.  **Never store the Master Key or Data Key persistently on disk.** Derive the Master Key in memory when needed. Keep the Data Key in secure memory (e.g., Keychain) if caching is necessary, but preferably re-decrypt it using the derived Master Key.
2.  **Always use a unique Nonce** for every encryption operation. Never reuse a nonce with the same key.
3.  **Verify the `version` field.** Currently, the version is `1`. If you encounter a higher version, the encryption algorithm may have changed.

## Syncing Implementation Details

The system ensures secure syncing of keys and settings across devices using Firestore as the central store.

### Encryption Key Syncing
**Source:** `src/hooks/useEncryptionKey.ts`

The `useEncryptionKey` hook manages the lifecycle of the Data Key:
1.  **Check:** On initialization, it checks `users/{userId}/encryption/dataKey` in Firestore.
2.  **Recover:** If found, it retrieves the encrypted key and decrypts it using the Master Key (derived locally from `userId`).
3.  **Create:** If not found (first run), it:
    *   Generates a new random Data Key.
    *   Encrypts it with the Master Key.
    *   Saves the encrypted key to Firestore.
    *   Returns the raw Data Key for immediate use.

### API Keys & Settings Syncing
**Source:** `src/services/firebase/firestoreSettingsStorage.ts`

The `FirestoreSettingsStorage` service handles the secure storage of user settings, including sensitive API keys:
1.  **Save:**
    *   Takes the full settings object (including `apiKeys`).
    *   Converts it to a JSON string.
    *   Encrypts the JSON string using the **Data Key**.
    *   Saves the encrypted blob to `users/{userId}/settings/appSettings`.
2.  **Retrieve:**
    *   Fetches the encrypted blob from Firestore.
    *   Decrypts it using the **Data Key**.
    *   Parses the JSON string back into the settings object.

This ensures that API keys are never stored in plaintext on Firestore and can only be accessed by the user who owns the Data Key.

## Server-Side Implementation

The Cloud Functions environment (Node.js) mirrors the client-side encryption to securely access API keys when needed (e.g., for proxying requests to ElevenLabs).

**Source:** `functions/src/services/encryptionService.ts`

*   **Algorithm**: Uses Node.js `crypto` module with `chacha20-poly1305`.
*   **Key Derivation**: Matches client-side SHA-256 derivation.
*   **Usage**:
    *   `fetchAndDecryptDataKey(firestore, uid)`: Retrieves and decrypts the user's Data Key.
    *   `fetchAndDecryptElevenLabsKey(firestore, uid)`: Retrieves the encrypted settings, decrypts them using the Data Key, and extracts the ElevenLabs API key.
