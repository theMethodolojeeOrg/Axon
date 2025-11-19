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
  | { type: 'file_url'; file_url: { url: string } }; // For PDFs, etc.
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
        "url": "https://example.com/report.pdf"
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
| **Image (URL)** | ✅ | ❌ (Converted to Base64*) | ❌ (Use File API*) | ✅ |
| **Image (Base64)** | ✅ | ✅ | ✅ | ✅ |
| **Audio** | ❌ | ❌ | ✅ | ❌ |
| **Video** | ❌ | ❌ | ✅ | ❌ |
| **PDF (File)** | ❌ | ✅ (Base64 only) | ✅ | ❌ |

> **Note:** The backend attempts to handle some conversions automatically, but for best performance, adhere to the provider's native preferences.

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

Supported by: Gemini (via URL), Anthropic (via Base64 - *client must convert*).

```javascript
// Gemini Example
const content = [
  { type: 'text', text: "Analyze this contract." },
  { 
    type: 'file_url', 
    file_url: { url: "https://storage.googleapis.com/..." } 
  }
];
```

## Best Practices

1.  **Base64 vs. URLs**:
    *   **OpenAI & Grok**: Prefer `image_url`.
    *   **Anthropic**: Requires `image_base64`. The backend does **not** currently download URLs for Anthropic; the client must provide base64.
    *   **Gemini**: Supports `inlineData` (Base64) for small files and `fileData` (URI) for larger files.
2.  **Image Detail**: For OpenAI, you can specify `detail: 'low' | 'high' | 'auto'` in `image_url` to control token usage.
3.  **Mime Types**: Always provide the correct `media_type` (e.g., `image/jpeg`, `audio/mp3`, `application/pdf`) when using base64.
4.  **Message History**: The backend stores these structured messages in Firestore. When retrieving history (`apiGetMessages`), the `content` field will be this array structure, so the frontend must be able to render it.

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
```
