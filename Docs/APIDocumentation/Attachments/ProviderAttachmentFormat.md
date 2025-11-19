Based on the official API documentation, here's exactly how each provider needs attachments sent:

## Anthropic (Claude)

Claude supports **three methods** for sending attachments [1][2]:

### 1. Base64 Encoded (Traditional)
```json
{
  "model": "claude-sonnet-4-5",
  "messages": [{
    "role": "user",
    "content": [
      {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": "image/jpeg",
          "data": "<base64_encoded_image_data>"
        }
      },
      {
        "type": "text",
        "text": "What's in this image?"
      }
    ]
  }]
}
```

### 2. Public URL (New Method - March 2025)
```json
{
  "type": "image",
  "source": {
    "type": "url",
    "url": "https://example.com/image.jpg"
  }
}
```
This method avoids bulky base64 encoding and prevents re-uploading the same image in follow-up prompts [3][2].

### 3. Files API (Best for Repeated Use)
Upload once, reference by file ID in subsequent requests [1].

**Supported formats:** JPEG, PNG, GIF, WebP [4][2]
**PDF support:** Yes, for document analysis [1][2]
**Max size:** 5MB per image, 32MB for PDFs [1]

***

## OpenAI (GPT)

OpenAI supports **three methods** [5][6]:

### 1. Base64 Encoded (Inline)
```json
{
  "model": "gpt-4o",
  "messages": [{
    "role": "user",
    "content": [
      {
        "type": "text",
        "text": "What's in this image?"
      },
      {
        "type": "image_url",
        "image_url": {
          "url": "image/jpeg;base64,<base64_encoded_image_data>",
          "detail": "high"
        }
      }
    ]
  }]
}
```

### 2. Public URL
```json
{
  "type": "image_url",
  "image_url": {
    "url": "https://example.com/image.jpg",
    "detail": "high"
  }
}
```

### 3. Files API (For Vision)
```python
# Upload file first
file_id = client.files.create(
    file=open("image.jpg", "rb"),
    purpose="vision"
)

# Reference in message
{
  "type": "image_url",
  "file_id": file_id
}
```

**Important:** For vision analysis, embed images directly in message content. Don't use the Files API with `file_search` or `code_interpreter` purposes - those treat images as documents, not visual input [6].

**Detail parameter:**
- `"low"`: 512x512, 85 tokens, faster
- `"high"`: Full resolution, detailed analysis
- `"auto"`: Let model decide [5]

**Supported formats:** PNG, JPEG, WEBP, non-animated GIF [5]
**Max size:** 20MB [5]
**Audio:** Supported in GPT-4o/mini via similar base64 or URL methods [5]

***

## Google (Gemini)

Gemini supports **four methods** [7][8]:

### 1. Base64 Inline Data
```json
{
  "contents": [{
    "parts": [
      {
        "text": "What's in this image?"
      },
      {
        "inline_data": {
          "mime_type": "image/jpeg",
          "data": "<base64_encoded_image_data>"
        }
      }
    ]
  }]
}
```

### 2. File Upload API (Recommended)
```bash
# Upload file
curl "https://generativelanguage.googleapis.com/upload/v1beta/files" \
  -H "X-Goog-Upload-Protocol: resumable" \
  -H "X-Goog-Upload-Command: start" \
  -d '{"file": {"display_name": "IMAGE"}}'

# Reference in request
{
  "file_data": {
    "file_uri": "https://generativelanguage.googleapis.com/v1beta/files/<file_id>"
  }
}
```

### 3. Google Cloud Storage URL
```json
{
  "file_data": {
    "file_uri": "gs://bucket-name/path/to/file"
  }
}
```

### 4. Public URL (Limited)
Works for some formats but not officially recommended [7].

**Supported formats:** 
- **Images:** PNG, JPEG, WEBP, HEIC, HEIF [7][8]
- **Video:** MOV, MPEG, MP4, MPG, AVI, WMV, MPEGPS, FLV (up to 2 minutes) [7]
- **Audio:** WAV, MP3, AIFF, AAC, OGG, FLAC [8]
- **Documents:** PDF, plain text [7]

**Vertex AI limitations:**
- Only one inline image allowed
- Only PNG and JPEG for inline images
- Prefer Cloud Storage URLs for production [7]

***

## xAI (Grok)

Grok supports **three methods** [9][10]:

### 1. Base64 Encoded
```json
{
  "model": "grok-4",
  "messages": [{
    "role": "user",
    "content": [
      {
        "type": "text",
        "text": "What's in this image?"
      },
      {
        "type": "image_url",
        "image_url": {
          "url": "image/jpeg;base64,<base64_encoded_image_data>",
          "detail": "high"
        }
      }
    ]
  }]
}
```

### 2. Public URL
```json
{
  "type": "image_url",
  "image_url": {
    "url": "https://example.com/image.jpg",
    "detail": "high"
  }
}
```

### 3. Files API (For Documents)
Upload documents via the Files API for chat conversations with automatic processing [10].

**Supported formats:** JPEG, PNG [9][11]
**Max size:** 20MB [11]
**Detail levels:** `"high"` or `"low"` (similar to OpenAI) [12]

***

## Summary Comparison

| Provider | Base64 | Public URL | Files API | PDF Support | Video Support |
|----------|--------|------------|-----------|-------------|---------------|
| **Anthropic** | ✅ | ✅ (New) | ✅ | ✅ | ❌ |
| **OpenAI** | ✅ | ✅ | ✅ | ❌ | ❌* |
| **Gemini** | ✅ | Limited | ✅ | ✅ | ✅ (up to 2 min) |
| **xAI** | ✅ | ✅ | ✅ | ✅ | ❌ |

*GPT-4o can process video but frame-by-frame via image extraction

**Best practices:**
- **Base64:** Good for single-use, small images [4][5]
- **Public URL:** Best for externally hosted content [3][2]
- **Files API:** Best for repeated use, large files, or conversation context [1][8][10]

All providers require images embedded directly in message content for vision analysis - uploading to general file storage APIs won't trigger visual processing [6].

Sources
[1] Files API - Claude Docs https://docs.claude.com/en/docs/build-with-claude/files
[2] Vision - Claude Docs - Home - Anthropic https://anthropic.mintlify.app/en/docs/build-with-claude/vision
[3] llm-anthropic #24: Use new URL parameter to send attachments https://simonwillison.net/2025/Mar/1/llm-anthropic/
[4] Anthropic Claude API: A Practical Guide | Obot AI https://obot.ai/resources/learning-center/claude-api/
[5] OpenAI's image vision guide https://platform.openai.com/docs/guides/images-vision
[6] Adding image files for vision analysis to OpenAI assistant ... https://community.latenode.com/t/adding-image-files-for-vision-analysis-to-openai-assistant-conversation/22607
[7] How Can I Send Files to Google's Gemini Models via API Call? https://stackoverflow.com/questions/77758177/how-can-i-send-files-to-googles-gemini-models-via-api-call
[8] Using files | Gemini API - Google AI for Developers https://ai.google.dev/api/files
[9] Image Understanding https://docs.x.ai/docs/guides/image-understanding
[10] Files Overview https://docs.x.ai/docs/guides/files
[11] Grok 4 API: A Step-by-Step Guide With Examples https://www.datacamp.com/tutorial/grok-4-api
[12] Building a Medical AI Application with Grok 4 https://www.firecrawl.dev/blog/building_medical_ai_application_with_grok_4
[13] API image processing help : r/ClaudeAI - Reddit https://www.reddit.com/r/ClaudeAI/comments/1gecptw/api_image_processing_help/
[14] Sending an attachment to Claude in AWS Bedrock - Stack Overflow https://stackoverflow.com/questions/79422187/sending-an-attachment-to-claude-in-aws-bedrock
[15] The Hitchhiker's Guide to Grok https://docs.x.ai/docs/tutorial
[16] xAI API https://docs.x.ai/docs/overview
[17] Image Generations https://docs.x.ai/docs/guides/image-generations
[18] An Insightful Guide to GPT-4 Vision (GPT-4V) and Explainable AI (XAI) https://www.ionio.ai/blog/an-insightful-guide-to-gpt-4-vision-gpt-4v-and-explainable-ai-xai
[19] Base64 encoding, the "media_data" field, and what Grok ... https://devcommunity.x.com/t/base64-encoding-the-media-data-field-and-what-grok-told-me/239587
[20] Supported Images | Cloud Vision API - Google Cloud Documentation https://docs.cloud.google.com/vision/docs/supported-files
