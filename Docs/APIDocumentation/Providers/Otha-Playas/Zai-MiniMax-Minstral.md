This document expands the API reference to include the specific **Z.ai** (Zhipu AI) and **MiniMax** models you requested, along with an updated look at **Mistral**.

***

# 4. Z.ai (Zhipu AI)

Z.ai (also known as Zhipu AI / BigModel) offers the "GLM" series. The latest generation includes **GLM-4.6** and **GLM-4.5**, with specialized "thinking" and vision variants.

### **Base URL**
```
https://api.z.ai/api/paas/v4
```

### **Authentication**
- Header: `Authorization: Bearer <YOUR_API_KEY>`

### **Supported Models & Pricing (Dec 2025)**

| Model ID | Context | Input / 1M | Output / 1M | Modalities | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `glm-4.6` | 200k | $0.60 | $2.20 | Text | **Flagship.** Best reasoning, coding, and agentic capability. |
| `glm-4.6v` | 128k | $0.30 | $0.90 | Text + Image | **Flagship Vision.** Native multimodal with "thinking" support. |
| `glm-4.6v-flash` | 128k | $0.15 | $0.45 | Text + Image | **Fast Vision.** Lower latency and cost. |
| `glm-4.5` | 128k | $0.60 | $2.20 | Text | Previous flagship. Strong generalist. |
| `glm-4.5-air` | 128k | $0.30 | $0.90 | Text | Balanced "Air" tier (speed/performance mix). |
| `glm-4.5v` | 128k | $0.60 | $1.80 | Text + Image | Multimodal variant of GLM-4.5. |

### **Special Features**
- **Thinking:** Enable "thinking" mode for complex tasks (similar to CoT).
- **Vision:** Pass `thinking: { "type": "enabled" }` even with vision inputs for enhanced reasoning on images (e.g., coordinate finding).

### **cURL Example (Vision + Thinking)**

```bash
curl --location 'https://api.z.ai/api/paas/v4/chat/completions' \
--header 'Authorization: Bearer <YOUR_API_KEY>' \
--header 'Content-Type: application/json' \
--data '{
    "model": "glm-4.6v",
    "messages": [
        {
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {
                        "url": "https://example.com/image.jpg"
                    }
                },
                {
                    "type": "text",
                    "text": "Locate the red car. Provide coordinates in [[xmin,ymin,xmax,ymax]] format."
                }
            ]
        }
    ],
    "thinking": {
        "type": "enabled"
    }
}'
```

***

# 5. MiniMax API

MiniMax provides the **M2** series, optimized for "agentic" workflows, massive context, and extremely low pricing.

### **Base URL**
```
https://api.minimax.io/v1
```

### **Authentication**
- Header: `Authorization: Bearer <YOUR_API_KEY>`

### **Supported Models & Pricing (Dec 2025)**

| Model ID | Context | Input / 1M | Output / 1M | Description |
| :--- | :--- | :--- | :--- | :--- |
| `MiniMax-M2` | 1M | $0.15 | $0.60 | **Flagship.** Agentic, long-context, 92% cheaper than Claude Sonnet. |
| `MiniMax-M2-Stable` | 1M | $0.15 | $0.60 | Stable version. Higher rate limits for paid tiers. |

> **Note:** MiniMax pricing is extremely aggressive ($0.15/$0.60), positioning M2 as a high-performance budget alternative for heavy coding/agent loops.

### **cURL Example**

```bash
curl --location 'https://api.minimax.io/v1/text/chatcompletion_v2' \
--header 'Authorization: Bearer <YOUR_API_KEY>' \
--header 'Content-Type: application/json' \
--data '{
    "model": "MiniMax-M2",
    "messages": [
        {
            "sender_type": "USER",
            "sender_name": "User",
            "text": "Analyze this 500-page logic puzzle."
        }
    ],
    "temperature": 0.1
}'
```

***

# 6. Mistral AI (Updated)

Mistral continues to refine its "Large" and specialized "Pixtral" (vision) models.

### **Base URL**
```
https://api.mistral.ai/v1
```

### **Supported Models & Pricing (Dec 2025)**

| Model ID | Context | Input / 1M | Output / 1M | Description |
| :--- | :--- | :--- | :--- | :--- |
| `mistral-large-latest` | 128k | $2.00 | $6.00 | **Flagship.** Top-tier reasoning. (Also `mistral-large-2411`). |
| `pixtral-large-2411` | 128k | $2.00 | $6.00 | **Flagship Vision.** Multimodal version of Mistral Large. |
| `pixtral-12b-2409` | 128k | $0.10 | $0.10 | **Edge Vision.** Efficient multimodal model. |
| `codestral-latest` | 32k | $0.20 | $0.60 | **Coding.** Optimized for FIM and code generation. |

### **cURL Example**

```bash
curl --location 'https://api.mistral.ai/v1/chat/completions' \
--header 'Authorization: Bearer <YOUR_API_KEY>' \
--header 'Content-Type: application/json' \
--data '{
    "model": "pixtral-large-2411",
    "messages": [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "What is in this picture?"},
                {"type": "image_url", "image_url": {"url": "https://example.com/image.jpg"}}
            ]
        }
    ]
}'
```

***

# Updated System Prompt Section

Append this to your agent's system instructions to strictly follow the specific models and endpoints you requested:

```markdown
## NEW PROVIDER: Z.AI (Zhipu AI)
- Base URL: https://api.z.ai/api/paas/v4
- Models:
  - `glm-4.6` (Flagship text)
  - `glm-4.6v` (Flagship vision + thinking)
  - `glm-4.6v-flash` (Fast vision)
  - `glm-4.5` (Standard text)
  - `glm-4.5-air` (Efficient text)
  - `glm-4.5v` (Standard vision)
- Special Param: Support `thinking: {"type": "enabled"}` in the request body.

## NEW PROVIDER: MINIMAX
- Base URL: https://api.minimax.io/v1
- Models:
  - `MiniMax-M2` (Flagship, 1M context, ultra-low cost)
  - `MiniMax-M2-Stable`
- Pricing Note: Extremely cheap ($0.15 input / $0.60 output).

## NEW PROVIDER: MISTRAL
- Base URL: https://api.mistral.ai/v1
- Models: `mistral-large-latest`, `pixtral-large-2411`, `pixtral-12b-2409`, `codestral-latest`.
```

Sources
[1] Pricing - Z.AI DEVELOPER DOCUMENT https://docs.z.ai/guides/overview/pricing
[2] Product Pricing - ZHIPU AI OPEN PLATFORM https://bigmodel.cn/pricing
[3] Z.ai Chat - Free AI powered by GLM-4.6 & GLM-4.5 https://z.ai
[4] GLM-4.6: Advanced Agentic, Reasoning and Coding Capabilities https://z.ai/blog/glm-4.6
[5] Z.AI (Zhipu AI) - LiteLLM Docs https://docs.litellm.ai/docs/providers/zai
[6] Pay as you go https://platform.minimax.io/docs/guides/pricing
[7] GLM-4.6V - Z.AI DEVELOPER DOCUMENT https://docs.z.ai/guides/vlm/glm-4.6v
[8] How to access and use Minimax M2 API - CometAPI https://www.cometapi.com/how-to-access-and-use-minimax-m2-api/
[9] Mistral AI Mistral-Medium-3 Pricing (Updated 2025) - Price Per Token https://pricepertoken.com/pricing-page/model/mistral-ai-mistral-medium-3
[10] Inspiring AGI to Benefit Humanity - Z.ai https://z.ai/model-api
[11] MiniMax M2 Pricing - Pay Per Token | $0.15/1M Input Tokens https://minimaxm2.io/pricing
[12] Z.AI: GLM 4.6 V https://openrouter.ai/z-ai/glm-4.6v
[13] M2 for AI Coding Tools - MiniMax API Docs https://platform.minimax.io/docs/guides/text-ai-coding-tools
[14] Pricing - Mistral AI https://mistral.ai/pricing
[15] GLM-4.6: Complete Guide, Pricing, Context Window, and API Access https://llm-stats.com/blog/research/glm-4-6-launch
[16] MiniMax https://www.minimax.io
[17] zai-org/GLM-4.6V https://huggingface.co/zai-org/GLM-4.6V
[18] Quick Start - MiniMax API Docs https://platform.minimax.io/docs/guides/quickstart
[19] Models - from cloud to edge | Mistral AI https://mistral.ai/models
[20] GLM-4.6 - Z.AI DEVELOPER DOCUMENT https://docs.z.ai/guides/llm/glm-4.6
