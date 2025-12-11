# Axon: Firebase Decoupling Plan
## On-Device-First Architecture with Optional Cloud Backend

**Vision:** "A phone is a server if you think outside the box enough" 🎯

Transform Axon into a user-centric, self-hosted capable system where:
- **On-Device First**: All data, conversation history, and memory lives locally on the device
- **Cloud as Optional**: Users can optionally sync to their own backend infrastructure if desired
- **No Cloud Requirement**: The app works 100% offline without any cloud connection
- **Self-Hostable**: Community members can run their own backend server easily
- **Backward Compatible**: Your Firebase infrastructure remains available as one optional backend

---

## Executive Summary

### Current State
- **iOS**: Uses Firebase Auth + Firestore for cloud services
- **Backend**: 40+ Cloud Functions endpoints with Firestore database
- **Architecture**: Cloud-first with local Core Data cache

### Target State
- **iOS**: On-device-first with SwiftData, supports optional backend sync
- **Backend**: Pluggable database layer (Firebase, PostgreSQL, SQLite, etc.)
- **Architecture**: Local-first with optional backend sync (yours or user's own)

### Key Insight
Axon is already well-architected for this transformation. Firebase integration is already isolated to service layers (`AuthenticationService`, `APIClient`, `EncryptionService`). We need to:
1. Replace Firebase Auth with device-local auth (device ID + device-generated keys)
2. Make backend sync fully optional with graceful offline support
3. Abstract backend storage layer for easy self-hosting

---

## Technology Stack Recommendations

### iOS App
- **Local Storage**: **SwiftData** (Apple's modern Swift-native ORM, replaces Core Data)
  - Supports encrypted storage via FileProtection
  - Full-featured encryption without external dependencies
  - Native Swift models, macros, schema management

- **On-Device Auth**: **Device Identity System**
  - Generate unique device ID on first install
  - Store encryption key in Secure Enclave (CryptoKit)
  - Optional cloud sync for device-to-device sync within user's account

- **Optional Cloud Sync**: Pluggable backend protocol
  - Users can point to their own backend URL
  - Support for device-to-device sync via user's backend
  - No cloud requirement - fully functional offline

### Backend (Optional, User-Provided)
- **Database Options**:
  - **SQLite** (simplest, single-machine deployment)
  - **PostgreSQL** (multi-user, multi-device sync)
  - **MongoDB** (if users prefer document-oriented)

- **Runtime Options**:
  - **Express.js** (simplest, port existing Cloud Functions)
  - **Docker Compose** (one-command deployment)
  - **Cloudflare Workers** (serverless, free tier available)

- **Auth**: Device token system (not Firebase Auth)
  - Device generates JWT tokens signed with local keys
  - Backend verifies token signature
  - No central auth required

---

## Core Components to Refactor

### Phase 1: On-Device Storage (Weeks 1-2)

#### 1.1 Migrate Core Data → SwiftData
**Files**:
- `Axon/Persistence.swift` - Replace NSPersistentCloudKitContainer
- `Axon/Models/*.swift` - Convert to SwiftData @Model macros

**Tasks**:
- [ ] Create SwiftData models for Conversation, Message, Memory, Artifact
- [ ] Remove CloudKit configuration
- [ ] Implement encryption at rest using FileProtection
- [ ] Update all Core Data access to use SwiftData
- [ ] Test data migration from old Core Data schema

**Why SwiftData?**
- Apple's modern framework (2023+)
- Swift-native, no Objective-C bridge
- Built-in encryption support
- Better performance than Core Data
- Same functionality, cleaner syntax

#### 1.2 Create Device Identity System
**New Files**:
- `Axon/Services/DeviceIdentity/DeviceIdentityService.swift`
- `Axon/Services/DeviceIdentity/DeviceKeyManager.swift`

**Tasks**:
- [ ] Generate unique device ID on first app install
- [ ] Store device ID in Secure Enclave via CryptoKit
- [ ] Create device-specific encryption key pair (Ed25519 for signing)
- [ ] Generate self-signed JWT tokens for API calls
- [ ] Handle device-to-device sync via user's account (optional)

**Key Methods**:
```swift
class DeviceIdentityService {
  func getDeviceID() -> String
  func getDeviceToken() -> String  // JWT signed with device key
  func validateToken(_ token: String) -> Bool
  func refreshToken() async -> String
}
```

**Benefits**:
- No cloud service required for authentication
- Device-to-device communication still possible via optional backend
- Each device is its own authority
- Perfect for offline-first apps

---

### Phase 2: On-Device Auth & Optional Cloud (Weeks 2-3)

#### 2.1 Replace Firebase Auth with Device Auth
**Files to Refactor**:
- `Axon/Services/Auth/AuthenticationService.swift` - Completely rewrite
- `Axon/Views/Settings/AccountSettingsView.swift` - Remove Firebase UI

**Current Firebase Dependencies**:
```swift
// Lines 23-24 in APIClient.swift - these are the KEY dependencies
private var authService: AuthenticationService { AuthenticationService.shared }
private var tokenStorage: SecureTokenStorage { SecureTokenStorage.shared }
```

**New Architecture**:
```swift
protocol AuthProvider {
  func getAuthToken() async -> String
  func refreshToken() async throws -> String
  func logout() async throws
  var isAuthenticated: Bool { get }
}

// Default: Device Auth (no cloud required)
class DeviceAuthProvider: AuthProvider {
  let deviceIdentity: DeviceIdentityService
  // Local-only auth, generates JWT tokens
}

// Optional: Cloud Auth (if user wants sync)
class CloudAuthProvider: AuthProvider {
  let backendURL: URL
  let deviceIdentity: DeviceIdentityService
  // Syncs with user's backend
}
```

**Tasks**:
- [ ] Create AuthProvider protocol
- [ ] Implement DeviceAuthProvider (default, offline-capable)
- [ ] Refactor AuthenticationService to use protocol
- [ ] Update APIClient to accept any AuthProvider
- [ ] Remove all Firebase Auth imports
- [ ] Update AccountSettingsView to show device ID instead of email

**Result**:
- App fully functional without cloud
- Firebase Auth completely removed
- Users can optionally enable cloud sync

#### 2.2 Create Optional Cloud Backend Configuration
**New Files**:
- `Axon/Services/Configuration/BackendConfiguration.swift`
- `Axon/Views/Settings/BackendSettingsView.swift`

**Tasks**:
- [ ] Create BackendConfiguration struct (optional URL, credentials)
- [ ] Store in UserDefaults (unencrypted, it's just a URL)
- [ ] Add Settings UI to enable/disable cloud sync
- [ ] Create APIClientConfigurable protocol
- [ ] Update APIClient to use config (Firebase endpoint → user's endpoint)

**Result**:
- Users can point app to their own backend
- Falls back to on-device-only if no backend configured
- Easy one-tap backend switching

---

### Phase 3: Optional Cloud Sync Layer (Weeks 3-4)

#### 3.1 Create Optional Cloud Sync Service
**New Files**:
- `Axon/Services/Sync/SyncService.swift` - Coordinates cloud sync
- `Axon/Services/Sync/BackendSyncProvider.swift` - Protocol for different backends
- `Axon/Services/Sync/FirebaseCloudSyncProvider.swift` - Your Firebase backend
- `Axon/Services/Sync/GenericBackendSyncProvider.swift` - Custom backends

**Architecture**:
```swift
protocol BackendSyncProvider {
  // Conversations
  func listConversations(since: Date?) async throws -> [Conversation]
  func createConversation(_ data: ConversationData) async throws -> Conversation
  func updateConversation(_ id: String, _ data: ConversationData) async throws
  func deleteConversation(_ id: String) async throws

  // Messages
  func listMessages(conversationId: String) async throws -> [Message]
  func createMessage(_ message: Message) async throws

  // Memories
  func listMemories(since: Date?) async throws -> [Memory]
  func createMemory(_ memory: Memory) async throws
  // ... etc
}

class SyncService {
  var provider: BackendSyncProvider? // nil = offline-only

  // Push local changes to cloud
  func pushChanges() async throws

  // Pull changes from cloud
  func pullChanges() async throws

  // Bidirectional sync with conflict resolution
  func sync() async throws
}
```

**Tasks**:
- [ ] Create BackendSyncProvider protocol
- [ ] Implement for Firebase (your current backend)
- [ ] Implement for generic HTTP/REST backend
- [ ] Create SyncService to manage optional sync
- [ ] Handle sync conflicts (device wins in case of conflict)
- [ ] Implement delta sync using timestamps
- [ ] Add retry logic with exponential backoff
- [ ] Handle network-down gracefully

**Sync Strategy**:
- **On-device first**: Always load from SwiftData immediately
- **Background sync**: Sync to backend in background if configured
- **Device wins**: Local changes always take priority
- **Graceful offline**: Works perfectly without backend
- **No data loss**: All changes stored locally, synced when backend available

#### 3.2 Update Conversation & Memory Services
**Files to Update**:
- `Axon/Services/Conversation/ConversationService.swift`
- `Axon/Services/Conversation/ConversationSyncManager.swift`
- `Axon/Services/Memory/MemoryService.swift`
- `Axon/Services/Memory/MemorySyncManager.swift`

**Changes**:
- [ ] Inject SyncService instead of APIClient
- [ ] Check if backend sync is configured
- [ ] Load from SwiftData first (always fast)
- [ ] Background sync if backend available
- [ ] Handle backend unavailability gracefully
- [ ] Remove Firestore-specific logic

**Result**:
- Services work offline-only OR with optional backend
- No changes to business logic
- Graceful fallback when backend unavailable

---

### Phase 4: Settings & Encryption Management (Week 4)

#### 4.1 Simplify Settings Management
**Files to Update**:
- `Axon/Services/Settings/SettingsStorage.swift` - Remove Firestore
- `Axon/Services/Encryption/EncryptionService.swift` - Simplify
- `Axon/Services/Encryption/SettingsCloudSyncService.swift` - Remove

**Current Complexity**:
```swift
// Current: Settings synced to Firestore encrypted
// users/{userId}/settings/appSettings

// New: Settings stored locally, optionally synced to user's backend
```

**Changes**:
- [ ] Keep AppSettings in UserDefaults (local only)
- [ ] API keys stay in Keychain (device-local, no sync)
- [ ] Remove Firestore encryption service
- [ ] Remove automatic cloud settings sync
- [ ] Optionally: Add manual "export settings" feature

**Result**:
- Simpler implementation
- No cloud sync of sensitive keys (more secure!)
- Users control their own keys
- Can manually backup settings

#### 4.2 Update Encryption Service
**Files**:
- `Axon/Services/Encryption/EncryptionService.swift`

**Changes**:
- [ ] Remove Firestore integration
- [ ] Keep ChaCha20-Poly1305 encryption for local data
- [ ] Master key = DeviceIdentityService.deviceKey (not user ID)
- [ ] All encryption local only
- [ ] No cloud key management needed

**Result**:
- Encryption completely device-local
- No cloud dependencies
- Better security (no key exposure)

---

### Phase 5: Backend Services (Optional Implementation)

#### 5.1 Create Express.js Backend Template
**New Repo/Directory**: `/backend`

**Structure**:
```
backend/
├── docker-compose.yml        # One-command deployment
├── src/
│   ├── index.ts              # Express app
│   ├── config/
│   │   └── database.ts        # SQLite or PostgreSQL config
│   ├── middleware/
│   │   └── auth.ts            # Device token verification
│   ├── routes/
│   │   ├── conversations.ts
│   │   ├── messages.ts
│   │   ├── memories.ts
│   │   └── artifacts.ts
│   ├── controllers/
│   │   └── [entity].ts
│   └── models/
│       └── [schema].ts
├── Dockerfile
└── .env.example
```

**Tasks**:
- [ ] Port Cloud Functions to Express
- [ ] Support SQLite + PostgreSQL via Knex
- [ ] Implement device token verification
- [ ] Implement sync endpoints (list, delta sync, upsert)
- [ ] Add Docker Compose for easy deployment
- [ ] Write deployment documentation

**Key Endpoints** (not Firebase-specific):
```
POST   /auth/token           # Get device token (device auth)
POST   /sync/conversations   # List conversations (delta sync)
POST   /sync/messages        # List messages
POST   /sync/memories        # List memories
POST   /conversation         # Create conversation
PUT    /conversation/:id     # Update conversation
DELETE /conversation/:id     # Delete conversation
```

**Benefits**:
- Users can run on their own hardware
- Docker makes deployment trivial
- No serverless/cloud required
- Full control over data

#### 5.2 Database Schema for Self-Hosted Backend
**Files**:
- `backend/src/schema/migrations/001_init.sql`

**Tables** (SQLite/PostgreSQL compatible):
```sql
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  public_key TEXT NOT NULL,      -- Device's public key for token verification
  created_at DATETIME DEFAULT NOW(),
  last_seen DATETIME DEFAULT NOW()
);

CREATE TABLE users (
  id TEXT PRIMARY KEY,            -- Could be email or device ID
  device_id TEXT REFERENCES devices(id),
  created_at DATETIME DEFAULT NOW()
);

CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id),
  title TEXT,
  summary TEXT,
  archived BOOLEAN DEFAULT FALSE,
  created_at DATETIME DEFAULT NOW(),
  updated_at DATETIME DEFAULT NOW(),
  UNIQUE(user_id, id)
);

CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT REFERENCES conversations(id),
  content TEXT,
  role TEXT,  -- 'user' or 'assistant'
  created_at DATETIME DEFAULT NOW()
);

CREATE TABLE memories (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id),
  content TEXT,
  type TEXT,   -- 'allocentric', 'egoic'
  confidence REAL,
  created_at DATETIME DEFAULT NOW(),
  updated_at DATETIME DEFAULT NOW()
);

-- Indexes for fast delta sync
CREATE INDEX idx_conversations_updated_at ON conversations(user_id, updated_at);
CREATE INDEX idx_messages_created_at ON messages(conversation_id, created_at);
CREATE INDEX idx_memories_updated_at ON memories(user_id, updated_at);
```

---

### Phase 6: Update iOS App for Self-Hosted Support

#### 6.1 Backend Configuration UI
**Files**:
- `Axon/Views/Settings/BackendSettingsView.swift` (new)

**Features**:
- [ ] Optional backend URL input (text field)
- [ ] Test backend connection button
- [ ] Show sync status (connected/offline/failed)
- [ ] Option to revert to offline-only
- [ ] Backend sync history log

**UI Flow**:
```
Settings > Advanced > Cloud Backend
├── [Toggle] Enable Cloud Sync
├── Backend URL: [https://my-backend.example.com]
├── [Button] Test Connection
└── Sync Status: Connected ✓
```

#### 6.2 Update APIClient for Pluggable Backends
**File**: `Axon/Services/API/APIClient.swift`

**Changes**:
- [ ] Add BackendConfiguration injection
- [ ] Support both Firebase and custom backend URLs
- [ ] Fall back to offline if backend unavailable
- [ ] Make backend completely optional
- [ ] Remove Firebase-specific code paths

**Current Code** (lines 55, 102-104):
```swift
// Current: Hard-coded Firebase endpoint
guard var urlComponents = URLComponents(
  url: config.environment.apiURL.appendingPathComponent(path),
  resolvingAgainstBaseURL: false
) else { ... }

// Future: Use BackendConfiguration
if let backendURL = BackendConfiguration.shared.backendURL {
  urlComponents = URLComponents(url: backendURL.appendingPathComponent(path), ...)
} else {
  // No backend configured - handle offline
}
```

#### 6.3 Settings & Memory Managers
**Files**:
- `Axon/Services/Conversation/ConversationSyncManager.swift`
- `Axon/Services/Memory/MemorySyncManager.swift`

**Changes**:
- [ ] Check if backend configured before sync
- [ ] Handle backend unavailable gracefully
- [ ] Load from SwiftData immediately
- [ ] Background sync if backend available
- [ ] No errors if backend offline

---

### Phase 7: Documentation & Community Support

#### 7.1 Update README
**Tasks**:
- [ ] Document on-device-first architecture
- [ ] Add "works offline" badge
- [ ] Link to self-hosting guide
- [ ] Document privacy/security model
- [ ] Show architecture diagram

#### 7.2 Self-Hosting Guide
**New File**: `docs/SELF_HOSTING.md`

**Contents**:
- [ ] System requirements (minimal)
- [ ] Docker Compose quickstart (one command)
- [ ] SQLite vs PostgreSQL choice
- [ ] Configuring iOS app to point to backend
- [ ] Backup & restore procedures
- [ ] Troubleshooting guide
- [ ] Security considerations

**Quick Start Example**:
```bash
# 1. Clone backend
git clone https://github.com/yourusername/axon-backend.git
cd axon-backend

# 2. Start everything with Docker Compose
docker-compose up -d

# 3. Note the backend URL (http://localhost:5000)

# 4. In Axon iOS app:
# Settings > Advanced > Cloud Backend
# Enable Cloud Sync
# Enter: http://localhost:5000
# Tap "Test Connection" ✓
```

#### 7.3 Architecture Documentation
**New File**: `docs/ARCHITECTURE.md`

**Sections**:
- [ ] On-device-first data flow
- [ ] Optional cloud backend architecture
- [ ] Device identity & token system
- [ ] Sync strategy (delta sync, conflict resolution)
- [ ] Supported backend options
- [ ] Security model
- [ ] Privacy guarantees

#### 7.4 API Documentation
**New File**: `docs/API.md` or `/backend/API.md`

**Endpoints**:
- [ ] Document all sync endpoints
- [ ] Device auth flow
- [ ] Token format (JWT)
- [ ] Error codes
- [ ] Example requests/responses

---

## Files to Remove/Delete

These Firebase-specific files can be safely removed:

### iOS App
- [ ] `Axon/GoogleService-Info.plist` - Firebase config (or keep for reference)
- [ ] `Axon/Config/FirebaseConfig.swift` - Firebase-specific config
- [ ] `Axon/Services/Encryption/SettingsCloudSyncService.swift` - Firestore sync
- [ ] Any Firebase initialization code in `AxonApp.swift`

### Dependencies
- [ ] Remove FirebaseAuth from Package.json
- [ ] Remove FirebaseFirestore from Package.json
- [ ] Remove FirebaseFunctions from Package.json
- [ ] Keep other Firebase packages if used (might be Analytics, etc.)

---

## Files to Refactor (With Minimal Changes)

These files need updates but stay mostly the same:

### iOS App
- [ ] `Axon/Services/Auth/AuthenticationService.swift` - Replace Firebase Auth with device auth
- [ ] `Axon/Services/API/APIClient.swift` - Support pluggable backends (mostly same code)
- [ ] `Axon/Services/Encryption/EncryptionService.swift` - Remove Firestore, keep crypto
- [ ] `Axon/Services/Settings/SettingsStorage.swift` - Remove cloud sync
- [ ] `Axon/Views/Settings/AccountSettingsView.swift` - Show device ID instead of email
- [ ] `Axon/ViewModels/SettingsViewModel.swift` - Remove Firestore calls
- [ ] `Axon/AxonApp.swift` - Remove Firebase.configure() call

---

## Migration Path (No Data Loss)

### For Your Current Firebase Users
1. **Phase 1-5 Complete**: Firebase backend still works as one option
2. **User's Choice**: They can:
   - **Option A**: Keep using your Firebase backend (unchanged)
   - **Option B**: Switch to offline-only mode (all data stays local)
   - **Option C**: Self-host their own backend and migrate

3. **Data Export** (optional feature):
   - Add "Export All Data" button in settings
   - Exports conversations, messages, memories as JSON
   - Can import into self-hosted backend

### For New Users
1. App works 100% offline from day 1
2. Optionally configure backend (yours or their own)
3. No Firebase account required
4. No lock-in

---

## Security Model

### On-Device Encryption
- **Master Key**: Stored in Secure Enclave via CryptoKit
- **Derived Keys**: Per-conversation encryption (optional)
- **Algorithm**: ChaCha20-Poly1305 (same as current)
- **Key Derivation**: Device ID + salt (not user ID)

### Device Authentication
- **Device ID**: UUID generated on first install
- **Device Key**: Ed25519 keypair in Secure Enclave
- **Token**: Self-signed JWT
  ```
  {
    "sub": "device-id-xyz",
    "iat": 1703001000,
    "exp": 1703087400,
    "iss": "axon-device"
  }
  ```
- **Signature**: Device private key (never leaves Secure Enclave)

### Backend Security (if used)
- **Device Token Verification**: Backend verifies JWT signature with device's public key
- **No Passwords**: Device tokens are the only auth mechanism
- **Token Rotation**: Regular refresh (24 hours)
- **Encrypted Transport**: HTTPS/TLS only

### Privacy Guarantees
- **On-Device**: All data stays on device (unless sync enabled)
- **End-to-End**: If synced, only device can decrypt (keys never shared)
- **No Tracking**: No analytics, telemetry, or user tracking (unless user self-hosts)
- **Open Source**: Community can audit code

---

## Implementation Timeline Estimate

| Phase | Task | Duration | Complexity |
|-------|------|----------|-----------|
| 1 | Migrate Core Data → SwiftData | 3-4 days | Medium |
| 2 | Device Identity & Auth | 3-4 days | High |
| 3 | Optional Cloud Sync | 4-5 days | High |
| 4 | Settings & Encryption | 2-3 days | Low |
| 5 | Backend Template | 5-7 days | High |
| 6 | iOS App Updates | 2-3 days | Low |
| 7 | Documentation | 3-4 days | Low |
| | **TOTAL** | **4-5 weeks** | |

**Note**: Can be parallelized - phases 1-2 and 5 can run simultaneously.

---

## Success Criteria

✅ **Offline First**
- [ ] App fully functional without internet
- [ ] All conversations, messages, memories accessible offline
- [ ] UI responsive with instant local loads

✅ **Optional Cloud**
- [ ] User can optionally enable cloud sync
- [ ] Backend URL configurable in settings
- [ ] Graceful fallback if backend unavailable
- [ ] Zero errors if backend offline

✅ **Self-Hostable**
- [ ] Backend runs in Docker Compose (one command)
- [ ] Works with SQLite (no PostgreSQL required)
- [ ] Easy setup guide for non-technical users
- [ ] Sample deployment instructions

✅ **Backward Compatible**
- [ ] Firebase backend still works (if kept)
- [ ] Existing Firebase users not disrupted
- [ ] Data export/migration path available

✅ **Secure**
- [ ] Device-local encryption working
- [ ] No passwords/passwords exposed
- [ ] Tokens properly validated
- [ ] No default API keys in code

✅ **Community Ready**
- [ ] Clear architecture documentation
- [ ] API documentation
- [ ] Self-hosting guide
- [ ] Contribution guidelines

---

## Rough Task Breakdown by File

### Phase 1: SwiftData Migration
- [ ] Axon/Persistence.swift - Replace NSPersistentCloudKitContainer
- [ ] Axon/Models/Conversation.swift - Add @Model macro
- [ ] Axon/Models/Message.swift - Add @Model macro
- [ ] Axon/Models/Memory.swift - Add @Model macro
- [ ] Axon/Models/Artifact.swift - Add @Model macro

### Phase 2: Device Auth
- [ ] Axon/Services/DeviceIdentity/DeviceIdentityService.swift (NEW)
- [ ] Axon/Services/DeviceIdentity/DeviceKeyManager.swift (NEW)
- [ ] Axon/Services/Auth/AuthenticationService.swift - Rewrite
- [ ] Axon/Services/API/APIClient.swift - Update auth flow
- [ ] Axon/Views/Settings/AccountSettingsView.swift - Remove Firebase UI

### Phase 3: Optional Cloud Sync
- [ ] Axon/Services/Configuration/BackendConfiguration.swift (NEW)
- [ ] Axon/Services/Sync/SyncService.swift (NEW)
- [ ] Axon/Services/Sync/BackendSyncProvider.swift (NEW)
- [ ] Axon/Services/Sync/FirebaseCloudSyncProvider.swift (NEW)
- [ ] Axon/Services/Sync/GenericBackendSyncProvider.swift (NEW)
- [ ] Axon/Services/Conversation/ConversationService.swift - Update
- [ ] Axon/Services/Conversation/ConversationSyncManager.swift - Update
- [ ] Axon/Services/Memory/MemoryService.swift - Update
- [ ] Axon/Services/Memory/MemorySyncManager.swift - Update

### Phase 4: Encryption & Settings
- [ ] Axon/Services/Encryption/EncryptionService.swift - Simplify
- [ ] Axon/Services/Encryption/SettingsCloudSyncService.swift - DELETE
- [ ] Axon/Services/Settings/SettingsStorage.swift - Update
- [ ] Axon/ViewModels/SettingsViewModel.swift - Remove cloud calls

### Phase 5: UI & Config
- [ ] Axon/Views/Settings/BackendSettingsView.swift (NEW)
- [ ] Axon/Config/FirebaseConfig.swift - Refactor/Delete
- [ ] Axon/AxonApp.swift - Remove Firebase init

### Phase 6: Documentation
- [ ] README.md - Update
- [ ] docs/ARCHITECTURE.md (NEW)
- [ ] docs/SELF_HOSTING.md (NEW)
- [ ] docs/API.md (NEW)
- [ ] backend/ directory (NEW) - Full Express.js template

---

## Why This Approach Works

### For You
- Firebase backend remains optional (no disruption to current infrastructure)
- Users who like your system can keep using it
- Users who want independence can self-host
- No pressure to maintain centralized infrastructure

### For Users
- Complete control over their data
- No vendor lock-in
- Works offline (critical for reliability)
- Can use your backend, their own, or neither
- Community can contribute/improve

### For the Community
- Can fork and customize
- Can run on their own servers
- Full architectural transparency
- Easy to understand codebase

### Technically Sound
- All data stored locally first (fast)
- Optional sync doesn't slow down local operations
- Graceful degradation if backend unavailable
- Clear separation of concerns
- Easy to test (mock backend)

---

## Next Steps

1. **Clarification** (Done! ✓)
   - [x] Understand vision: on-device-first, cloud optional
   - [x] Choose tech stack: SwiftData + device auth + optional backend
   - [x] Review current architecture

2. **Phase 1 Planning** (Start here)
   - [ ] Create detailed SwiftData migration plan
   - [ ] Map Core Data entities → SwiftData models
   - [ ] Plan encryption strategy

3. **Phase 1 Implementation**
   - [ ] Start with Persistence.swift migration
   - [ ] Convert models one by one
   - [ ] Test with sample data

Would you like me to dive deeper into any specific phase, start with Phase 1 implementation, or refine any aspect of this plan?

---

## References & Resources

- [Apple SwiftData Documentation](https://developer.apple.com/documentation/swiftdata)
- [What's new in SwiftData - WWDC24](https://developer.apple.com/videos/play/wwdc2024/10137/)
- [Multipeer Connectivity Framework](https://developer.apple.com/documentation/multipeerconnectivity)
- [CloudKit Alternatives](https://blog.back4app.com/cloudkit-alternatives/)
- [CryptoKit - Secure Enclave](https://developer.apple.com/documentation/cryptokit)
