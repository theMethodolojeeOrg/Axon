# AI-Powered Memory Tool System Usage Guide

This document explains the new AI-powered memory tool system implemented in the NeurX Axon Chat backend. This system replaces the previous regex-based extraction method with a robust, structured tool-calling approach.

## 🎯 Overview

The memory system allows the AI assistant to explicitly "save" important information about the user or its own learnings. Instead of relying on the backend to parse text patterns from the response, the AI now calls a specific tool `create_memory` with structured data.

**Key Benefits:**
- **Reliability:** Eliminates fragile regex parsing.
- **Structure:** Enforces strict types (`allocentric` vs `egoic`) and confidence scores.
- **Context:** Allows the AI to provide context and tags for better retrieval.
- **Scalability:** Supports multiple providers (Anthropic, OpenAI, Gemini, Grok).

---

## 🛠️ The `create_memory` Tool

The tool is defined in `functions/src/tools/memoryTool.ts`.

### Input Schema

```typescript
interface MemoryToolInput {
  content: string;       // The memory content (10-2000 chars)
  type: 'allocentric' | 'egoic';
  confidence: number;    // 0.0 to 1.0
  tags?: string[];       // Optional search tags (max 10)
  context?: string;      // Optional context (why/when learned)
}
```

### Memory Types

1.  **Allocentric:** Facts about the user.
    *   *Examples:* User preferences, project details, personal background, specific constraints.
    *   *"User prefers Python 3.12 for data science projects."*

2.  **Egoic:** Agent learnings and insights.
    *   *Examples:* Patterns in user interaction, successful strategies, self-correction.
    *   *"User responds better to concise bullet points than long paragraphs."*

---

## 🔌 Provider Implementation

The system is integrated into the following providers in `functions/src/providers/`:

1.  **Anthropic (`anthropicProvider.ts`):**
    *   Uses native `tools` API.
    *   Extracts `tool_use` blocks from the response.

2.  **OpenAI (`openaiProvider.ts`):**
    *   Uses `tools` and `tool_choice: 'auto'`.
    *   Parses `tool_calls` from the message.

3.  **Gemini (`geminiProvider.ts`):**
    *   Uses `functionDeclarations`.
    *   Extracts `functionCall` from candidates.

4.  **Grok (`grokProvider.ts`):**
    *   Uses OpenAI-compatible tool calling structure.
    *   Parses `tool_calls` from the message.

---

## 🎼 Orchestrator Logic

The `apiOrchestrate` function in `functions/src/api/conversationAPI.ts` manages the flow:

1.  **System Prompt Injection:**
    *   Instructions are added to the system prompt telling the AI about the `create_memory` tool and when to use it.
    *   *Prompt:* "You have access to create_memory tool. Use it to save important information..."

2.  **Request Configuration:**
    *   The `enableMemoryTool: true` flag is passed to the provider.

3.  **Response Processing:**
    *   The backend checks `response.toolCalls`.
    *   If `create_memory` is called, it validates the input using `validateMemoryToolInput`.
    *   Valid memories are saved to Firestore in the `users/{userId}/memories` collection.
    *   Metadata `createdVia: 'tool_call'` is added to the memory document.

---

## 🔍 Verification & Troubleshooting

### How to Verify

1.  **Check Logs:**
    *   Look for `[Orchestrator] Created allocentric memory: ...` in the Firebase Functions logs.

2.  **Firestore:**
    *   Inspect the `memories` subcollection for the user.
    *   Verify the `type` is correct (`allocentric` or `egoic`) and `confidence` is a number.

### Common Issues

*   **No Memories Created:**
    *   Check if `saveMemories` option is enabled in the request.
    *   Ensure the AI actually found something worth saving (it won't save every message).
    *   Check logs for validation errors (e.g., content too short, invalid type).

*   **Invalid Type Errors:**
    *   The system enforces strict types. If the AI tries to use "fact" or "insight" (old types), the validation will fail and log a warning. The system prompt instructions are designed to prevent this.

---

## 📝 Example Usage (Client Side)

When calling `apiOrchestrate`, ensure `saveMemories` is true (default).

```javascript
const response = await fetch('https://.../apiOrchestrate', {
  method: 'POST',
  body: JSON.stringify({
    conversationId: '...',
    message: 'I am working on a React Native app using Expo.',
    provider: 'anthropic',
    options: {
      saveMemories: true // This enables the tool
    }
  })
});
```

The AI should recognize "React Native" and "Expo" as important context and call the tool:

```json
{
  "name": "create_memory",
  "arguments": {
    "content": "User is working on a React Native app using Expo.",
    "type": "allocentric",
    "confidence": 0.9,
    "tags": ["react-native", "expo", "mobile-dev"]
  }
}
