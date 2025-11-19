# NeurXAxonChat API Documentation

## Overview

Complete REST API for the NeurXAxonChat platform, providing full access to memory management, conversations, artifacts, settings, analytics, and more. All endpoints require Firebase authentication and API key validation.

**Base URL:** `https://us-central1-neurx-axon-chat.cloudfunctions.net`

**API Version:** 1.0.0
**Last Updated:** October 28, 2025

---

## Table of Contents

1. [Authentication](#authentication)
2. [Common Response Formats](#common-response-formats)
3. [Error Handling](#error-handling)
4. [Phase 1: Core Memory API](#phase-1-core-memory-api)
5. [Phase 2: Conversation Management API](#phase-2-conversation-management-api)
6. [Phase 3: Artifact Management API](#phase-3-artifact-management-api)
7. [Phase 4: Settings & Projects API](#phase-4-settings--projects-api)
8. [Phase 5: Audio & Tool Execution API](#phase-5-audio--tool-execution-api)
9. [Phase 6: Batch Operations & Import/Export](#phase-6-batch-operations--importexport)
10. [Phase 7: Advanced Features & Analytics](#phase-7-advanced-features--analytics)
11. [Rate Limiting](#rate-limiting)
12. [CORS Configuration](#cors-configuration)

---

## Authentication

### Requirements

Every request requires two forms of authentication:

1. **API Key** (Query Parameter)
   ```
   ?apiKey=YOUR_ADMIN_KEY
   ```

2. **Firebase ID Token** (Authorization Header)
   ```
   Authorization: Bearer <Firebase_ID_Token>
   ```

### Example Request

```bash
curl -X GET 'https://us-central1-neurx-axon-chat.cloudfunctions.net/api/memories?apiKey=YOUR_ADMIN_KEY' \
  -H 'Authorization: Bearer eyJhbGciOiJSUzI1NiIs...'
```

### Getting a Firebase ID Token

```javascript
import { getAuth, signInWithEmailAndPassword } from "firebase/auth";

const auth = getAuth();
const userCredential = await signInWithEmailAndPassword(auth, email, password);
const idToken = await userCredential.user.getIdToken();
```

---

## Common Response Formats

### Success Response (2xx)

```json
{
  "data": {
    "id": "uuid",
    "content": "...",
    "createdAt": 1729123456789
  }
}
```

Or for list responses:

```json
{
  "data": [
    { "id": "uuid1", "content": "..." },
    { "id": "uuid2", "content": "..." }
  ],
  "pagination": {
    "offset": 0,
    "limit": 50,
    "total": 123,
    "hasMore": true
  }
}
```

### Error Response (4xx, 5xx)

```json
{
  "error": "Brief error message",
  "details": {
    "field": "Additional context"
  }
}
```

---

## Error Handling

### HTTP Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| 200 | OK | Successful GET/PATCH |
| 201 | Created | Successful POST (creation) |
| 400 | Bad Request | Invalid input, missing fields |
| 401 | Unauthorized | Invalid API key or token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource doesn't exist |
| 405 | Method Not Allowed | Wrong HTTP method |
| 500 | Server Error | Internal server error |

### Common Error Responses

```json
{
  "error": "Missing required query parameter: apiKey"
}
```

```json
{
  "error": "Invalid API key"
}
```

```json
{
  "error": "Missing or invalid authorization header"
}
```

---

# Phase 1: Core Memory API

Store, retrieve, and manage memories with intelligent compression and relevance scoring.

## POST /api/memories/parse

Parse memory tags from LLM response text and extract structured memories.

**Method:** POST
**Auth:** Required (API Key + Firebase Token)

### Request Body

```json
{
  "responseText": "Here's what I learned:\n<memory type=\"fact\" confidence=\"0.9\">\nPython uses indentation for blocks\n</memory>",
  "projectId": "project-uuid"
}
```

### Response (201 Created)

```json
{
  "data": {
    "memories": [
      {
        "id": "mem-uuid-1",
        "type": "fact",
        "content": "Python uses indentation for blocks",
        "confidence": 0.9,
        "tags": [],
        "projectId": "project-uuid",
        "createdAt": 1729123456789
      }
    ],
    "parseCount": 1,
    "failureCount": 0
  }
}
```

---

## POST /api/memories/batch

Create multiple memories in a single request with server-side validation and compression.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "memories": [
    {
      "type": "fact",
      "content": "Machine learning models require large datasets",
      "confidence": 0.8,
      "tags": ["ml", "data"],
      "projectId": "project-uuid"
    }
  ]
}
```

### Response (201 Created)

```json
{
  "data": {
    "created": 1,
    "memories": [
      {
        "id": "mem-uuid-1",
        "type": "fact",
        "content": "Machine learning models require large datasets",
        "confidence": 0.8,
        "createdAt": 1729123456789
      }
    ]
  }
}
```

---

## POST /api/memories/:id/compact

Trigger memory compaction using Haiku to create a condensed version.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "memoryId": "mem-uuid-1"
}
```

### Response (200 OK)

```json
{
  "data": {
    "id": "mem-uuid-1",
    "original": "Machine learning models require large datasets...",
    "compact": "ML models need large datasets",
    "compressionRatio": 0.65
  }
}
```

---

## GET /api/memories/retrieve

Context-aware memory retrieval with intelligent relevance scoring.

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| query | string | Search query (required) |
| projectId | string | Filter by project |
| maxMemories | number | Max results (default: 10) |
| minConfidence | number | Minimum confidence (0-1) |

### Response (200 OK)

```json
{
  "data": {
    "query": "python loops",
    "memories": [
      {
        "id": "mem-uuid-1",
        "content": "Python for loops iterate over sequences",
        "confidence": 0.92,
        "tags": ["python", "loops"],
        "relevanceScore": 0.87
      }
    ]
  }
}
```

---

# Phase 2: Conversation Management API

Full lifecycle management of conversations with message history and memory injection.

## POST /api/conversations

Create a new conversation.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "title": "Python Learning Session",
  "projectId": "project-uuid"
}
```

### Response (201 Created)

```json
{
  "data": {
    "id": "conv-uuid-1",
    "title": "Python Learning Session",
    "projectId": "project-uuid",
    "messageCount": 0,
    "createdAt": 1729123456789
  }
}
```

---

## GET /api/conversations

List user's conversations with pagination and filtering.

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| limit | number | Results per page (default: 50) |
| offset | number | Pagination offset (default: 0) |
| projectId | string | Filter by project ID |
| sort | string | Sort order: -createdAt\|-updatedAt\|title |

### Response (200 OK)

```json
{
  "data": [
    {
      "id": "conv-uuid-1",
      "title": "Python Learning Session",
      "messageCount": 5,
      "createdAt": 1729123456789
    }
  ],
  "pagination": {
    "offset": 0,
    "limit": 50,
    "total": 42,
    "hasMore": true
  }
}
```

---

## GET /api/conversations/:id

Retrieve a single conversation with full message history.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "id": "conv-uuid-1",
    "title": "Python Learning Session",
    "messages": [
      {
        "id": "msg-1",
        "role": "user",
        "content": "How do Python loops work?",
        "createdAt": 1729123456789
      }
    ]
  }
}
```

---

## PATCH /api/conversations/:id

Update conversation metadata.

**Method:** PATCH
**Auth:** Required

### Request Body

```json
{
  "title": "Advanced Python Concepts"
}
```

### Response (200 OK)

```json
{
  "data": {
    "id": "conv-uuid-1",
    "title": "Advanced Python Concepts",
    "updatedAt": 1729123456890
  }
}
```

---

## DELETE /api/conversations/:id

Delete a conversation (soft delete by default).

**Method:** DELETE
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "id": "conv-uuid-1",
    "deleted": true,
    "mode": "soft"
  }
}
```

---

## POST /api/conversations/:id/messages

Add a message to a conversation.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "role": "user",
  "content": "What are decorators in Python?"
}
```

### Response (201 Created)

```json
{
  "data": {
    "id": "msg-uuid-1",
    "role": "user",
    "content": "What are decorators in Python?"
  }
}
```

---

## GET /api/conversations/:id/messages

Get paginated messages from a conversation.

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| limit | number | Max messages (default: 50) |
| offset | number | Pagination offset |

### Response (200 OK)

```json
{
  "data": [
    {
      "id": "msg-1",
      "role": "user",
      "content": "Hello"
    }
  ],
  "pagination": {
    "total": 12,
    "hasMore": false
  }
}
```

---

# Phase 3: Artifact Management API

Create, manage, and version code artifacts and structured content.

## POST /api/artifacts

Create an artifact from parsed content or raw XML.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "type": "code",
  "language": "python",
  "title": "Fibonacci Function",
  "code": "def fib(n):\n  if n <= 1:\n    return n\n  return fib(n-1) + fib(n-2)",
  "conversationId": "conv-uuid-1"
}
```

### Response (201 Created)

```json
{
  "data": {
    "id": "art-uuid-1",
    "type": "code",
    "language": "python",
    "title": "Fibonacci Function",
    "code": "def fib(n):\n  ...",
    "versionCount": 1,
    "createdAt": 1729123456789
  }
}
```

---

## GET /api/artifacts

List artifacts with filtering and pagination.

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| limit | number | Results per page (default: 50) |
| type | string | Filter by type: code\|text\|diagram |
| conversationId | string | Filter by conversation |
| sort | string | Sort: -updatedAt\|-createdAt\|title |

### Response (200 OK)

```json
{
  "data": [
    {
      "id": "art-uuid-1",
      "type": "code",
      "language": "python",
      "title": "Fibonacci Function",
      "versionCount": 1
    }
  ],
  "pagination": {
    "total": 23,
    "hasMore": false
  }
}
```

---

## GET /api/artifacts/:id

Get a single artifact with all details.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "id": "art-uuid-1",
    "type": "code",
    "language": "python",
    "title": "Fibonacci Function",
    "code": "def fib(n):\n  if n <= 1:\n    return n\n  return fib(n-1) + fib(n-2)",
    "versionCount": 3
  }
}
```

---

## PUT /api/artifacts/:id

Update artifact code and/or title.

**Method:** PUT
**Auth:** Required

### Request Body

```json
{
  "code": "def fib(n):\n  # Updated version"
}
```

### Response (200 OK)

```json
{
  "data": {
    "id": "art-uuid-1",
    "code": "def fib(n):\n  # Updated version",
    "versionCount": 4
  }
}
```

---

## DELETE /api/artifacts/:id

Delete an artifact.

**Method:** DELETE
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "id": "art-uuid-1",
    "deleted": true,
    "mode": "soft"
  }
}
```

---

## POST /api/artifacts/:id/fork

Create a copy of an artifact.

**Method:** POST
**Auth:** Required

### Response (201 Created)

```json
{
  "data": {
    "id": "art-uuid-2",
    "type": "code",
    "title": "Fibonacci Function (Copy)",
    "forkedFrom": "art-uuid-1",
    "createdAt": 1729123456960
  }
}
```

---

## GET /api/artifacts/:id/versions

Get version history of an artifact.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "artifactId": "art-uuid-1",
    "versions": [
      {
        "version": 3,
        "code": "def fib(n):\n  if n <= 1:\n    return n\n  return fib(n-1) + fib(n-2)"
      }
    ]
  }
}
```

---

## POST /api/artifacts/batch

Create multiple artifacts in one request.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "artifacts": [
    {
      "type": "code",
      "language": "python",
      "title": "Helper Function",
      "code": "def helper():\n  pass"
    }
  ]
}
```

### Response (201 Created)

```json
{
  "data": {
    "created": 1,
    "artifacts": [
      {
        "id": "art-uuid-1",
        "type": "code",
        "title": "Helper Function"
      }
    ]
  }
}
```

---

# Phase 4: Settings & Projects API

Manage user settings and organize conversations into projects.

## GET /api/settings

Retrieve user settings with defaults applied.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "theme": "dark",
    "provider": "anthropic",
    "model": "claude-3-sonnet",
    "tts": {
      "provider": "elevenlabs",
      "voiceId": "21m00Tcm4TlvDq8ikWAM"
    }
  }
}
```

---

## PUT /api/settings

Update user settings (partial update).

**Method:** PUT
**Auth:** Required

### Request Body

```json
{
  "theme": "light",
  "model": "claude-3-opus"
}
```

### Response (200 OK)

```json
{
  "data": {
    "theme": "light",
    "provider": "anthropic",
    "model": "claude-3-opus"
  }
}
```

---

## POST /api/settings/reset

Reset all settings to defaults.

**Method:** POST
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "message": "Settings reset to defaults"
  }
}
```

---

## PUT /api/settings/apikeys/:provider

Update API key for a specific provider.

**Method:** PUT
**Auth:** Required

### Request Body

```json
{
  "apiKey": "sk-ant-..."
}
```

### Response (200 OK)

```json
{
  "data": {
    "provider": "anthropic",
    "updated": true
  }
}
```

---

## GET /api/projects

List user's projects with inline statistics.

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| limit | number | Results per page (default: 50) |
| sort | string | Sort: -updatedAt\|-createdAt\|name |

### Response (200 OK)

```json
{
  "data": [
    {
      "id": "proj-uuid-1",
      "name": "Python Learning",
      "icon": "🐍",
      "conversationCount": 5,
      "memoryCount": 23,
      "artifactCount": 3
    }
  ],
  "pagination": {
    "total": 3,
    "hasMore": false
  }
}
```

---

## POST /api/projects

Create a new project.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "name": "Web Development",
  "description": "Learning web technologies",
  "icon": "🌐"
}
```

### Response (201 Created)

```json
{
  "data": {
    "id": "proj-uuid-2",
    "name": "Web Development",
    "conversationCount": 0
  }
}
```

---

## GET /api/projects/:id

Get a single project with statistics.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "id": "proj-uuid-1",
    "name": "Python Learning",
    "icon": "🐍",
    "conversationCount": 5,
    "memoryCount": 23,
    "artifactCount": 3
  }
}
```

---

## PUT /api/projects/:id

Update project metadata.

**Method:** PUT
**Auth:** Required

### Request Body

```json
{
  "name": "Advanced Python",
  "icon": "🐍🚀"
}
```

### Response (200 OK)

```json
{
  "data": {
    "id": "proj-uuid-1",
    "name": "Advanced Python",
    "updatedAt": 1729123457200
  }
}
```

---

## DELETE /api/projects/:id

Delete a project (soft delete by default).

**Method:** DELETE
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "id": "proj-uuid-1",
    "deleted": true,
    "mode": "soft"
  }
}
```

---

## GET /api/projects/:id/analytics

Get comprehensive analytics for a project.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "projectId": "proj-uuid-1",
    "statistics": {
      "conversationCount": 5,
      "memoryCount": 23,
      "artifactCount": 3
    },
    "topTags": [
      { "tag": "python", "count": 8 },
      { "tag": "loops", "count": 5 }
    ]
  }
}
```

---

# Phase 5: Audio & Tool Execution API

Generate audio from text and execute tools with permissions and rate limiting.

## POST /api/audio/generate

Generate audio from text using ElevenLabs TTS.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "text": "Hello, this is a test of text to speech.",
  "voiceId": "21m00Tcm4TlvDq8ikWAM",
  "model": "eleven_turbo_v2_5",
  "conversationId": "conv-uuid-1",
  "messageId": "msg-uuid-1"
}
```

### Response (201 Created)

```json
{
  "data": {
    "success": true,
    "audioUrls": [
      "https://storage.googleapis.com/..."
    ],
    "chunkCount": 1
  }
}
```

---

## POST /api/audio/upload

Upload audio file to Firebase Storage.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "audioData": "data:audio/mpeg;base64,//NExAAV...",
  "conversationId": "conv-uuid-1",
  "messageId": "msg-uuid-1"
}
```

### Response (201 Created)

```json
{
  "data": {
    "success": true,
    "url": "https://storage.googleapis.com/..."
  }
}
```

---

## GET /api/audio/:conversationId/:messageId

Get signed download URL for audio chunk.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "url": "https://storage.googleapis.com/...",
    "expiresAt": 1729209856789
  }
}
```

---

## GET /api/audio/:conversationId/:messageId/all

Get all audio chunk URLs for a message.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "conversationId": "conv-uuid-1",
    "messageId": "msg-uuid-1",
    "chunkCount": 3,
    "audioUrls": [
      "https://storage.googleapis.com/...chunk_0.mp3"
    ]
  }
}
```

---

## GET /api/tools

List available tools for the user's role.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "tools": [
      {
        "name": "text_search",
        "description": "Search for text patterns",
        "rateLimit": {
          "daily": 100,
          "remaining": 87
        }
      }
    ]
  }
}
```

---

## POST /api/tools/execute

Execute tools with automatic LLM response parsing.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "toolCalls": [
    {
      "tool": "text_search",
      "parameters": {
        "query": "Python recursion"
      }
    }
  ]
}
```

### Response (200 OK)

```json
{
  "data": {
    "results": [
      {
        "tool": "text_search",
        "success": true,
        "result": {
          "matches": [
            "Recursion is when a function calls itself"
          ]
        }
      }
    ]
  }
}
```

---

## GET /api/tools/usage

Get tool usage statistics for today.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "date": "2025-10-28",
    "usage": [
      {
        "tool": "text_search",
        "used": 13,
        "limit": 100,
        "remaining": 87
      }
    ]
  }
}
```

---

# Phase 6: Batch Operations & Import/Export

High-volume operations and data portability.

## POST /api/batch

Execute multiple operations in a single batch request.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "operations": [
    {
      "id": "op-1",
      "action": "create",
      "resource": "memory",
      "data": {
        "type": "fact",
        "content": "Python lists are mutable",
        "confidence": 0.9,
        "tags": ["python"]
      }
    }
  ],
  "mode": "sequential"
}
```

### Response (200 OK)

```json
{
  "data": {
    "batchId": "batch-uuid-1",
    "status": "completed",
    "results": [
      {
        "id": "op-1",
        "status": "success",
        "resourceId": "mem-uuid-2"
      }
    ],
    "summary": {
      "total": 1,
      "succeeded": 1,
      "failed": 0
    }
  }
}
```

---

## GET /api/memories/export

Export memories in specified format with filters.

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| format | string | json\|csv\|markdown (required) |
| projectId | string | Filter by project |
| tags | string | Comma-separated tags |

### Response (200 OK - File Download)

Returns memories in requested format with proper Content-Disposition header.

---

## POST /api/memories/import

Import memories from JSON/CSV/Array with merge strategy.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "data": "[{\"type\":\"fact\",\"content\":\"Imported memory\",\"confidence\":0.8}]",
  "mergeStrategy": "skip"
}
```

### Response (200 OK)

```json
{
  "data": {
    "report": {
      "totalProcessed": 1,
      "created": 1,
      "skipped": 0,
      "failed": 0
    }
  }
}
```

---

## GET /api/conversations/export

Export conversations with message history.

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| format | string | json\|markdown (required) |
| projectId | string | Filter by project |

### Response (200 OK - File Download)

Returns conversations with full message history in requested format.

---

## POST /api/conversations/import

Import conversations with full message history.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "data": "[{\"title\":\"Imported Conversation\",\"projectId\":\"proj-1\",\"messages\":[]}]",
  "mergeStrategy": "skip"
}
```

### Response (200 OK)

```json
{
  "data": {
    "report": {
      "totalProcessed": 1,
      "created": 1,
      "skipped": 0
    }
  }
}
```

---

# Phase 7: Advanced Features & Analytics

Memory evolution chains, relationship tracking, and comprehensive analytics.

## GET /api/memories/:id/chain

Get full memory evolution chain with all relationships.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "memoryId": "mem-uuid-1",
    "chain": [
      {
        "id": "mem-uuid-1",
        "content": "Python uses indentation",
        "confidence": 0.85,
        "tags": ["python"],
        "type": "fact"
      }
    ],
    "totalItems": 1,
    "confidence": {
      "min": 0.85,
      "max": 0.85,
      "average": 0.85
    }
  }
}
```

---

## POST /api/memories/:id/relate

Create a relationship between two memories.

**Method:** POST
**Auth:** Required

### Request Body

```json
{
  "targetMemoryId": "mem-uuid-2",
  "type": "supersedes",
  "reason": "More specific and accurate",
  "confidence": 0.9
}
```

### Response (201 Created)

```json
{
  "data": {
    "id": "mem-uuid-1_supersedes_mem-uuid-2",
    "sourceMemoryId": "mem-uuid-1",
    "targetMemoryId": "mem-uuid-2",
    "type": "supersedes",
    "confidence": 0.9
  }
}
```

---

## GET /api/analytics/knowledge-map

Get knowledge graph for visualization (D3.js, Cytoscape, etc).

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "nodes": [
      {
        "id": "mem-uuid-1",
        "label": "Python uses indentation...",
        "type": "memory",
        "value": 0.85,
        "group": "fact"
      }
    ],
    "edges": [
      {
        "source": "mem-uuid-1",
        "target": "tag:python",
        "type": "tags",
        "weight": 1
      }
    ],
    "distributions": {
      "confidence": {
        "high": 3,
        "medium": 1,
        "low": 1
      }
    }
  }
}
```

---

## GET /api/analytics/timeline

Get learning timeline with events and progression.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "events": [
      {
        "timestamp": 1729123456789,
        "type": "memory_created",
        "memoryId": "mem-uuid-1",
        "memoryContent": "Python uses indentation"
      }
    ],
    "summary": {
      "totalMemoriesCreated": 5,
      "totalUpdates": 2,
      "averageConfidenceProgression": 0.78,
      "timelineSpanDays": 3
    }
  }
}
```

---

## GET /api/analytics/insights

Get AI-generated insights about learning patterns.

**Method:** GET
**Auth:** Required

### Response (200 OK)

```json
{
  "data": {
    "insights": [
      {
        "title": "Learning Velocity",
        "description": "You've been learning at 1.67 memories per day",
        "metric": 1.67,
        "type": "trend",
        "confidence": 0.95
      }
    ],
    "predictions": {
      "nextLearningAreas": ["advanced-python", "databases"],
      "completenessScore": 0.62
    }
  }
}
```

---

## GET /api/analytics/summary

Get comprehensive analytics in one request.

**Method:** GET
**Auth:** Required

### Response (200 OK)

Returns combined insights, timeline, and knowledge map data.

```json
{
  "data": {
    "insights": [...],
    "timeline": {...},
    "knowledgeMap": {...},
    "predictions": {...}
  }
}
```

---

## GET /api/memories/:id/supersession

Get linear memory version history (supersedes chain).

**Method:** GET
**Auth:** Required

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| direction | string | forward\|backward\|both (default: both) |

### Response (200 OK)

```json
{
  "data": {
    "memoryId": "mem-uuid-1",
    "direction": "both",
    "chain": [
      {
        "id": "mem-uuid-original",
        "content": "Python has indentation",
        "confidence": 0.6
      }
    ],
    "totalItems": 1
  }
}
```

---

# Rate Limiting

## Tool Rate Limits

Tools have daily quotas that reset at UTC midnight:

| Tool | Daily Limit |
|------|-------------|
| text_search | 100 |
| code_execution | 50 |
| web_request | 100 |

Check remaining quota via `GET /api/tools/usage`.

---

# CORS Configuration

The API is configured to accept requests from:

- `http://localhost:3000` - Local development (React)
- `http://localhost:5173` - Local development (Vite)
- `https://axon.neurx.org` - Production domain
- `https://axon-neurx-chat.web.app` - Firebase hosting
- `https://axon-neurx-chat.firebaseapp.com` - Firebase alternate

---

# Status

**API Version:** 1.0.0
**Status:** Production Ready ✅
**Total Endpoints:** 49

**Phases Implemented:**
- ✅ Phase 1: Core Memory API (4 endpoints)
- ✅ Phase 2: Conversation Management API (7 endpoints)
- ✅ Phase 3: Artifact Management API (8 endpoints)
- ✅ Phase 4: Settings & Projects API (10 endpoints)
- ✅ Phase 5: Audio & Tool Execution API (7 endpoints)
- ✅ Phase 6: Batch Operations & Import/Export (5 endpoints)
- ✅ Phase 7: Advanced Features & Analytics (8 endpoints)

**Last Updated:** October 28, 2025
