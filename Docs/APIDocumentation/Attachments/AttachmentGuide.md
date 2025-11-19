# Multimodal Attachment Guide

This guide details how to use the new multimodal capabilities of the NeurX Axon Chat API. The API now supports sending text, images, audio, video, and files (PDFs) to supported AI providers.

## Core Concepts

The `content` field in messages, which was previously a simple `string`, now also accepts an array of `ContentPart` objects. This allows you to mix and match different types of content in a single message.

### The `ContentPart` Type

```typescript
export type ContentPart =
  | { type: 'text'; text: string }
  | { type: 'image_url'; image_url: { url: string; detail?: 'auto' | 'low' | 'high' } }
  | { type: 'image_base64'; media_type: string; data: string }
  | { type: 'audio_url'; audio_url: { url: string } }
  | { type: 'audio_base64'; media_type: string; data: string }
  | { type: 'video_url'; video_url: { url: string } }
  | { type: 'video_base64'; media_type: string; data: string }
  | { type: 'file_url'; file_url: { url: string; mime_type?: string } }; // For PDFs, etc.
```

## API Usage

You can use these structured content parts in the following API endpoints:

1.  **`POST /apiAddMessage`** (Uses `content` field)
2.  **`POST /apiAddMessageWithResponse`** (Uses `content` field)
3.  **`POST /apiOrchestrate`** (Uses `message` field)

> **Important:** For `apiOrchestrate`, the field name is `message`, but it accepts the same `string | ContentPart[]` structure.

### Example Request Body

```json
{
  "conversationId": "conv-123",
  "provider": "gemini",
  "model": "gemini-1.5-pro",
  "content": [
    {
      "type": "text",
      "text": "What is in this image and what does the document say about it?"
    },
    {
      "type": "image_url",
      "image_url": {
        "url": "https://example.com/chart.png"
      }
    },
    {
      "type": "file_url",
      "file_url": {
        "url": "https://example.com/report.pdf",
        "mime_type": "application/pdf"
      }
    }
  ]
}
```

## Supported Modalities by Provider

Not all providers support all modalities. Here is a breakdown:

| Feature | OpenAI (GPT-4o) | Anthropic (Claude 3.5) | Gemini (1.5 Pro/Flash) | Grok (Grok-2) |
| :--- | :---: | :---: | :---: | :---: |
| **Text** | ✅ | ✅ | ✅ | ✅ |
| **Image (URL)** | ✅ | ✅ | ❌ (Use File API*) | ✅ |
| **Image (Base64)** | ✅ | ✅ | ✅ | ✅ |
| **Audio** | ❌ | ❌ | ✅ | ❌ |
| **Video** | ❌ | ❌ | ✅ | ❌ |
| **PDF (File)** | ❌ | ❌ (Backend limitation) | ✅ | ❌ |

> **Note:** The backend attempts to handle some conversions automatically, but for best performance, adhere to the provider's native preferences.

## iOS Client Implementation Guide

For the iOS client, follow these specific guidelines to ensure attachments are processed correctly by all providers.

### 1. Sending Images
You can send images as either public URLs or Base64 encoded strings.

**Option A: Public URL (Preferred for OpenAI, Anthropic, Grok)**
Use this if the image is hosted publicly (e.g., Firebase Storage with a public download token).

```json
{
  "type": "image_url",
  "image_url": {
    "url": "https://firebasestorage.googleapis.com/...",
    "detail": "auto" // Optional: 'low', 'high', 'auto'
  }
}
```

**Option B: Base64 (Required for local images or Gemini inline)**
Use this if the image is only on the device or if you want to avoid public URLs.

```json
{
  "type": "image_base64",
  "media_type": "image/jpeg", // or "image/png", "image/webp"
  "data": "<base64_string_without_prefix>"
}
```

### 2. Sending PDFs (Documents)
**For Gemini:** Use `file_url` and **MUST** provide `mime_type`.

```json
{
  "type": "file_url",
  "file_url": {
    "url": "https://example.com/document.pdf",
    "mime_type": "application/pdf"
  }
}
```

**For Anthropic:** Currently, PDFs must be sent as Base64 images (convert pages to images) or text extraction, as the `file_url` support for PDFs is limited to specific provider implementations. *Note: The backend does not currently auto-convert PDFs to Base64 for Anthropic.*

### 3. Sending Audio/Video (Gemini Only)
Gemini supports audio and video via Base64 or File URL.

```json
{
  "type": "audio_base64",
  "media_type": "audio/mp3",
  "data": "<base64_string>"
}
```

## Examples

### 1. Text + Image (Vision)

Supported by: OpenAI, Anthropic, Gemini, Grok.

```javascript
const content = [
  { type: 'text', text: "Describe this UI design." },
  { 
    type: 'image_base64', 
    media_type: 'image/png', 
    data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" 
  }
];
```

### 2. Text + Audio

Supported by: Gemini.

```javascript
const content = [
  { type: 'text', text: "Summarize this meeting recording." },
  { 
    type: 'audio_base64', 
    media_type: 'audio/mp3', 
    data: "<base64_encoded_audio_data>" 
  }
];
```

### 3. Text + PDF Document

Supported by: Gemini (via URL).

```javascript
// Gemini Example
const content = [
  { type: 'text', text: "Analyze this contract." },
  { 
    type: 'file_url', 
    file_url: { 
      url: "https://storage.googleapis.com/...",
      mime_type: "application/pdf"
    } 
  }
];
```

## Best Practices

1.  **Base64 vs. URLs**:
    *   **OpenAI, Anthropic, Grok**: Prefer `image_url` for images.
    *   **Gemini**: Supports `inlineData` (Base64) for small files and `fileData` (URI) for larger files.
2.  **Mime Types**: Always provide the correct `media_type` (e.g., `image/jpeg`, `audio/mp3`, `application/pdf`) when using base64. **Crucial:** Provide `mime_type` in `file_url` for Gemini.
3.  **Message History**: The backend stores these structured messages in Firestore. When retrieving history (`apiGetMessages`), the `content` field will be this array structure, so the frontend must be able to render it.

## Frontend Rendering Logic

When displaying messages, check if `content` is a string or an array:

```javascript
function renderMessage(message) {
  if (typeof message.content === 'string') {
    return <p>{message.content}</p>;
  }

  return (
    <div className="message-stack">
      {message.content.map((part, index) => {
        switch (part.type) {
          case 'text':
            return <p key={index}>{part.text}</p>;
          case 'image_url':
            return <img key={index} src={part.image_url.url} alt="attachment" />;
          case 'image_base64':
            return <img key={index} src={`data:${part.media_type};base64,${part.data}`} alt="attachment" />;
          // ... handle other types
          default:
            return null;
        }
      })}
    </div>
  );
}

# Project Status Update: Attachment Guide & iOS Implementation Details
**Date:** November 19, 2025

## 1. Documentation Update
- **Objective:** Update `docs/AttachmentGuide.md` to provide specific implementation details for the iOS client regarding multimodal attachments.
- **Status:** ✅ Complete
- **Details:**
  - Updated `ContentPart` type definition to include `mime_type` for `file_url`.
  - Added a dedicated "iOS Client Implementation Guide" section.
  - Clarified image sending options (Public URL vs Base64).
  - Specified requirements for PDF sending (MIME type for Gemini, limitations for Anthropic).
  - Updated "Supported Modalities" table to reflect current backend capabilities (Anthropic Image URL support).

## 2. Backend Changes (Previous Step)
- **Objective:** Ensure backend providers conform to the attachment format.
- **Status:** ✅ Complete
- **Details:**
  - `functions/src/providers/types.ts`: Added `mime_type` to `file_url`.
  - `functions/src/api/conversationAPI.ts`: Updated sanitization.
  - `functions/src/providers/anthropicProvider.ts`: Added `image_url` support.
  - `functions/src/providers/geminiProvider.ts`: Added dynamic `mime_type` support.

## 3. Next Steps
- iOS Client Developer to implement the changes according to the new guide.
- Verify integration with actual iOS client requests.

