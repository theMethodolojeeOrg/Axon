# Complete Guide to Interacting with Anthropic Claude API Using curl

## Introduction

Anthropic's Claude API provides access to state-of-the-art large language models through a simple REST interface. Using curl, you can directly interact with Claude without installing any SDKs, making it ideal for quick prototyping, shell scripting, and systems where you want minimal dependencies. This guide covers authentication, available endpoints, practical examples, and best practices for using Claude via curl commands.

## Getting Started

### Creating an API Key

To use Claude's API, you need to create an API key through Anthropic's console:

1. Visit [Anthropic Console](https://console.anthropic.com)
2. Sign up or log in to your account
3. Navigate to the API keys section
4. Click "Create Key" and give it a name
5. Copy your API key immediately (it won't be shown again)

### Setting Up Environment Variables

Store your API key securely as an environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-your-api-key-here"
```

Verify it's set:

```bash
echo $ANTHROPIC_API_KEY
```

## Authentication and Headers

### Required Headers

All Claude API requests require three headers:

```bash
-H "x-api-key: $ANTHROPIC_API_KEY"
-H "anthropic-version: 2023-06-01"
-H "Content-Type: application/json"
```

The `anthropic-version` header specifies the API version. Using `2023-06-01` ensures stability and access to the latest features.

### API Base URL

The Claude API endpoint is:

```
https://api.anthropic.com/v1/
```

## Available Models

Claude offers several models with different capabilities and pricing:

| Model | Context Window | Best For | Input Cost | Output Cost |
|-------|---|---|---|---|
| claude-opus-4-1 | 200K tokens | Complex reasoning, research | $15/MTok | $75/MTok |
| claude-sonnet-4-5 | 200K tokens | Balanced performance | $3/MTok | $15/MTok |
| claude-haiku-4-5 | 200K tokens | Fast, lightweight tasks | $0.80/MTok | $4/MTok |
| claude-sonnet-3.7 | 200K tokens | General purpose (legacy) | $3/MTok | $15/MTok |
| claude-haiku-3.5 | 200K tokens | Speed-focused (legacy) | $0.80/MTok | $4/MTok |

Note: Prices are approximate and subject to change. Check the [official pricing page](https://www.anthropic.com/pricing) for current rates.

## Text Generation

### Basic Message Request

Send a simple text prompt to Claude:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "messages": [
      {"role": "user", "content": "Explain quantum computing in simple terms"}
    ]
  }'
```

The response includes the model's text in `content[0].text`.

### Controlling Response Generation

Fine-tune output with `max_tokens` and other parameters:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 500,
    "messages": [
      {"role": "user", "content": "Write a short story about AI"}
    ]
  }'
```

**Key parameters:**
- `max_tokens`: Maximum length of the response (required)
- `temperature`: Controls randomness (0-1, default 1.0). Lower = more deterministic
- `top_p`: Nucleus sampling for diversity (0-1, default 1.0)
- `top_k`: Sample from top K tokens (1-1000)

## System Prompts

Guide Claude's behavior with a system prompt:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "system": "You are a helpful coding assistant. Always provide code examples in Python unless otherwise specified.",
    "messages": [
      {"role": "user", "content": "How do I reverse a list?"}
    ]
  }'
```

System prompts provide consistent context and behavioral guidance across all turns in a conversation.

## Streaming Responses

### Using Server-Sent Events

Get real-time response streaming by adding `stream: true`:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  --no-buffer \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "stream": true,
    "messages": [
      {"role": "user", "content": "Write a poem about the sea"}
    ]
  }'
```

The response streams as Server-Sent Events. Each event contains a chunk of text in `delta.text` fields.

## Multi-turn Conversations

### Building Chat History

Maintain conversation context by including previous turns:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "messages": [
      {"role": "user", "content": "What is 2 + 2?"},
      {"role": "assistant", "content": "2 + 2 = 4"},
      {"role": "user", "content": "What is that multiplied by 3?"}
    ]
  }'
```

Claude will use all previous messages as context for understanding the current request.

## Vision and Image Analysis

### Sending Images via Base64

Include images by encoding them to base64:

```bash
# Encode image to base64
IMAGE_BASE64=$(base64 -i /path/to/image.jpg | tr -d '\n')

curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image",
            "source": {
              "type": "base64",
              "media_type": "image/jpeg",
              "data": "'$IMAGE_BASE64'"
            }
          },
          {
            "type": "text",
            "text": "What is in this image?"
          }
        ]
      }
    ]
  }'
```

### Sending Images via URL

Reference images directly from URLs without encoding:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image",
            "source": {
              "type": "url",
              "url": "https://example.com/image.jpg"
            }
          },
          {
            "type": "text",
            "text": "Analyze this image"
          }
        ]
      }
    ]
  }'
```

### Multiple Images

Combine multiple images in one request:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Image 1:"
          },
          {
            "type": "image",
            "source": {
              "type": "url",
              "url": "https://example.com/image1.jpg"
            }
          },
          {
            "type": "text",
            "text": "Image 2:"
          },
          {
            "type": "image",
            "source": {
              "type": "url",
              "url": "https://example.com/image2.jpg"
            }
          },
          {
            "type": "text",
            "text": "Compare these two images"
          }
        ]
      }
    ]
  }'
```

## Tool Use and Function Calling

### Defining Tools

Enable Claude to use external functions:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather for a location",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {
              "type": "string",
              "description": "City and state, e.g., San Francisco, CA"
            },
            "unit": {
              "type": "string",
              "enum": ["celsius", "fahrenheit"],
              "description": "Temperature unit"
            }
          },
          "required": ["location"]
        }
      }
    ],
    "messages": [
      {"role": "user", "content": "What is the weather in Paris?"}
    ]
  }'
```

Claude will return `tool_use` blocks when it determines a tool should be called.

### Handling Tool Results

Send tool results back to Claude:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "tools": [
      {
        "name": "get_weather",
        "description": "Get the current weather",
        "input_schema": {
          "type": "object",
          "properties": {
            "location": {"type": "string"}
          },
          "required": ["location"]
        }
      }
    ],
    "messages": [
      {"role": "user", "content": "What is the weather in Paris?"},
      {
        "role": "assistant",
        "content": [
          {
            "type": "tool_use",
            "id": "tool_123",
            "name": "get_weather",
            "input": {"location": "Paris"}
          }
        ]
      },
      {
        "role": "user",
        "content": [
          {
            "type": "tool_result",
            "tool_use_id": "tool_123",
            "content": "Temperature: 15Â°C, Cloudy, Wind: 10 km/h"
          }
        ]
      }
    ]
  }'
```

## Token Counting

### Count Tokens Before Sending

Estimate token usage before making expensive requests:

```bash
curl https://api.anthropic.com/v1/messages/count_tokens \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "messages": [
      {"role": "user", "content": "Explain machine learning in depth"}
    ]
  }' | jq '.input_tokens'
```

This helps predict costs and prevent unexpected bills.

## Batch Processing API

### Create a Batch Job

Process multiple requests asynchronously at 50% cost savings:

```bash
# Create batch_requests.jsonl
cat > requests.jsonl << 'EOF'
{"custom_id": "msg-1", "params": {"model": "claude-sonnet-4-5", "max_tokens": 1024, "messages": [{"role": "user", "content": "What is AI?"}]}}
{"custom_id": "msg-2", "params": {"model": "claude-sonnet-4-5", "max_tokens": 1024, "messages": [{"role": "user", "content": "Explain machine learning"}]}}
EOF

curl https://api.anthropic.com/v1/messages/batches \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "requests": [
      {
        "custom_id": "msg-1",
        "params": {
          "model": "claude-sonnet-4-5",
          "max_tokens": 1024,
          "messages": [{"role": "user", "content": "What is AI?"}]
        }
      },
      {
        "custom_id": "msg-2",
        "params": {
          "model": "claude-sonnet-4-5",
          "max_tokens": 1024,
          "messages": [{"role": "user", "content": "Explain machine learning"}]
        }
      }
    ]
  }'
```

The response includes a `id` for tracking the batch.

### Check Batch Status

Monitor batch processing:

```bash
curl https://api.anthropic.com/v1/messages/batches/msgbatch_01HkcTjaV5uDC8jWR4ZsDV8d \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01"
```

Status will be `in_progress` initially, then `ended` when complete.

### Retrieve Batch Results

Download results once processing completes:

```bash
curl https://api.anthropic.com/v1/messages/batches/msgbatch_01HkcTjaV5uDC8jWR4ZsDV8d \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  | jq '.results_url' -r | xargs curl -H "x-api-key: $ANTHROPIC_API_KEY"
```

Results are returned in JSONL format with one result per line.

## Prompt Caching

### Enable Caching for Large Contexts

Reduce costs by up to 90% when reusing large documents:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-sonnet-4-5",
    "max_tokens": 1024,
    "system": [
      {
        "type": "text",
        "text": "You are a helpful assistant"
      },
      {
        "type": "text",
        "text": "<large document content here>",
        "cache_control": {"type": "ephemeral"}
      }
    ],
    "messages": [
      {"role": "user", "content": "Summarize this document"}
    ]
  }'
```

The `cache_control` field enables caching. Subsequent requests with the same cached content will be significantly cheaper.

## Extended Thinking

### Enable Claude to Think Deeper

Use extended thinking for complex reasoning tasks:

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-opus-4-1",
    "max_tokens": 16000,
    "thinking": {
      "type": "enabled",
      "budget_tokens": 10000
    },
    "messages": [
      {"role": "user", "content": "Solve this complex math problem: ..."}
    ]
  }'
```

Extended thinking allows Claude to work through problems before responding. The response includes `thinking` content blocks.

## Practical Tips and Best Practices

### Storing Complex Requests

Save elaborate JSON requests in files:

```bash
cat > message_request.json << 'EOF'
{
  "model": "claude-sonnet-4-5",
  "max_tokens": 1024,
  "system": "You are an expert programmer",
  "messages": [
    {"role": "user", "content": "Review this code"}
  ]
}
EOF

curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d @message_request.json
```

### Parsing JSON Responses with jq

Extract specific information from responses:

```bash
# Get just the text response
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":1024,"messages":[{"role":"user","content":"Hello"}]}' \
  | jq -r '.content[0].text'

# Check token usage
curl ... | jq '.usage'

# Get stop reason
curl ... | jq '.stop_reason'
```

### Error Handling

Common HTTP responses:

| Status | Error | Meaning |
|--------|-------|---------|
| 200 | - | Success |
| 400 | invalid_request_error | Malformed JSON or missing fields |
| 401 | authentication_error | Invalid API key |
| 403 | permission_error | Insufficient permissions |
| 429 | rate_limit_error | Too many requests |
| 500 | internal_server_error | Server error (retry later) |

### Debugging

View full request and response details:

```bash
curl -v https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":100,"messages":[{"role":"user","content":"Hi"}]}'
```

The `-v` flag shows all headers and the request/response lifecycle.

### Cost Optimization

1. **Use appropriate models:** Choose `claude-haiku-4-5` for simple tasks, `claude-sonnet-4-5` for balanced work, `claude-opus-4-1` for complex reasoning
2. **Set reasonable `max_tokens`:** Smaller limits mean cheaper responses
3. **Leverage prompt caching:** Reuse large documents with cache_control
4. **Use batch API:** 50% savings for non-urgent processing
5. **Monitor token usage:** Check `usage` in responses regularly

## Response Structure

### Standard Response Format

All successful responses follow this structure:

```json
{
  "id": "msg_01...",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "The response text"
    }
  ],
  "model": "claude-sonnet-4-5",
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 123,
    "output_tokens": 456,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0
  }
}
```

Key fields:
- `id`: Unique message identifier
- `stop_reason`: Why generation stopped (`end_turn`, `max_tokens`, `stop_sequence`)
- `usage`: Token counts including cache statistics

## Rate Limits and Quotas

Claude API rate limits vary by model and tier:

- **Requests per minute:** 100-10,000 depending on tier
- **Tokens per minute:** 10K-300K+ depending on tier
- **Batch requests:** Separate rate limiting applies

Check your [usage dashboard](https://console.anthropic.com) for current limits.

## Security Best Practices

1. **Never hardcode API keys:** Always use environment variables
2. **Use workspace-level keys:** More restrictive than user keys
3. **Rotate keys regularly:** Implement key rotation policies
4. **Monitor usage:** Watch for unusual patterns
5. **Use HTTPS only:** Always send requests over secure connections
6. **Validate inputs:** Sanitize user-provided prompts before sending

## Transitioning to SDKs

While curl is excellent for testing and scripting, production systems often benefit from official SDKs:

**Python:**
```python
from anthropic import Anthropic

client = Anthropic()
response = client.messages.create(
    model="claude-sonnet-4-5",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.content[0].text)
```

**JavaScript:**
```javascript
const Anthropic = require("@anthropic-ai/sdk");
const client = new Anthropic();

const response = await client.messages.create({
  model: "claude-sonnet-4-5",
  max_tokens: 1024,
  messages: [{ role: "user", content: "Hello!" }]
});

console.log(response.content[0].text);
```

## Conclusion

Anthropic's Claude API via curl provides a powerful, accessible interface for building AI applications. With comprehensive support for text, images, tool use, and batch processing, you can prototype and deploy sophisticated AI-powered features with minimal setup. For more information, consult the [official Claude API documentation](https://docs.claude.com).