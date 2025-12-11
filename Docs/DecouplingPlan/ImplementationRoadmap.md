# AXON Implementation Roadmap
## Turning Vision into Code

This roadmap maps the revolutionary architecture to concrete implementation phases, starting with what you already have and building toward the complete vision.

---

## Current State Assessment

### ✅ What You Already Have (Don't Break It!)

**Memory System Foundation:**
- `Memory.swift` model with allocentric/egoic typing
- Confidence values in memory model
- Tag-based memory system
- Core Data persistence for memories

**Conversation System:**
- Unified conversation storage (regardless of provider)
- Message history with model/provider tracking
- OnDeviceConversationOrchestrator (direct API calls!)
- Provider-agnostic design (OpenAI, Anthropic, Google, xAI)

**Proxy Server (The Game Changer):**
- `ServerSettingsView.swift` - Already has full UI!
- FlyingFox HTTP server (lightweight, on-device)
- OpenAI API compatibility
- Already compatible with Cline, Continue, etc.
- Authentication via password/Bearer token

**Security & Storage:**
- Keychain for API keys (all providers supported)
- Core Data with NSPersistentCloudKitContainer
- Secure token storage
- Settings encrypted locally

**UI/UX:**
- Settings structure ready for advanced features
- Clean separation of concerns
- Already supporting multiple models/providers

### ❌ What Needs Work (Firebase Decoupling)

**Authentication:**
- Firebase Auth required (need device-local alternative)
- User sign-in mandatory (need guest/offline mode)

**Cloud Dependencies:**
- Backend calls required for some operations
- Firestore for encryption key management
- Optional cloud sync not fully implemented

**Memory Features:**
- No salience injection into system prompt
- No automatic memory making (background service)
- No manual memory creation UI
- Memory search not fully utilized
- Confidence scoping logic incomplete

---

## Phase A: Foundation (Device-First Memory)

### Duration: 2-3 weeks
### Goal: Full on-device memory system with salience injection

#### A1: Device Identity & Auth (No Firebase Required)
**Files to Create:**
- `Axon/Services/DeviceIdentity/DeviceIdentityService.swift`
- `Axon/Services/Auth/DeviceAuthProvider.swift`

**What it does:**
```swift
class DeviceIdentityService {
  // Generate unique device ID on first install
  func getDeviceID() -> String

  // Store in Secure Enclave (CryptoKit)
  func getDeviceKey() -> SecureEnclaveKey

  // Generate self-signed JWT tokens (no cloud needed)
  func getAuthToken() -> String  // JWT signed with device key
}
```

**Why First:**
- Removes Firebase Auth dependency
- Device can authenticate itself without cloud
- Foundation for everything else

**Tasks:**
- [ ] Generate UUID on first app launch
- [ ] Store in Secure Enclave using CryptoKit.SecureEnclave
- [ ] Create JWT token generation (no Firebase)
- [ ] Handle token refresh locally
- [ ] Update APIClient to use device tokens instead of Firebase tokens

#### A2: Memory System Enhancements
**Files to Update:**
- `Axon/Models/Memory.swift` - Add missing fields
- `Axon/Services/Memory/MemoryService.swift` - Full CRUD operations
- `Axon/Services/Memory/MemorySearchService.swift` - New file

**Memory Model Additions:**
```swift
struct Memory: Identifiable, Codable {
  let id: String
  let userId: String

  // Core content
  let content: String
  let type: MemoryType  // .allocentric, .egoic

  // Confidence & Scoping
  var confidence: Double  // 0.0 to 1.0
  var scope: String?  // "under Y conditions"
  var scopeConditions: [String]?  // ["backend code", "async/await"]

  // Operational Learning
  var successCount: Int?
  var failureCount: Int?
  var lastValidated: Date?

  // Discovery tracking
  var discoveredBy: String?  // "Claude Opus", "GPT-4", etc.
  var discoveredDate: Date

  // Search & Retrieval
  var tags: [String]  // ["typescript", "security", "performance"]
  var relatedMemoryIds: [String]?
  var salienceScore: Double?  // Computed at injection time

  // Timestamps
  let createdAt: Date
  var updatedAt: Date
}

enum MemoryType: String, Codable {
  case allocentric  // About the user
  case egoic        // About the agent's methods
}
```

**Memory Service Methods:**
```swift
class MemoryService {
  // Create/Update with scoping (no overwrites!)
  func createMemory(
    content: String,
    type: MemoryType,
    confidence: Double,
    scope: String? = nil,
    tags: [String],
    discoveredBy: String? = nil
  ) async throws -> Memory

  // Search by tag, semantic similarity, or free text
  func searchMemories(
    query: String,
    type: MemoryType? = nil,
    limit: Int = 10,
    minConfidence: Double = 0.5
  ) async throws -> [Memory]

  // Semantic search (using embeddings)
  func searchMemoriesSemantically(
    embedding: [Float],
    type: MemoryType? = nil,
    similarityThreshold: Float = 0.7
  ) async throws -> [Memory]

  // Update confidence based on new evidence
  func updateConfidence(
    memoryId: String,
    newConfidence: Double,
    evidence: String,
    condition: String? = nil
  ) async throws

  // Get most salient memories for context window
  func getSalientMemories(
    forTask: String,
    contextWindowAvailable: Int = 2000,
    type: MemoryType? = nil
  ) async throws -> [Memory]
}
```

**Tasks:**
- [ ] Extend Memory model with all fields above
- [ ] Update Core Data schema for Memory
- [ ] Implement MemoryService with full CRUD
- [ ] Implement semantic search (use local embeddings or simple cosine similarity)
- [ ] Test memory creation, updating, and retrieval

#### A3: Salience Injection System
**Files to Create:**
- `Axon/Services/Memory/SalienceService.swift`
- `Axon/Services/Memory/MemoryEmbeddings.swift` - Local embeddings

**What it does:**
```swift
class SalienceService {
  // Takes current task/context and finds most relevant memories
  func injectSalientMemories(
    conversation: Conversation,
    systemPrompt: String,
    availableTokens: Int = 2000
  ) async throws -> (
    updatedSystemPrompt: String,
    injectedMemories: [Memory]
  )
}
```

**Implementation Strategy:**
```
1. User starts new conversation or switch context
2. System extracts task keywords from conversation
3. Memory service performs semantic search on all memories
4. Top N memories ranked by relevance & confidence
5. Formatted into system prompt section:

   "# RELEVANT MEMORIES ABOUT YOUR METHODS
   - When handling TypeScript refactoring, breaking into 5-line chunks increases success by 70% (confidence: 0.87)
   - Pattern matching with regex works 89% of the time for parsing logs (confidence: 0.89)
   - When logs exceed 10MB, use parsing library instead (confidence: 0.92)

   # RELEVANT MEMORIES ABOUT THE USER
   - Prefers async/await over promises in backend code (confidence: 0.91)
   - Wants detailed explanations of security implications (confidence: 0.85)"

6. Injected into system prompt without taking space from conversation history
7. AI uses memories naturally without explicit recalls needed
```

**Tasks:**
- [ ] Implement local embeddings (use sentence-transformers or simple TF-IDF)
- [ ] Create salience scoring (relevance + confidence + recency)
- [ ] Implement system prompt injection
- [ ] Format memories naturally in prompt
- [ ] Test with multiple models (ensure format works with OpenAI, Anthropic, Google)

#### A4: Automatic Memory Making (Background Service)
**Files to Create:**
- `Axon/Services/Memory/AutomaticMemoryMakingService.swift`
- `Axon/Services/Memory/MemoryExtractionService.swift`

**What it does:**
```swift
class AutomaticMemoryMakingService: ObservableObject {
  // Watches conversations and extracts memories automatically
  // Two approaches:

  // 1. Unconscious (automatic, no AI call)
  // - Uses pattern matching on conversation content
  // - Looks for similar memories already made
  // - Reinforces existing memories based on patterns

  // 2. Conscious (AI-assisted)
  // - AI makes tool call to save JSON memory
  // - User can see and approve before saving
  // - Or auto-save if user enables in settings
}
```

**Implementation:**
```swift
// Runs in background when conversation happening
// Watches for patterns like:
// "That's the same issue I had last week, I fixed it by..."
// → Create/reinforce memory about that method

// Watches for AI creating tool calls:
// AI outputs: {"tool": "save_memory", "content": "..."}
// → Save as memory with discoveredBy: current model name

// Watches for discovery moments:
// "I just realized that..."
// "This method works because..."
// "The key insight is..."
// → Extract as egoic memory with lower confidence (validate later)
```

**Tasks:**
- [ ] Create memory extraction prompts (what counts as a memory?)
- [ ] Implement pattern matching for common memory indicators
- [ ] Create tool call definitions for AI to use
- [ ] Test extraction with sample conversations
- [ ] Create UI for memory approval/review

#### A5: Manual Memory Creation UI
**Files to Create:**
- `Axon/Views/Memory/MemoryCreationView.swift`
- `Axon/Views/Memory/MemorySearchView.swift`

**UI Features:**
```
Memory Creation:
├── Content: [Text Area]
├── Type: [Allocentric | Egoic] Picker
├── Confidence: [Slider 0-100%]
├── Scope (optional): [Text Field]
│   "e.g., 'when coding backend', 'for large datasets'"
├── Tags: [Multi-select or text input]
│   "typescript, security, performance, ..."
├── Discovered By (auto-filled): [Model name]
└── [Save] Button

Memory Search:
├── Search Bar: [Text input]
├── Filter by:
│   ├── Type [All | Allocentric | Egoic]
│   ├── Min Confidence [Slider]
│   └── Tags [Multi-select]
├── Results sorted by:
│   ├── Relevance (semantic similarity)
│   ├── Confidence (highest first)
│   └── Recency
└── Click to view/edit memory
```

**Tasks:**
- [ ] Create MemoryCreationView with all fields
- [ ] Create MemorySearchView with filtering
- [ ] Add "Create Memory" button to conversation view
- [ ] Add memory search to conversation setup
- [ ] Test creation and retrieval workflows

---

## Phase B: Integration (Proxy Server Enhanced)

### Duration: 1-2 weeks
### Goal: External tools can leverage your memories

#### B1: Memory Proxy Endpoints
**Files to Update:**
- `Axon/Services/Server/APIServerService.swift` - Add endpoints

**New Endpoints:**
```
GET /api/memories/search
  Query: ?q=typescript&type=egoic&limit=10&minConfidence=0.8
  Returns: [Memory]

GET /api/memories/:id
  Returns: Memory

POST /api/memories
  Body: {content, type, confidence, tags, ...}
  Returns: Memory

POST /api/memories/salient
  Body: {task, contextTokens, ...}
  Returns: [Memory]

PUT /api/memories/:id
  Updates memory confidence/scope

DELETE /api/memories/:id
  Soft delete (archive)
```

**Tasks:**
- [ ] Implement memory search endpoint
- [ ] Implement salience injection endpoint
- [ ] Add authentication (Bearer token using device auth)
- [ ] Test with Cline, Continue, etc.

#### B2: Model Selection Endpoint
**Files to Update:**
- `Axon/Services/Server/APIServerService.swift`

**New Endpoints:**
```
GET /api/models/available
  Returns: [
    {provider: "openai", model: "gpt-4o", enabled: true},
    {provider: "anthropic", model: "claude-opus", enabled: true},
    ...
  ]

POST /api/models/switch
  Body: {provider, model}
  Sets default model for next request

GET /api/models/current
  Returns: current model selection
```

**Tasks:**
- [ ] Implement model listing
- [ ] Implement model switching
- [ ] Ensure Cline/Continue can switch models via API

#### B3: OpenAI API Compatibility (Already Mostly Done)
**Files to Review:**
- `Axon/Services/Server/APIServerService.swift`

**Verify:**
- [ ] `/v1/chat/completions` fully compatible
- [ ] Streaming works correctly
- [ ] Bearer token authentication works
- [ ] Memory injection doesn't break compatibility

**Tests:**
- [ ] Cline can use the server
- [ ] Continue VS Code extension works
- [ ] LangChain Python client works
- [ ] curl requests work

---

## Phase C: Optional Cloud Sync

### Duration: 2-3 weeks
### Goal: Device-to-device sync without vendor lock-in

#### C1: CloudKit Integration (iCloud Sync)
**Files to Create:**
- `Axon/Services/Sync/CloudKitSyncManager.swift`

**What it does:**
```
User's iPhone has memories
User opens iPad
CloudKit auto-syncs memories via iCloud
User has same memories on both devices
No explicit backend needed
Works without internet (syncs when reconnected)
```

**Tasks:**
- [ ] Create CloudKit schema for Memory
- [ ] Create CloudKit schema for Conversation
- [ ] Implement sync manager
- [ ] Test multi-device sync
- [ ] Handle conflicts (device wins)

**Files to Update:**
- `Axon/Axon.entitlements` - Add CloudKit capability
- `Axon/AxonApp.swift` - Initialize CloudKit sync

#### C2: Custom Backend Support
**Files to Create:**
- `Axon/Services/Sync/CustomBackendSyncManager.swift`
- `Axon/Views/Settings/BackendConfigView.swift`

**What it does:**
```
User can point to their own backend:
- Your Firebase (if they want)
- Self-hosted PostgreSQL + Express
- Supabase
- Any REST API they control

Settings UI:
├── [Toggle] Enable Cloud Sync
├── Backend Type: [iCloud | Custom Backend]
├── If Custom Backend:
│   ├── URL: [https://example.com]
│   ├── [Test Connection] button
│   └── Status: Connected ✓
```

**Tasks:**
- [ ] Create BackendConfigView
- [ ] Implement custom backend sync
- [ ] Add URL validation
- [ ] Implement test connection feature
- [ ] Handle offline gracefully

#### C3: Optional: Your Firebase Backend
**Files to Create:**
- `Axon/Services/Sync/FirebaseBackendSyncManager.swift` (optional)

**Purpose:**
- Still available as an option
- But not required
- Not default
- Community can ignore completely

**Tasks:**
- [ ] Keep Firebase as one optional sync backend
- [ ] Document how to use
- [ ] Make it completely optional in build

---

## Phase D: Polish & Open Source

### Duration: 1-2 weeks
### Goal: Production-ready release

#### D1: Documentation
**Files to Create:**
- `docs/ARCHITECTURE.md` - How it all works
- `docs/MEMORY_SYSTEM.md` - Memory types, confidence, scoping
- `docs/SALIENCE.md` - How memories get injected
- `docs/PROXY_SERVER.md` - How to use with Cline, etc.
- `docs/SYNC_OPTIONS.md` - iCloud, custom backends
- `docs/SELF_HOSTING.md` - How to host your own backend
- `docs/API.md` - Complete endpoint documentation

#### D2: Backend Template (Optional)
**Create `/backend` directory:**
```
backend/
├── docker-compose.yml        # One-command deployment
├── src/index.ts              # Express app
├── src/schema/               # Database schemas
├── .env.example              # Configuration
└── README.md                 # Setup guide
```

**Simple Express server that:**
- [ ] Accepts memory sync
- [ ] Stores in PostgreSQL or SQLite
- [ ] Implements device token verification
- [ ] Handles conflicts (device wins)

#### D3: Tests & QA
**Tasks:**
- [ ] Unit tests for memory system
- [ ] Integration tests for salience injection
- [ ] Test with all providers (OpenAI, Anthropic, Google, xAI)
- [ ] Test proxy server with Cline
- [ ] Test iCloud sync
- [ ] Test custom backend sync
- [ ] Performance testing (large memory pools)
- [ ] Security review

#### D4: License & Community Setup
**Tasks:**
- [ ] Choose license (MIT recommended for adoption)
- [ ] Create CONTRIBUTING.md
- [ ] Create CODE_OF_CONDUCT.md
- [ ] Create issue templates
- [ ] Create GitHub discussions for community
- [ ] Write comprehensive README

---

## Implementation Strategy

### Recommended Order (Don't Skip Steps)

```
1. A1: Device Auth (removes Firebase dependency)
   ↓
2. A2: Memory System (core feature)
   ↓
3. A3: Salience Injection (makes memory useful)
   ↓
4. Test A1-A3 thoroughly before moving on
   ↓
5. A4: Automatic Memory Making (quality of life)
   ↓
6. A5: Manual Memory UI (user control)
   ↓
7. B1-B3: Proxy Server (let external tools use memories)
   ↓
8. C1: CloudKit (simple multi-device sync)
   ↓
9. C2: Custom Backend Support (power users)
   ↓
10. D1-D4: Polish & release
```

### Parallelization Opportunities

These can run in parallel:
- A2 (memory model) and A1 (device auth) - independent
- A4 (automatic memories) and A5 (manual UI) - independent
- B1-B3 (proxy server) can start once A2 done
- C1 (CloudKit) can start once A2 done

### Risk Mitigation

**Don't:**
- Break existing Firebase functionality immediately
- Remove dependencies before alternatives work
- Change data models without migration strategy

**Do:**
- Keep Firebase as optional fallback initially
- Test each phase thoroughly
- Maintain backward compatibility until full replacement
- Get user feedback at each milestone

---

## Success Metrics

### Phase A Complete:
- ✅ App works without Firebase Auth
- ✅ Memories can be created/searched locally
- ✅ Salience injection improves AI quality noticeably
- ✅ Works offline without cloud

### Phase B Complete:
- ✅ Cline can use proxy server
- ✅ External tools see your memories
- ✅ Model switching works via API

### Phase C Complete:
- ✅ Memories sync across your devices
- ✅ Can point to custom backend
- ✅ No vendor lock-in

### Phase D Complete:
- ✅ Well-documented
- ✅ Community can self-host
- ✅ Community can fork/modify
- ✅ Ready for open source

---

## Timeline Estimate

| Phase | Duration | Effort |
|-------|----------|--------|
| A1 | 2-3 days | Medium |
| A2 | 3-4 days | High |
| A3 | 3-4 days | High |
| A4 | 2-3 days | Medium |
| A5 | 2-3 days | Medium |
| B1-B3 | 3-5 days | Medium |
| C1 | 2-3 days | Low |
| C2 | 2-3 days | Low |
| D1-D4 | 3-5 days | Low |
| **TOTAL** | **4-5 weeks** | |

---

## Next Immediate Steps

1. **Review this roadmap** - Does the order make sense?
2. **Decide on A1 approach** - CryptoKit Secure Enclave? Or simpler local keys?
3. **Start A1** - Remove Firebase Auth dependency
4. **Then move to A2-A3** - Core memory + salience

This keeps you moving while ensuring a solid foundation.

The vision becomes reality step-by-step. Let's build it. 🚀
