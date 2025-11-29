# Complete Guide to Interacting with OpenAI's API Using curl

## Introduction

OpenAI's API provides RESTful access to powerful AI models for text generation, image creation, embeddings, and more[1]. Using curl (Client URL) is the fastest way to test and interact with these endpoints directly from the command line without writing code[2]. This guide covers authentication, all major API endpoints, and practical examples with curl commands.

## Authentication

### API Key Setup

OpenAI uses Bearer authentication with API keys[1]. To get started, you need to obtain an API key from your OpenAI account dashboard[2].

**Set up your API key as an environment variable:**

```bash
export OPENAI_API_KEY="your_api_key_here"
```

This prevents accidentally exposing your key in command history or scripts[2].

### Basic Authentication Format

All requests require two headers[1][3]:

```bash
-H "Content-Type: application/json"
-H "Authorization: Bearer $OPENAI_API_KEY"
```

### Organization and Project Headers

If you belong to multiple organizations or projects, specify which one to use[1]:

```bash
-H "OpenAI-Organization: YOUR_ORG_ID"
-H "OpenAI-Project: $PROJECT_ID"
```

## Chat Completions

### Basic Chat Request

The most common use case is sending messages to GPT models[2]:

```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello OpenAI! How are you?"}
    ]
  }'
```

The response contains the assistant's reply in `choices.message.content`[2].

### Streaming Responses

To receive responses as they're generated using server-sent events, add the `stream` parameter and use the `-N` flag[4]:

```bash
curl -N https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello!"}
    ],
    "stream": true
  }'
```

### Controlling Output

Add parameters to control the response behavior[2]:

```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [{"role": "user", "content": "Write a story"}],
    "max_tokens": 100,
    "temperature": 0.7,
    "top_p": 1.0
  }'
```

## Responses API

### Creating a Model Response

The Responses API is OpenAI's advanced interface for stateful interactions[1]:

```bash
curl https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4.1",
    "input": "Tell me a three sentence bedtime story about a unicorn."
  }'
```

### Retrieving a Response

Get a previously created response by ID[1]:

```bash
curl https://api.openai.com/v1/responses/resp_123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Deleting a Response

Remove a stored response[1]:

```bash
curl -X DELETE https://api.openai.com/v1/responses/resp_123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

## Text Completions

### Basic Completion Request

For plain text generation without conversation structure[2]:

```bash
curl https://api.openai.com/v1/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-3.5-turbo-instruct",
    "prompt": "Write a haiku about the ocean.",
    "max_tokens": 50
  }'
```

## Image Generation (DALL-E)

### Generate Images

Create images from text prompts[5]:

```bash
curl https://api.openai.com/v1/images/generations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "prompt": "a photo of a happy corgi puppy sitting and facing forward, studio light, longshot",
    "n": 1,
    "size": "1024x1024"
  }'
```

### Edit Images

Modify existing images using prompts[5]:

```bash
curl https://api.openai.com/v1/images/edits \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F image="@/path/to/image.png" \
  -F mask="@/path/to/mask.png" \
  -F prompt="a photo of a happy corgi puppy with fancy sunglasses on" \
  -F n=1 \
  -F size="1024x1024"
```

### Create Variations

Generate variations of an existing image (DALL-E 2 only)[6][5]:

```bash
curl https://api.openai.com/v1/images/variations \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -F image="@/path/to/image.png" \
  -F n=4 \
  -F size="1024x1024"
```

## Embeddings

### Creating Embeddings

Convert text into numerical vectors for semantic search and clustering[7]:

```bash
curl -X POST \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  --data '{
    "input": "Hello, world!",
    "model": "text-embedding-3-large"
  }' \
  https://api.openai.com/v1/embeddings
```

The response contains a vector representation in the `embedding` field[7].

### Using Smaller Embeddings Model

For faster processing with slightly lower quality[2]:

```bash
curl https://api.openai.com/v1/embeddings \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "text-embedding-3-small",
    "input": "OpenAI makes powerful AI models."
  }'
```

## Assistants API

### Creating a Thread

Initialize a conversation thread[8]:

```bash
curl https://api.openai.com/v1/threads \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2" \
  -d ''
```

### Adding a Message to Thread

Send a message to the thread[8]:

```bash
curl https://api.openai.com/v1/threads/thread_abc123/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2" \
  -d '{
    "role": "user",
    "content": "How does AI work? Explain it in simple terms."
  }'
```

### Running the Thread

Execute the assistant on the thread[8]:

```bash
curl https://api.openai.com/v1/threads/thread_abc123/runs \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -H "OpenAI-Beta: assistants=v2" \
  -d '{
    "assistant_id": "asst_abc123"
  }'
```

### Retrieving Thread Results

Get the assistant's response[8]:

```bash
curl https://api.openai.com/v1/threads/thread_abc123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2"
```

## Conversations API

### Creating a Conversation

Initialize a conversation with optional metadata[1]:

```bash
curl https://api.openai.com/v1/conversations \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "metadata": {"topic": "demo"},
    "items": [
      {
        "type": "message",
        "role": "user",
        "content": "Hello!"
      }
    ]
  }'
```

### Retrieving a Conversation

Access an existing conversation by ID[1]:

```bash
curl https://api.openai.com/v1/conversations/conv_123 \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Updating Conversation Metadata

Modify conversation properties[1]:

```bash
curl https://api.openai.com/v1/conversations/conv_123 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "metadata": {"topic": "project-x"}
  }'
```

### Deleting a Conversation

Remove a conversation permanently[1]:

```bash
curl -X DELETE https://api.openai.com/v1/conversations/conv_123 \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

## Function Calling

### Defining Functions

Enable the model to call external functions[9]:

```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4",
    "messages": [
      {
        "role": "system",
        "content": "You are a helpful assistant."
      },
      {
        "role": "user",
        "content": "How is the current weather in Graz?"
      }
    ],
    "parallel_tool_calls": false,
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_current_weather",
          "description": "Get the current weather",
          "parameters": {
            "type": "object",
            "properties": {
              "location": {
                "type": "string",
                "description": "The city and country, eg. San Francisco, USA"
              },
              "format": {
                "type": "string",
                "enum": ["celsius", "fahrenheit"]
              }
            },
            "required": ["location", "format"]
          }
        }
      }
    ]
  }'
```

## Advanced Features

### Listing Available Models

View all models accessible with your API key[1]:

```bash
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $OPENAI_API_KEY"
```

### Pretty-Printing JSON Responses

Use `jq` to format JSON output for better readability[2]:

```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Hello!"}]}' | jq
```

### Debug Headers

Inspect response headers for troubleshooting[1]:

```bash
curl -i https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"Test"}]}'
```

Useful headers include `x-request-id`, `openai-processing-ms`, and rate limit information[1].

## Best Practices

### Security

Never expose API keys in public repositories or client-side code[2][3]. Always use environment variables or secure key management services[10].

### Cost Control

Set `max_tokens` limits to prevent unexpectedly large bills[2]:

```bash
-d '{"model":"gpt-4","messages":[...],"max_tokens":100}'
```

### Error Handling

Common HTTP status codes[2][10]:

- **401 Unauthorized**: Invalid or missing API key
- **429 Too Many Requests**: Rate limit exceeded
- **400 Bad Request**: Malformed JSON or missing required fields

### Rate Limits

Monitor the rate limit headers in responses to track usage[1]:

- `x-ratelimit-remaining-requests`
- `x-ratelimit-remaining-tokens`
- `x-ratelimit-reset-requests`

## Transitioning to Code

While curl is excellent for testing, production applications should use official SDKs[2]. Here's how a curl request translates to Python:

**curl:**
```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello"}]}'
```

**Python equivalent:**
```python
import openai

openai.api_key = "your_api_key_here"

response = openai.ChatCompletion.create(
    model="gpt-4",
    messages=[{"role": "user", "content": "Hello"}]
)

print(response["choices"][0]["message"]["content"])
```

## Debugging Tips

### Logging Request IDs

OpenAI recommends logging the `x-request-id` header for production debugging[1]:

```bash
curl -D - https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model":"gpt-4","messages":[...]}' | grep x-request-id
```

### Verbose Output

Use `-v` flag to see complete request and response details:

```bash
curl -v https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model":"gpt-4","messages":[...]}'
```

### Testing Without API Key Exposure

Store complex requests in files:

```bash
cat > request.json << EOF
{
  "model": "gpt-4",
  "messages": [{"role": "user", "content": "Hello"}]
}
EOF

curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d @request.json
```

Sources
[1] API Reference https://platform.openai.com/docs/api-reference/introduction
[2] cURL OpenAI API: Step-by-Step Tutorial for Beginners https://muneebdev.com/curl-openai-api-tutorial/
[3] How do I authenticate API requests with OpenAI? https://zilliz.com/ai-faq/how-do-i-authenticate-api-requests-with-openai
[4] API Assistant - Streaming curl - OpenAI Developer Community https://community.openai.com/t/api-assistant-streaming-curl/731219
[5] DALL·E API now available in public beta - OpenAI https://openai.com/index/dall-e-api-now-available-in-public-beta/
[6] Image generation - OpenAI API https://platform.openai.com/docs/guides/image-generation
[7] Access the OpenAI API with curl - Moritz's AI blog - Substack https://moritzstrube.substack.com/p/access-the-openai-api-with-curl
[8] Can Anypone provide a CURL example of assistant V2? - API https://community.openai.com/t/can-anypone-provide-a-curl-example-of-assistant-v2/721243
[9] OpenAI function calling example https://gist.github.com/philipp-meier/678a4679d0895276f270fac4c046ad14
[10] How do I authenticate API requests with OpenAI? https://milvus.io/ai-quick-reference/how-do-i-authenticate-api-requests-with-openai
[11] Text generation - OpenAI API https://platform.openai.com/docs/guides/text
[12] Is There A Quickstart Guide For Using CURL? - API https://community.openai.com/t/is-there-a-quickstart-guide-for-using-curl/1362664
[13] OpenAI Inference Protocol Using Curl - Cloudera Docs https://docs.cloudera.com/machine-learning/cloud/ai-inference/topics/ml-caii-openai-inference-protocol-using-curl.html
[14] OpenAI Realtime API Quick Start 2025: Get Started in 5 Min https://skywork.ai/blog/agent/openai-realtime-api-quick-start-2025-get-started-in-5-min/
[15] How to Use OpenAI API Without Coding - YouTube https://www.youtube.com/watch?v=0Aw8wrhCMaI
[16] OpenAI API Documentation - DALL-E Image Generation https://platform.openai.com/docs/guides/images
[17] How to use Azure OpenAI image generation models - Microsoft Learn https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/dall-e
[18] How to serve Embeddings models via OpenAI API https://docs.openvino.ai/2025/model-server/ovms_demos_embeddings.html
[19] trying to generate an image using openai api - Stack Overflow https://stackoverflow.com/questions/79574584/trying-to-generate-an-image-using-openai-api
