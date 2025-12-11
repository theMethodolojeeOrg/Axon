# Axon Encryption & Security Architecture

## Overview

Axon is designed with a **local-first, privacy-centric** architecture. Your data stays on your device by default, and all sensitive information is encrypted at rest using industry-standard cryptography.

---

## Data Storage Layers

### Layer 1: Local Device Storage

| Data Type | Storage Location | Encryption |
|-----------|------------------|------------|
| Conversations | SwiftData (SQLite) | iOS Data Protection |
| Memories | SwiftData (SQLite) | iOS Data Protection |
| App Settings | UserDefaults + JSON | iOS Data Protection |
| API Keys | iOS Keychain | Hardware-backed AES-256 |

### Layer 2: Optional Cloud Sync (User-Configured)

| Data Type | Sync Method | Encryption |
|-----------|-------------|------------|
| Settings | iCloud Key-Value Store | Apple end-to-end encryption |
| Conversations | iCloud CloudKit (optional) | Apple end-to-end encryption |
| Memories | iCloud CloudKit (optional) | Apple end-to-end encryption |

### Layer 3: Custom Backend (Self-Hosted)

| Data Type | Transport | At-Rest |
|-----------|-----------|---------|
| All synced data | TLS 1.3 | User-controlled |

---

## API Key Security

### Storage: iOS Keychain

All API keys are stored in the iOS Keychain, which provides:

- **Hardware-backed encryption** (Secure Enclave on supported devices)
- **AES-256-GCM** encryption
- **Per-app isolation** - other apps cannot access Axon's keychain items
- **Biometric protection** available (Face ID / Touch ID)

### Keychain Configuration

```swift
// Keychain access configuration used by Axon
let query: [String: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrService: "com.methodolojee.Axon",
    kSecAttrAccount: "api-key-\(provider)",
    kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
]
```

**Key Points:**
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - Keys are only accessible when the device is unlocked
- Keys are **not** backed up to iCloud or iTunes
- Keys are **not** migrated to new devices - must be re-entered

### Supported API Keys

| Provider | Key Prefix | Storage Key |
|----------|------------|-------------|
| OpenAI | `sk-` | `openai` |
| Anthropic | `sk-ant-` | `anthropic` |
| Google Gemini | `AIza` | `gemini` |
| xAI | `xai-` | `xai` |
| ElevenLabs | `sk_` | `elevenlabs` |
| Custom Providers | varies | `custom-{uuid}` |

---

## Conversation & Memory Encryption

### Local Storage (SwiftData)

Conversations and memories are stored in SwiftData (backed by SQLite) with:

1. **iOS Data Protection**: Files are encrypted with keys tied to the device passcode
2. **File Protection Class**: `completeUntilFirstUserAuthentication`
3. **Encryption**: AES-256 with hardware-derived keys

### Data Protection Levels

| Level | Description | Axon Usage |
|-------|-------------|------------|
| `completeProtection` | Encrypted when locked | Available for high-security mode |
| `completeUntilFirstUserAuthentication` | Encrypted until first unlock | **Default** |
| `completeUnlessOpen` | Encrypted when not open | Not used |
| `none` | No encryption | Not used |

---

## Network Security

### API Calls to AI Providers

All API calls use:

- **TLS 1.3** (or TLS 1.2 minimum)
- **Certificate pinning** not currently implemented (relies on system trust store)
- **No plaintext transmission** of API keys or conversation content

### Request Flow

```
┌─────────────┐     TLS 1.3      ┌──────────────────┐
│   Axon App  │ ───────────────► │  AI Provider API │
│             │                  │  (OpenAI, etc.)  │
│ API Key     │                  │                  │
│ from        │  Authorization:  │                  │
│ Keychain    │  Bearer sk-xxx   │                  │
└─────────────┘                  └──────────────────┘
```

### Custom Backend Communication

When using a self-hosted backend:

```
┌─────────────┐     TLS 1.3      ┌──────────────────┐
│   Axon App  │ ───────────────► │  Your Backend    │
│             │                  │  (Cloud Functions│
│ Auth Token  │  Authorization:  │   or custom)     │
│ (optional)  │  Bearer {token}  │                  │
└─────────────┘                  └──────────────────┘
```

---

## App Lock & Biometric Security

### Available Protections

| Feature | Description |
|---------|-------------|
| **App Lock** | Require authentication to open app |
| **Face ID / Touch ID** | Biometric authentication |
| **Passcode Fallback** | Device passcode as backup |
| **Lock Timeout** | Auto-lock after inactivity |
| **Privacy Blur** | Blur content in app switcher |

### Lock Timeout Options

- Immediately
- After 1 minute
- After 5 minutes
- After 15 minutes
- After 1 hour
- Never

### Implementation

```swift
// Biometric authentication using LocalAuthentication framework
let context = LAContext()
context.evaluatePolicy(
    .deviceOwnerAuthenticationWithBiometrics,
    localizedReason: "Unlock Axon"
) { success, error in
    // Handle result
}
```

---

## What Axon Does NOT Do

### We Never:

- ❌ Store your API keys on our servers
- ❌ Transmit your conversations to methodolojee servers
- ❌ Access your data without your explicit action
- ❌ Include analytics that track conversation content
- ❌ Share data with third parties (except AI providers you configure)

### We Cannot:

- ❌ Recover your API keys if you lose them
- ❌ Access your conversations (they're on YOUR device)
- ❌ Decrypt your data without your device passcode

---

## Third-Party Data Handling

When you use AI providers through Axon, your data is subject to their privacy policies:

| Provider | Privacy Policy |
|----------|---------------|
| OpenAI | https://openai.com/privacy |
| Anthropic | https://anthropic.com/privacy |
| Google | https://policies.google.com/privacy |
| xAI | https://x.ai/privacy |

**Important**: Axon sends your messages directly to these providers. Review their data retention and training policies.

---

## iCloud Sync Security

### Key-Value Store (Settings)

- **Encryption**: Apple end-to-end encryption
- **Access**: Only your Apple ID can access
- **Data**: App preferences, non-sensitive settings

### CloudKit (Conversations/Memories - Optional)

- **Encryption**: Apple end-to-end encryption with Advanced Data Protection
- **Access**: Only your Apple ID can access
- **Container**: Private database (not shared)

### Enabling Advanced Data Protection

For maximum iCloud security:
1. Go to iOS Settings → [Your Name] → iCloud
2. Enable "Advanced Data Protection"
3. This enables end-to-end encryption for most iCloud data

---

## Self-Hosted Backend Security

### Requirements

If you deploy your own backend:

1. **Use HTTPS** - Never deploy without TLS
2. **Authentication** - Implement token-based auth
3. **Firestore Rules** - If using Firebase, configure security rules
4. **Rate Limiting** - Protect against abuse

### Recommended Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Your Infrastructure                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │ Cloud        │    │ Firestore    │    │ Cloud     │ │
│  │ Functions    │───►│ Database     │    │ Storage   │ │
│  │ (HTTPS)      │    │ (encrypted)  │    │ (optional)│ │
│  └──────────────┘    └──────────────┘    └───────────┘ │
│         ▲                                               │
│         │ TLS 1.3                                       │
│         │                                               │
└─────────┼───────────────────────────────────────────────┘
          │
    ┌─────┴─────┐
    │  Axon App │
    └───────────┘
```

### Firebase Security Rules Example

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only access their own data
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
```

---

## Security Best Practices for Users

### DO:

- ✅ Use a strong device passcode
- ✅ Enable Face ID / Touch ID
- ✅ Enable App Lock in Axon settings
- ✅ Rotate API keys periodically
- ✅ Enable Advanced Data Protection for iCloud
- ✅ Use HTTPS for custom backends

### DON'T:

- ❌ Share your API keys
- ❌ Use HTTP (non-TLS) backends in production
- ❌ Store API keys in notes or messages
- ❌ Disable device passcode

---

## Incident Response

### If Your Device Is Lost/Stolen:

1. Use Find My iPhone to locate or erase device
2. Revoke API keys from provider dashboards:
   - OpenAI: https://platform.openai.com/api-keys
   - Anthropic: https://console.anthropic.com/settings/keys
   - Google: https://aistudio.google.com/app/apikey
3. Change Apple ID password if iCloud sync was enabled

### If You Suspect API Key Compromise:

1. Immediately revoke the key at the provider's dashboard
2. Generate a new key
3. Update the key in Axon Settings → API Keys
4. Review provider usage logs for unauthorized activity

---

## Technical Specifications

### Cryptographic Algorithms

| Purpose | Algorithm |
|---------|-----------|
| Keychain encryption | AES-256-GCM |
| iOS Data Protection | AES-256 |
| TLS | TLS 1.3 (ECDHE + AES-256-GCM) |
| iCloud encryption | AES-256 (Apple-managed keys) |

### Key Derivation

- Device keys: Derived from device UID + user passcode
- Keychain keys: Hardware-backed (Secure Enclave when available)

---

## Compliance Notes

### GDPR Considerations

- Data stored locally on user's device
- No data transmitted to methodolojee servers
- User has full control over data deletion
- Export functionality available (conversations)

### Data Portability

Users can export their data:
- Conversations: JSON export
- Memories: JSON export
- Settings: Stored in standard formats

---

## Questions?

For security-related questions:
- Email: tom@methodolojee.org
- GitHub: https://github.com/methodolojee/Axon/issues

For responsible disclosure of security vulnerabilities, please email directly rather than opening a public issue.

---

*Last Updated: December 2025*
*Version: 1.0*
