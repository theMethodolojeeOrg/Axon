# NeurXAxonChat Cloud Functions API Documentation

## Overview

NeurXAxonChat is a **Firebase Cloud Functions** application, not a traditional REST API server. Each operation is implemented as a separate, independently deployable HTTP Cloud Function.

**Base URL:** `https://us-central1-neurx-8f122.cloudfunctions.net`

**Current Project:** `neurx-8f122`

**Region:** us-central1

**API Status:** Production

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Authentication](#authentication)
3. [Function Invocation](#function-invocation)
4. [Error Handling](#error-handling)
5. [Core Functions by Phase](#core-functions-by-phase)
6. [CORS Configuration](#cors-configuration)
7. [Known Issues & Inconsistencies](#known-issues--inconsistencies)

---

## Architecture Overview

### Key Differences from REST APIs

This is **NOT** a traditional REST API with path-based routing (e.g., `/api/memories`). Instead:

- **Each function is a separate endpoint**: `apiCreateMemory`, `apiGetMemories`, etc. are individual Cloud Functions
- **URLs are function names**: Each function gets its own URL: `https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateMemory`
- **HTTP methods are handled inside functions**: Each function checks `req.method` internally and returns 405 if wrong method is used
- **No centralized router**: Functions are independently deployable and don't share routing logic

### Function Types

#### 1. HTTP onRequest Functions (Most APIs)
```typescript
export const apiCreateMemory = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  // ... handler logic
});
```

**Characteristics:**
- Direct HTTP endpoint
- Manual method checking required
- CORS handling via `cors` middleware
- Request body via `req.body`
- Query parameters via `req.query`

#### 2. Callable Functions
```typescript
export const chat = functions.https.onCall(async (data, context) => {
  if (!context?.auth) {
    throw new functions.https.HttpsError('unauthenticated', '...');
  }
  // ... handler logic
});
```

**Characteristics:**
- Firebase SDK handles authentication
- Only available to authenticated users
- Simpler error handling via `HttpsError`
- Used for: `chat`, `listProviders`, admin functions

---

## Authentication

### ⚠️ CRITICAL: Authentication Inconsistencies

There are **two different authentication patterns** used across the codebase:

#### Pattern A: Bearer Token + API Key (Most REST Endpoints)

Used by most Phase 1-7 APIs:

```bash
curl -X POST 'https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateMemory?apiKey=YOUR_API_KEY' \
  -H 'Authorization: Bearer YOUR_FIREBASE_ID_TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"type":"fact","content":"...","confidence":0.9}'
```

**Requirements:**
1. **Firebase ID Token** (Bearer token in Authorization header)
   - Obtained after user authentication with Firebase
   - Expires periodically, must be refreshed

2. **API Key** (Query parameter: `?apiKey=...`)
   - Server-side validation via `checkApiKey()` function
   - **SECURITY NOTE**: Exposing API key in URL query parameter is not ideal. Consider moving to header.

#### Pattern B: Firebase Callable (SDK Functions)

Used by: `chat`, `listProviders`, admin functions

```javascript
import { getFunctions, httpsCallable } from 'firebase/functions';

const functions = getFunctions();
const callChat = httpsCallable(functions, 'chat');

const response = await callChat({
  providerId: 'anthropic',
  request: { messages: [...] }
});
```

**Requirements:**
- User must be authenticated with Firebase
- Authentication is handled automatically by Firebase SDK
- No API key needed

### Getting a Firebase ID Token

```javascript
import { getAuth, signInWithEmailAndPassword } from 'firebase/auth';

const auth = getAuth();
const userCredential = await signInWithEmailAndPassword(auth, email, password);
const idToken = await userCredential.user.getIdToken();
```

---

## Function Invocation

### HTTP onRequest Functions (REST Pattern)

```bash
# POST request with body
curl -X POST 'https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateMemory?apiKey=KEY' \
  -H 'Authorization: Bearer TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{"type":"fact","content":"...","confidence":0.9}'

# GET request with query parameters
curl -X GET 'https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemories?apiKey=KEY&limit=20&offset=0' \
  -H 'Authorization: Bearer TOKEN'

# Wrong HTTP method - will return 405
curl -X DELETE 'https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemories' \
  # Returns: { error: 'Method not allowed' } with 405 status
```

### Callable Functions (Firebase SDK)

```javascript
const response = await httpsCallable(functions, 'chat')({
  providerId: 'anthropic',
  request: { messages: [...] }
});
```

---

## Error Handling

### Error Response Formats

#### Format A: Simple Error Object (Most Common)
```json
{
  "error": "Brief error message"
}
```

#### Format B: Error with Details
```json
{
  "error": "Main error message",
  "details": {
    "field": "Additional context about the error"
  }
}
```

#### Format C: HttpsError (Callable Functions)
```json
{
  "code": "auth/unauthenticated",
  "message": "User must be authenticated",
  "details": null
}
```

### HTTP Status Codes

| Code | Meaning | Common Scenarios |
|------|---------|------------------|
| 200 | OK | Successful GET or update |
| 201 | Created | Successful resource creation |
| 400 | Bad Request | Invalid input, missing fields, validation errors |
| 401 | Unauthorized | Missing/invalid Firebase token or API key |
| 403 | Forbidden | User doesn't have permission |
| 404 | Not Found | Resource doesn't exist |
| 405 | Method Not Allowed | Wrong HTTP method (GET instead of POST, etc.) |
| 500 | Internal Server Error | Unhandled exception or Firebase/Firestore error |

### Common Error Messages

```
"Missing or invalid Authorization header"
"Invalid ID token"
"Method not allowed"
"Conversation ID is required"
"Title must be non-empty string"
"Project ID is required"
```

---

## Full Endpoint Reference

### System & Utility Functions

| Function | URL |
|----------|-----|
| `health` | `https://us-central1-neurx-8f122.cloudfunctions.net/health` |

### Phase 1: Core Memory API (Memory Management)

**Files:** `memoryAugmentedAPI.ts`, `memoryEnhancedAPI.ts`

| Function | URL |
|----------|-----|
| `apiGetModels` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetModels` |
| `apiChat` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiChat` |
| `apiCreateMemory` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateMemory` |
| `apiGetMemories` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemories` |
| `apiGetMemory` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemory` |
| `apiDeleteMemory` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiDeleteMemory` |
| `apiMemoryAnalytics` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiMemoryAnalytics` |
| `apiParseMemories` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiParseMemories` |
| `apiBatchCreateMemories` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiBatchCreateMemories` |
| `apiRetrieveMemories` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiRetrieveMemories` |
| `apiCompactMemory` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiCompactMemory` |

### Phase 2: Conversation Management API

**File:** `conversationAPI.ts`

| Function | URL |
|----------|-----|
| `apiCreateConversation` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateConversation` |
| `apiListConversations` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiListConversations` |
| `apiGetConversation` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetConversation` |
| `apiUpdateConversation` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiUpdateConversation` |
| `apiDeleteConversation` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiDeleteConversation` |
| `apiAddMessage` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiAddMessage` |
| `apiGetMessages` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMessages` |
| `apiAddMessageWithResponse` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiAddMessageWithResponse` |
| `apiRegenerateMessage` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiRegenerateMessage` |
| `apiOrchestrate` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiOrchestrate` |

### Phase 3: Artifact Management API

**File:** `artifactAPI.ts`

| Function | URL |
|----------|-----|
| `apiCreateArtifact` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateArtifact` |
| `apiListArtifacts` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiListArtifacts` |
| `apiGetArtifact` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetArtifact` |
| `apiUpdateArtifact` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiUpdateArtifact` |
| `apiDeleteArtifact` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiDeleteArtifact` |
| `apiForktArtifact` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiForktArtifact` |
| `apiGetArtifactVersions` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetArtifactVersions` |
| `apiBatchCreateArtifacts` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiBatchCreateArtifacts` |

### Phase 4: Settings & Projects API

**Files:** `settingsAPI.ts`, `projectsAPI.ts`

| Function | URL |
|----------|-----|
| `apiGetSettings` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetSettings` |
| `apiUpdateSettings` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiUpdateSettings` |
| `apiResetSettings` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiResetSettings` |
| `apiUpdateAPIKey` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiUpdateAPIKey` |
| `apiListProjects` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiListProjects` |
| `apiCreateProject` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateProject` |
| `apiGetProject` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetProject` |
| `apiUpdateProject` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiUpdateProject` |
| `apiDeleteProject` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiDeleteProject` |
| `apiGetProjectAnalytics` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetProjectAnalytics` |

### Phase 5: Audio & Tool Execution API

**Files:** `audioAPI.ts`, `toolsAPI.ts`

| Function | URL |
|----------|-----|
| `apiElevenLabs` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiElevenLabs` |
| `apiListTools` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiListTools` |
| `apiExecuteTools` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiExecuteTools` |
| `apiGetToolUsage` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetToolUsage` |

### Phase 6: Batch Operations & Import/Export

**Files:** `batchAPI.ts`, `importExportAPI.ts`

| Function | URL |
|----------|-----|
| `apiBatchOperations` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiBatchOperations` |
| `apiExportMemories` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiExportMemories` |
| `apiImportMemories` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiImportMemories` |
| `apiExportConversations` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiExportConversations` |
| `apiImportConversations` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiImportConversations` |

### Phase 7: Advanced Features & Analytics

**File:** `advancedFeaturesAPI.ts`

| Function | URL |
|----------|-----|
| `apiGetMemoryEvolutionChain` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemoryEvolutionChain` |
| `apiCreateMemoryRelationship` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateMemoryRelationship` |
| `apiGetKnowledgeMap` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetKnowledgeMap` |
| `apiGetLearningTimeline` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetLearningTimeline` |
| `apiGetInsights` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetInsights` |
| `apiGetAnalyticsSummary` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetAnalyticsSummary` |
| `apiGetSupersessionChain` | `https://us-central1-neurx-8f122.cloudfunctions.net/apiGetSupersessionChain` |

---

## CORS Configuration

The API accepts requests from the following origins:

```
- http://localhost:3000 (Local React development)
- http://localhost:5173 (Local Vite development)
- https://axon.neurx.org (Production domain)
- https://axon-neurx-chat.web.app (Firebase hosting)
- https://axon-neurx-chat.firebaseapp.com (Firebase alternate)
```

**CORS Settings:**
- Credentials: Allowed
- Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
- Headers: Content-Type, Authorization

---

## Known Issues & Inconsistencies

### 🚨 CRITICAL ISSUES

#### 1. API Key in Query Parameter (Security Risk)
**Problem:** API key is passed as a query parameter, which:
- Logs the key in browser history
- Exposes it in request logs
- Can be captured in referrer headers

**Current Location:** Most REST endpoints check `req.query.apiKey`

**Recommendation:** Move API key to `X-API-Key` header instead:
```bash
curl -X POST 'https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateMemory' \
  -H 'Authorization: Bearer TOKEN' \
  -H 'X-API-Key: YOUR_API_KEY'
```

#### 2. Inconsistent Authentication Across Functions
**Problem:** Different functions use different auth patterns:
- Some: Bearer token + API key
- Some: Bearer token only
- Some: Firebase callable with SDK authentication

**Status:** Functions should be standardized to one pattern

**Impact:** Client developers must know which pattern each function uses

#### 3. No Request/Response Schema Validation
**Problem:** Functions don't validate request bodies against a schema
- Developers can pass invalid data without clear error messages
- Response formats are inconsistent across functions

**Recommendation:** Implement validation layer with JSON Schema

### ⚠️ MODERATE ISSUES

#### 4. Inconsistent Error Response Format
**Pattern Variance:**
- Some endpoints: `{ error: "message" }`
- Some endpoints: `{ error: "message", details: {...} }`
- Some endpoints: HttpsError format (callable functions)

**Recommendation:** Standardize on single format:
```json
{
  "error": {
    "code": "invalid_argument",
    "message": "Human-readable error message",
    "details": { "field": "Additional context" }
  }
}
```

#### 5. No Centralized Request Logging
**Problem:** Debugging cross-function requests is difficult
- No correlation IDs between requests
- No structured logging format

**Recommendation:** Implement request tracing with unique IDs

#### 6. Path Parameter Extraction is Fragile
**Current Pattern:**
```typescript
const conversationId = req.path.split('/').pop();
```

**Problem:** Assumes specific URL structure that doesn't exist
- These functions are called at `/{functionName}`, not `/api/conversations/{id}`
- Path parameters cannot be extracted this way

**Status:** This suggests the code was written for a different deployment model

#### 7. Missing Error Handling for Concurrent Operations
**Problem:** Batch operations don't handle partial failures well
- Sequential mode stops on first error
- No clear error reporting for which operations succeeded/failed

### 📋 DOCUMENTATION ISSUES

#### 8. Documentation Describes REST API That Doesn't Exist
**The old documentation describes:**
- RESTful path-based routing: `POST /api/memories`, `GET /api/memories/:id`
- Centralized `/api/*` endpoints

**Reality:**
- Individual function endpoints: `POST https://.../apiCreateMemory`
- No path-based routing
- No `/api/` prefix in actual URLs

**This File:** Corrects these inaccuracies

#### 9. Missing Function Parameter Documentation
**Current State:** Individual function parameters not documented in detail
- Request body schemas
- Query parameter constraints
- Response field definitions

**Recommendation:** Add JSDoc comments with parameter definitions

---

## Quick Reference: HTTP Method Errors

Each function enforces its HTTP method. Calling with the wrong method returns:

```json
{
  "error": "Method not allowed"
}
```

With status code **405**.

**Example:**
```bash
# This will fail with 405 because apiGetMemories only accepts GET
curl -X POST 'https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemories' \
  -H 'Authorization: Bearer TOKEN' \
  -d '{"query":"python"}'

# Correct usage
curl -X GET 'https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemories' \
  -H 'Authorization: Bearer TOKEN'
```

---

## Unified Chat Orchestrator: apiOrchestrate

### Orchestrator Overview

The orchestrator is a single endpoint that handles the complete chat experience:

- Save user message
- Get LLM response with memory context
- Auto-create artifacts from code blocks
- Auto-create memories from learnings
- Execute tools if requested
- Generate audio (optional)

**All in ONE API call.**

### Request Format

```bash
curl -X POST 'https://us-central1-neurx-8f122.cloudfunctions.net/apiOrchestrate?apiKey=KEY' \
  -H 'Authorization: Bearer TOKEN' \
  -H 'Content-Type: application/json' \
  -d '{
    "conversationId": "conv-123",
    "message": "Write a Python function to sort a list",
    "provider": "anthropic",
    "options": {
      "createArtifacts": true,
      "saveMemories": true,
      "executeTools": false
    }
  }'
```

### Request Body Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `conversationId` | string | ✅ | ID of conversation to add message to |
| `message` | string | ✅ | User's message content |
| `provider` | string | ✅ | AI provider: `anthropic`, `openai`, or `gemini` |
| `options.model` | string | ❌ | Specific model ID |
| `options.temperature` | number | ❌ | Sampling temperature (0.0-1.0) |
| `options.maxTokens` | number | ❌ | Max response length |
| `options.includeMemories` | boolean | ❌ | Auto-inject memories (default: true) |
| `options.createArtifacts` | boolean | ❌ | Auto-detect and create artifacts (default: true) |
| `options.saveMemories` | boolean | ❌ | Auto-detect and create memories (default: true) |
| `options.executeTools` | boolean | ❌ | Execute tools if detected (default: false) |
| `options.generateAudio` | boolean | ❌ | Generate audio response (default: false) |
| `options.projectId` | string | ❌ | Project ID for filtering memories |

### Response Format

```json
{
  "userMessage": {
    "id": "msg-123",
    "role": "user",
    "content": "Write a Python function to sort a list",
    "conversationId": "conv-456",
    "createdAt": 1629820800000,
    "updatedAt": 1629820800000
  },

  "assistantMessage": {
    "id": "msg-789",
    "role": "assistant",
    "content": "Here's a Python function...",
    "conversationId": "conv-456",
    "createdAt": 1629820801000,
    "updatedAt": 1629820801000,
    "metadata": {
      "model": "claude-3-5-sonnet",
      "providerId": "anthropic",
      "tokensUsed": 287
    }
  },

  "artifacts": [
    {
      "id": "art-xyz",
      "type": "code",
      "language": "python",
      "title": "Sort Function",
      "content": "def sort_list(items):\n    return sorted(items)",
      "source": "auto_detected",
      "linkedMessageId": "msg-789"
    }
  ],

  "memories": [
    {
      "id": "mem-456",
      "type": "fact",
      "content": "Python's sorted() function returns a new sorted list",
      "confidence": 0.95,
      "source": "auto_detected",
      "linkedMessageId": "msg-789"
    }
  ],

  "tools": [],
  "audio": null,
  "conversationUpdated": true,

  "metadata": {
    "totalTime": 3421,
    "operationsPerformed": ["message_save", "llm_chat", "artifact_create", "memory_create"],
    "llmTime": 2100,
    "memoriesCreated": 1,
    "artifactsCreated": 1,
    "toolsExecuted": 0,
    "warnings": []
  }
}
```

### Benefits vs Separate Calls

| Metric | Separate Calls | Orchestrator |
|--------|----------------|--------------|
| API Calls | 4-6 | 1 |
| Network Round Trips | 4-6 | 1 |
| Total Time | 5-9s | 3-5s |
| Client Complexity | High | Low |
| Error Handling | Complex | Simple |
| Artifacts Auto-created | ❌ | ✅ |
| Memories Auto-created | ❌ | ✅ |

### Examples

#### Swift

```swift
let result = try await client.orchestrate(
  conversationId: convId,
  message: "Write a Python function to sort a list",
  provider: "anthropic",
  options: [
    "createArtifacts": true,
    "saveMemories": true
  ]
)

let userMsg = result.userMessage
let assistantMsg = result.assistantMessage
let artifacts = result.artifacts
let memories = result.memories
```

#### JavaScript

```javascript
const result = await client.orchestrate({
  conversationId: convId,
  message: 'Write a Python function to sort a list',
  provider: 'anthropic',
  options: {
    createArtifacts: true,
    saveMemories: true,
  },
});

console.log('Response:', result.assistantMessage.content);
console.log('Artifacts created:', result.artifacts.length);
console.log('Memories created:', result.memories.length);
```

#### Python

```python
result = client.orchestrate(
    conversation_id=conv_id,
    message='Write a Python function to sort a list',
    provider='anthropic',
    options={
        'createArtifacts': True,
        'saveMemories': True,
    }
)

print(f"Response: {result['assistantMessage']['content']}")
print(f"Artifacts: {len(result['artifacts'])}")
print(f"Memories: {len(result['memories'])}")
```

### Common Use Cases

#### Case 1: Code Generation with Auto-Artifacts

```json
{
  "message": "Write a Flask API endpoint",
  "provider": "anthropic",
  "options": {
    "createArtifacts": true,
    "saveMemories": true
  }
}
```

#### Case 2: Learning & Knowledge Building

```json
{
  "message": "Explain machine learning concepts",
  "provider": "anthropic",
  "options": {
    "saveMemories": true,
    "createArtifacts": false
  }
}
```

#### Case 3: Tool-Augmented Chat

```json
{
  "message": "Search for latest AI news and summarize",
  "provider": "anthropic",
  "options": {
    "executeTools": true,
    "saveMemories": true
  }
}
```

### Orchestrator Error Handling

If a sub-operation fails, the orchestrator completes what it can and includes warnings:

```json
{
  "userMessage": { ... },
  "assistantMessage": { ... },
  "artifacts": [ ... ],
  "memories": [],
  "tools": [],
  "metadata": {
    "warnings": [
      "Memory creation failed: rate limited",
      "Tool execution failed: timeout"
    ]
  }
}
```

Response is still 201 (partial success) or 500 (complete failure).

### Performance

- **Typical response time:** 2-5 seconds
- **Firestore operations:** ~5-8 reads, 3-4 writes
- **LLM latency:** 1-4 seconds (provider dependent)

### See Also

- [ORCHESTRATOR_DESIGN.md](ORCHESTRATOR_DESIGN.md) - Complete design documentation
- [INTEGRATED_MESSAGE_ENDPOINT.md](INTEGRATED_MESSAGE_ENDPOINT.md) - Message + response endpoint
- [Phase 2: Conversation Management API](#phase-2-conversation-management-api) - Lower-level message endpoint

---

## Migration Path from Old Documentation

If you were using the old REST API documentation:

| Old Endpoint | New Function | Method |
|-------------|-------------|--------|
| `POST /api/memories` | `apiCreateMemory` | POST |
| `GET /api/memories` | `apiGetMemories` | GET |
| `GET /api/memories/:id` | `apiGetMemory` | GET |
| `DELETE /api/memories/:id` | `apiDeleteMemory` | DELETE |
| `POST /api/conversations` | `apiCreateConversation` | POST |
| `GET /api/conversations` | `apiListConversations` | GET |
| `GET /api/conversations/:id` | `apiGetConversation` | GET |

All functions require:
- Base URL: `https://us-central1-neurx-8f122.cloudfunctions.net`
- Query parameter: `?apiKey=YOUR_API_KEY`
- Header: `Authorization: Bearer YOUR_FIREBASE_ID_TOKEN`

---

## Implementation Status

**Total Functions:** 56

**By Phase:**
- ✅ Phase 1: Core Memory API (11 endpoints)
- ✅ Phase 2: Conversation Management (10 endpoints)
- ✅ Phase 3: Artifact Management (8 endpoints)
- ✅ Phase 4: Settings & Projects (10 endpoints)
- ✅ Phase 5: Audio & Tools (4 endpoints)
- ✅ Phase 6: Batch & Import/Export (5 endpoints)
- ✅ Phase 7: Advanced Features & Analytics (7 endpoints)
- ✅ System & Utilities (1 endpoint: `health`)

**Special Endpoints:**

- `apiOrchestrate` - Unified chat orchestrator (messages, memories, artifacts, tools)

**Callable Functions:**

- `chat` - Memory-augmented chat
- `listProviders` - Get available AI providers
- Admin functions (6 functions)

---

## Last Updated

**Date:** November 19, 2025

**Changes in This Version:**
- Updated "Full Endpoint Reference" with complete list of 56 endpoints and their full URLs
- Verified all endpoints against codebase
- Updated implementation status counts
- Confirmed `apiForktArtifact` naming
- Added `health` endpoint to reference
