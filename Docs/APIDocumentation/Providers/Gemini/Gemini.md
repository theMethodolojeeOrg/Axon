# Complete Guide to Interacting with Google Gemini API Using curl

## Introduction

Google's Gemini API provides a powerful, flexible interface for building applications with state-of-the-art generative AI capabilities. The Gemini API can be accessed directly via REST endpoints using curl, making it ideal for testing, scripting, and quick prototyping without requiring installation of language-specific SDKs. This guide covers authentication, available endpoints, practical examples, and best practices for interacting with Gemini using curl commands.

## Getting Started

### Creating an API Key

To use the Gemini API, you need a free API key from Google AI Studio. Follow these steps:

1. Visit [Google AI Studio](https://aistudio.google.com/app/apikey)
2. Click "Create API Key"
3. Select or create a Google Cloud project
4. Copy your API key

### Setting Up Environment Variables

Store your API key as an environment variable to avoid exposing it in command history:

```bash
export GEMINI_API_KEY="your_api_key_here"
```

Verify it's set correctly:

```bash
echo $GEMINI_API_KEY
```

## Authentication

### Basic Header Format

All Gemini API requests require two essential headers:

```bash
-H "x-goog-api-key: $GEMINI_API_KEY"
-H "Content-Type: application/json"
```

The API uses header-based authentication with your API key, unlike some services that include the key in the request body.

### API Endpoints

The Gemini API base URL is:

```
https://generativelanguage.googleapis.com/v1beta/
```

Available models include:
- `gemini-2.5-flash` - Fast, optimized model for most tasks
- `gemini-2.5-pro` - More capable model for complex reasoning
- `gemini-2.0-flash` - Previous generation flash model
- `gemini-2.0-flash-lite` - Lightweight variant
- Specialized models for embeddings and other tasks

## Text Generation

### Basic Text Prompt

Generate text from a simple text input:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "Explain how AI works in a single paragraph."
          }
        ]
      }
    ]
  }'
```

### Controlling Output with Generation Config

Adjust response behavior using `generationConfig`:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "Write a short story about a robot"
          }
        ]
      }
    ],
    "generationConfig": {
      "temperature": 0.7,
      "topP": 0.95,
      "topK": 40,
      "maxOutputTokens": 500,
      "stopSequences": ["END"]
    }
  }'
```

**Key parameters:**
- `temperature`: Controls randomness (0-2). Lower = more deterministic, higher = more creative
- `topP`: Nucleus sampling threshold (0-1)
- `topK`: Only sample from top K most likely tokens
- `maxOutputTokens`: Maximum length of generated response
- `stopSequences`: Stops generation when these strings are encountered

### Disabling Thinking Mode

Gemini 2.5 models have extended thinking enabled by default. Disable it for faster responses:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "What is 2+2?"
          }
        ]
      }
    ],
    "generationConfig": {
      "thinkingConfig": {
        "thinkingBudget": 0
      }
    }
  }'
```

## System Instructions

Guide model behavior using system instructions:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "system_instruction": {
      "parts": [
        {
          "text": "You are a helpful assistant that specializes in technical writing. Always provide clear, concise explanations."
        }
      ]
    },
    "contents": [
      {
        "parts": [
          {
            "text": "Explain API authentication"
          }
        ]
      }
    ]
  }'
```

System instructions act as a persistent context for the model, affecting all responses in the conversation.

## Streaming Responses

### Using Server-Sent Events (SSE)

For real-time response streaming, use the `streamGenerateContent` endpoint with the `--no-buffer` flag:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  --no-buffer \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "Write a poem about the ocean"
          }
        ]
      }
    ]
  }'
```

The response arrives as Server-Sent Events with multiple `GenerateContentResponse` objects, each containing a chunk of text.

### Processing Streamed Output with jq

Parse streamed JSON responses:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent?alt=sse" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  --no-buffer \
  -X POST \
  -d '{"contents":[{"parts":[{"text":"Hello"}]}]}' | \
  grep -o '"text":"[^"]*"' | sed 's/"text":"//' | sed 's/"$//'
```

## Multi-turn Conversations

### Building Chat History

Maintain conversation context by providing multiple `Content` objects with alternating roles:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "role": "user",
        "parts": [
          {
            "text": "I have 2 dogs in my house."
          }
        ]
      },
      {
        "role": "model",
        "parts": [
          {
            "text": "That sounds lovely! Dogs are wonderful companions. What are their names?"
          }
        ]
      },
      {
        "role": "user",
        "parts": [
          {
            "text": "Their names are Max and Bella. How many paws are in my house?"
          }
        ]
      }
    ]
  }'
```

The model uses the entire conversation history as context for generating responses.

## Multimodal Input

### Sending Images

Include base64-encoded images in your request using `inline_data`:

```bash
# First, encode your image
BASE64_IMAGE=$(base64 /path/to/image.jpg | tr -d '\n')

curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "What is in this image?"
          },
          {
            "inline_data": {
              "mime_type": "image/jpeg",
              "data": "'$BASE64_IMAGE'"
            }
          }
        ]
      }
    ]
  }'
```

### Uploading Files for Reuse

For larger files or multiple requests, upload via the File API:

```bash
# Upload a file
curl "https://generativelanguage.googleapis.com/v1beta/files?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -F "file=@/path/to/document.pdf"
```

This returns a `file_uri` you can reference in multiple requests.

## Embeddings

### Generating Text Embeddings

Convert text to numerical vectors for semantic search:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-exp-03-07:embedContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "model": "models/gemini-embedding-exp-03-07",
    "content": {
      "parts": [
        {
          "text": "What is machine learning?"
        }
      ]
    }
  }'
```

The response includes an `embedding` array containing the numerical vector representation.

## Safety Settings

### Adjusting Content Filters

Fine-tune safety behavior for your use case:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "safetySettings": [
      {
        "category": "HARM_CATEGORY_HARASSMENT",
        "threshold": "BLOCK_ONLY_HIGH"
      },
      {
        "category": "HARM_CATEGORY_HATE_SPEECH",
        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
      },
      {
        "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
        "threshold": "BLOCK_LOW_AND_ABOVE"
      },
      {
        "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
      }
    ],
    "contents": [
      {
        "parts": [
          {
            "text": "Your prompt here"
          }
        ]
      }
    ]
  }'
```

**Threshold Options:**
- `HARM_BLOCK_THRESHOLD_UNSPECIFIED` - Use default threshold
- `BLOCK_NONE` - Allow all content
- `BLOCK_ONLY_HIGH` - Block only high probability harm
- `BLOCK_MEDIUM_AND_ABOVE` - Block medium and high probability
- `BLOCK_LOW_AND_ABOVE` - Block low, medium, and high probability

**Safety Categories:**
- `HARM_CATEGORY_HARASSMENT` - Negative comments targeting identity
- `HARM_CATEGORY_HATE_SPEECH` - Rude, disrespectful, or profane content
- `HARM_CATEGORY_SEXUALLY_EXPLICIT` - Sexual or lewd content
- `HARM_CATEGORY_DANGEROUS_CONTENT` - Content promoting harmful acts
- `HARM_CATEGORY_CIVIC_INTEGRITY` - Election-related content

## Structured Output

### JSON Response Format

Request structured output in JSON:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "Extract the name and age from this text: John is 30 years old"
          }
        ]
      }
    ],
    "generationConfig": {
      "responseMimeType": "application/json",
      "responseSchema": {
        "type": "object",
        "properties": {
          "name": {
            "type": "string"
          },
          "age": {
            "type": "integer"
          }
        },
        "required": ["name", "age"]
      }
    }
  }'
```

## Batch Processing

### Submitting Batch Requests

For cost-effective processing of large datasets, use batch mode (50% cheaper):

```bash
# Create batch_requests.jsonl with requests
cat > batch_requests.jsonl << 'EOF'
{"generate_content_request": {"contents": [{"parts": [{"text": "What is AI?"}]}]}}
{"generate_content_request": {"contents": [{"parts": [{"text": "Explain machine learning"}]}]}}
EOF

# Upload batch file
BATCH_FILE=$(curl "https://generativelanguage.googleapis.com/v1beta/files?key=$GEMINI_API_KEY" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -X POST \
  -F "file=@batch_requests.jsonl" | jq -r '.file.name')

# Submit batch job
curl "https://generativelanguage.googleapis.com/v1beta/batchGenerateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "requests": [
      {
        "model": "models/gemini-2.5-flash",
        "contents": [{"parts": [{"text": "What is AI?"}]}]
      }
    ]
  }'
```

## Function Calling

### Defining Tools for the Model

Enable the model to call external functions:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "What is the weather in London?"
          }
        ]
      }
    ],
    "tools": [
      {
        "function_declarations": [
          {
            "name": "get_weather",
            "description": "Get weather information for a location",
            "parameters": {
              "type": "object",
              "properties": {
                "location": {
                  "type": "string",
                  "description": "City and country"
                },
                "unit": {
                  "type": "string",
                  "enum": ["celsius", "fahrenheit"],
                  "description": "Temperature unit"
                }
              },
              "required": ["location", "unit"]
            }
          }
        ]
      }
    ]
  }'
```

The model will return a `functionCall` object when it needs to invoke a tool. You must then call the function and send the result back to the model.

## Listing Available Models

### Getting Model Information

View all available models:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY" \
  -H "x-goog-api-key: $GEMINI_API_KEY"
```

Get details about a specific model:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash?key=$GEMINI_API_KEY" \
  -H "x-goog-api-key: $GEMINI_API_KEY"
```

## Token Counting

### Estimate Token Usage

Count tokens before sending expensive requests:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:countTokens?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [
      {
        "parts": [
          {
            "text": "Write a comprehensive guide to machine learning"
          }
        ]
      }
    ]
  }' | jq '.totalTokens'
```

## Practical Tips and Best Practices

### Storing Requests in Files

For complex requests, store JSON in files:

```bash
cat > request.json << 'EOF'
{
  "contents": [
    {
      "parts": [
        {
          "text": "Explain quantum computing"
        }
      ]
    }
  ],
  "generationConfig": {
    "temperature": 0.7,
    "maxOutputTokens": 1000
  }
}
EOF

curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d @request.json
```

### Formatting Output with jq

Pretty-print JSON responses:

```bash
curl "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{"contents":[{"parts":[{"text":"Hello"}]}]}' | jq '.'
```

Extract just the text response:

```bash
curl "..." | jq -r '.candidates[0].content.parts[0].text'
```

### Debugging with Verbose Output

View complete request and response headers:

```bash
curl -v "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{...}'
```

### Error Handling

Common HTTP status codes and meanings:

| Status | Meaning | Solution |
|--------|---------|----------|
| 200 | Success | Response is valid |
| 400 | Bad Request | Check JSON syntax and required fields |
| 401 | Unauthorized | Verify API key is correct |
| 429 | Rate Limited | Wait or upgrade your API tier |
| 500 | Server Error | Retry request later |

### Performance Optimization

1. **Use appropriate models:** Choose `gemini-2.5-flash` for fast responses, `gemini-2.5-pro` for complex reasoning
2. **Set reasonable maxOutputTokens:** Limit response length to reduce latency and cost
3. **Enable caching for repeated inputs:** Use `cachedContent` for large documents processed multiple times
4. **Batch similar requests:** Use batch mode for 50% cost savings on non-urgent processing
5. **Disable extended thinking when not needed:** Faster responses with `"thinkingBudget": 0`

## Using the Google Gen AI SDK

### Installation

The Gen AI SDK provides language-specific bindings for structured API interaction:

```bash
# Python
pip install -U google-genai

# JavaScript/Node.js
npm install @google/genai

# Go
go get google.golang.org/genai

# Java
# Add to Maven pom.xml dependencies
```

### Python Example with Gen SDK

```python
from google import genai

# Initialize client (reads GEMINI_API_KEY from environment)
client = genai.Client()

# Simple text generation
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents="Explain how AI works"
)
print(response.text)

# With configuration
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents="Write a story",
    config=genai.types.GenerateContentConfig(
        temperature=0.8,
        max_output_tokens=500
    )
)

# Streaming responses
for chunk in client.models.generate_content_stream(
    model="gemini-2.5-flash",
    contents="Tell me a joke"
):
    print(chunk.text, end="")
```

### JavaScript Example with Gen SDK

```javascript
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

// Simple text generation
const response = await ai.models.generateContent({
    model: "gemini-2.5-flash",
    contents: "Explain how AI works"
});
console.log(response.text);

// With streaming
const stream = await ai.models.generateContentStream({
    model: "gemini-2.5-flash",
    contents: "Write a poem"
});

for await (const chunk of stream) {
    process.stdout.write(chunk.text);
}
```

## Rate Limits and Quotas

Gemini API has the following rate limits:

- **Requests per minute:** Varies by model and tier
- **Tokens per minute:** Varies by subscription
- **Batch requests:** Subject to queue limits

Monitor your usage via [Google AI Studio Dashboard](https://aistudio.google.com/app/usageoverview).

## Security Best Practices

1. **Never commit API keys:** Always use environment variables
2. **Use project-level API keys when possible:** More restrictive than user-level
3. **Rotate keys regularly:** Implement key rotation policies
4. **Monitor API usage:** Check for unusual patterns
5. **Use HTTPS only:** Always use secure connections
6. **Validate user inputs:** Sanitize prompts before sending to API

## Conclusion

The Gemini API via curl provides a powerful, flexible interface for building AI-powered applications. By mastering these curl commands and understanding the API structure, you can quickly prototype, test, and deploy Gemini-powered features without language-specific SDK dependencies. For production applications, consider migrating to the official Gen AI SDKs for better error handling, caching, and type safety.

For more information, visit the [official Gemini API documentation](https://ai.google.dev/api).