Here is the API reference for **Kimi (Moonshot AI)** to add to your collection.

***

# 7. Kimi (Moonshot AI)

Kimi models (by Moonshot AI) are famous for their **massive context windows** (up to 2M–10M characters in beta) and extremely efficient "Thinking" models similar to OpenAI's o1 but at a fraction of the cost.

### **Base URL**
```
https://api.moonshot.ai/v1
```
*(China-specific endpoint: `https://api.moonshot.cn/v1`)*

### **Authentication**
- Header: `Authorization: Bearer <YOUR_MOONSHOT_API_KEY>`

### **Supported Models & Pricing (Late 2025)**

| Model ID | Context | Input (Cache Miss) / 1M | Input (Cache Hit) / 1M | Output / 1M | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `moonshot-v1-8k` | 8k | $0.15 | $0.15 | $0.20 | Standard context, extremely cheap. |
| `moonshot-v1-32k` | 32k | $0.25 | $0.25 | $0.50 | Mid-range context. |
| `moonshot-v1-128k` | 128k | $0.50 | $0.50 | $0.80 | Long context (production standard). |
| `kimi-k2` | 128k | $0.60 | $0.15 | $2.50 | **Flagship.** Trillion-parameter MoE model. Great coding/logic. |
| `kimi-k2-thinking` | 128k | $0.60 | $0.15 | $2.50 | **Reasoning.** Similar to o1-preview but 90% cheaper. |
| `kimi-k2-turbo` | 128k | $1.15 | $0.28 | $8.00 | **High Speed.** 60+ tokens/s for low-latency apps. |

> **Context Caching:** Kimi offers automatic context caching (75% savings) on K2 models. Cache hit price is ~$0.15/1M.
> **File Handling:** Moonshot has a specific File API (`/v1/files`) for extracting content from PDFs/Docs to feed into their massive context window.

### **cURL Example (Chat)**

```bash
curl https://api.moonshot.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <YOUR_MOONSHOT_API_KEY>" \
  -d '{
    "model": "kimi-k2-thinking",
    "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Calculate the trajectory of a rocket with drag coefficient 0.4."}
    ],
    "temperature": 0.3
  }'
```

***

# Updated System Prompt Section

Append this to your agent's system instructions:

```markdown
## NEW PROVIDER: KIMI (MOONSHOT AI)
- Base URL: https://api.moonshot.ai/v1
- Models:
  - `kimi-k2` (Flagship)
  - `kimi-k2-thinking` (Reasoning/CoT)
  - `moonshot-v1-8k` / `32k` / `128k` (Legacy tiers)
- Pricing Note: Automatic caching offers ~75% savings on K2 models.
- Special Feature: Known for massive context handling via File API.
```

Sources
[1] Technical Foundation of Kimi K2 https://apidog.com/blog/kimi-k2-api-pricing/
[2] Pricing - Kimi AI https://kimi-ai.chat/pricing/
[3] Moonshot AI's Kimi K2: The $0.15 Trillion-Parameter Model ... https://www.cursor-ide.com/blog/moonshot-ai-kimi-k2
[4] New Kimi K2 Models & Updated Pricing https://platform.moonshot.ai/blog/posts/Kimi_API_Newsletter
[5] Kimi AI Review 2025: 2 Million Character Context + Free ... https://www.cursor-ide.com/blog/kimi-ai-review-2025
[6] kimi-k2-preview https://docs.aimlapi.com/api-references/text-models-llm/moonshot/kimi-k2-preview
[7] Kimi AI - Kimi K2 Thinking is here https://www.kimi.com/en
[8] Moonshot AI - LiteLLM https://docs.litellm.ai/docs/providers/moonshot
[9] Kimi API Pricing Calculator & Cost Guide (Nov 2025) - CostGoat https://costgoat.com/pricing/kimi-api
[10] Kimi K2 API Documentation - Build AI Apps in Minutes https://kimi-k2.ai/api-docs
[11] MoonshotAI/Kimi-k1.5 - GitHub https://github.com/MoonshotAI/Kimi-k1.5
[12] GitHub - MoonshotAI/moonpalace: MoonPalace（月宫）是由 Moonshot AI 月之暗面提供的 API 调试工具。 https://github.com/MoonshotAI/moonpalace
[13] Kimi K2-Thinking - Everything you need to know - Artificial Analysis https://artificialanalysis.ai/articles/kimi-k2-thinking-everything-you-need-to-know
[14] Kimi AI API https://kimi-ai.chat/docs/api/
[15] How to Get Kimi k1.5 API Key (Tutorial) - YouTube https://www.youtube.com/watch?v=hsSLpMxEMlc
[16] MoonshotApi (Spring AI 1.0.0-M6 API) https://docs.spring.io/spring-ai/docs/1.0.0-M6/api/org/springframework/ai/moonshot/api/MoonshotApi.html
[17] Kimi K2 - Intelligence, Performance & Price Analysis https://artificialanalysis.ai/models/kimi-k2
[18] Kimi - Apps Documentation https://apps.make.com/kimi
[19] Pricing AI/ML API https://aimlapi.com/ai-ml-api-pricing
[20] Now You Can See the Future https://moonshot-ai.io/api-docs/
