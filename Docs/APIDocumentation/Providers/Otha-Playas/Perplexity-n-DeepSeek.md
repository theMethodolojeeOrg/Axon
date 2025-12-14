This guide provides API reference documentation for integrating **Perplexity** (Sonar) and **DeepSeek** models as of late 2025. It includes current model IDs, pricing, and system prompt examples for each provider.

***

# 1. Perplexity (Sonar) API

Perplexity’s API provides programmatic access to its "online" LLMs, which cite sources and pull real-time web data.

### **Base URL**
```
https://api.perplexity.ai
```

### **Authentication**
- Header: `Authorization: Bearer <YOUR_API_KEY>`

### **Supported Models & Pricing (Dec 2025)**

| Model ID | Context Window | Input Cost / 1M | Output Cost / 1M | Search Cost / 1k | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `sonar-reasoning-pro` | 128k | $2.00 | $8.00 | $5.00 | **Recommended.** Best for complex queries. Uses advanced reasoning (CoT) + search. |
| `sonar-reasoning` | 128k | $1.00 | $5.00 | $5.00 | Lighter reasoning model. Good balance of speed/intelligence. |
| `sonar-pro` | 200k | $3.00 | $15.00 | $5.00 | High-capacity standard search model (no reasoning tokens). |
| `sonar` | 128k | $1.00 | $1.00 | $5.00 | Cheapest standard search model. Good for simple lookups. |

> **Note on Pricing:** Perplexity charges per token **plus** a flat fee per search request (typically priced per 1,000 requests). The "Search Cost" above is normalized to per-1k requests for comparison.

### **cURL Example**

```bash
curl --location 'https://api.perplexity.ai/chat/completions' \
--header 'Authorization: Bearer <YOUR_PPLX_API_KEY>' \
--header 'Content-Type: application/json' \
--data '{
    "model": "sonar-reasoning-pro",
    "messages": [
        {
            "role": "system",
            "content": "You are a helpful research assistant. Always cite your sources."
        },
        {
            "role": "user",
            "content": "What is the current stock price of TSLA and its P/E ratio?"
        }
    ],
    "temperature": 0.2,
    "max_tokens": 1024,
    "top_p": 0.9,
    "search_domain_filter": ["finance.yahoo.com", "bloomberg.com"],
    "return_images": false,
    "return_related_questions": false
}'
```

### **Key Features**
- **Online:** All `sonar` models have internet access.
- **Citations:** Returns a `citations` array in the response object.
- **Reasoning:** Models with `reasoning` in the ID produce "thinking" tokens (often hidden or summarized) to improve accuracy.

***

# 2. DeepSeek API

DeepSeek provides highly cost-efficient reasoning and standard LLMs, often undercutting major providers while delivering frontier-class performance.

### **Base URL**
```
https://api.deepseek.com
```

### **Authentication**
- Header: `Authorization: Bearer <YOUR_DEEPSEEK_API_KEY>`

### **Supported Models & Pricing (Dec 2025)**

| Model ID | Context Window | Input (Cache Hit) / 1M | Input (Cache Miss) / 1M | Output Cost / 1M | Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `deepseek-reasoner` | 128k | $0.14 | $0.55 | $2.19 | **(DeepSeek-R1)** Flagship reasoning model (CoT). Best for math/code. |
| `deepseek-chat` | 128k | $0.07 | $0.27 | $1.10 | **(DeepSeek-V3)** Standard frontier model. Extremely cheap & fast. |

> **Context Caching:** DeepSeek automatically caches context. If your prefix matches a previous request, you pay the significantly lower "Cache Hit" price.

### **cURL Example**

```bash
curl https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <YOUR_DEEPSEEK_API_KEY>" \
  -d '{
        "model": "deepseek-reasoner",
        "messages": [
          {"role": "system", "content": "You are a specialized coding assistant."},
          {"role": "user", "content": "Write a Python script to scrape a sitemap recursively."}
        ],
        "temperature": 0.6,
        "stream": false
      }'
```

### **Key Features**
- **Reasoning (R1):** The `deepseek-reasoner` model outputs a `reasoning_content` field (in the API response) showing its Chain of Thought process before the final answer.
- **Context Caching:** Enabled by default (TTL 60 seconds to hours depending on usage volume).
- **Prefix Injection:** Supports `prefix` in messages (beta) to force the model to start its answer a certain way.

***

# 3. Quick Comparison Table

| Feature | Perplexity (`sonar-reasoning-pro`) | DeepSeek (`deepseek-reasoner`) |
| :--- | :--- | :--- |
| **Primary Use** | Web Search / Real-time Fact Checking | Code / Math / Pure Logic |
| **Web Access** | ✅ Yes (Built-in) | ❌ No (Offline only) |
| **Cost** | High ($2 in / $8 out + search fee) | Very Low ($0.55 in / $2.19 out) |
| **Context** | 128k | 128k |
| **Reasoning** | Hidden/Internal CoT | Visible `reasoning_content` |

***

# 4. System Prompt for Your "Model Sync" Agent

If you are feeding this into your subroutine agent, you can append this section to its system instructions:

```markdown
## NEW PROVIDER: PERPLEXITY
- Base URL: https://api.perplexity.ai
- Models:
  - `sonar-reasoning-pro` (128k context, online, CoT)
  - `sonar-reasoning` (128k context, online, CoT)
  - `sonar-pro` (200k context, online)
  - `sonar` (128k context, online)
- Pricing Note: Charges per token PLUS a per-request fee for search complexity.

## NEW PROVIDER: DEEPSEEK
- Base URL: https://api.deepseek.com
- Models:
  - `deepseek-reasoner` (R1) -> 128k context. Specialized for reasoning.
  - `deepseek-chat` (V3) -> 128k context. General purpose.
- Pricing Note: Has distinctive "Cache Hit" vs "Cache Miss" pricing tiers.
```

Sources
[1] Pricing - Perplexity https://docs.perplexity.ai/getting-started/pricing
[2] Overview - Perplexity https://docs.perplexity.ai
[3] Ridiculous API cost of Perplexity AI https://www.reddit.com/r/perplexity_ai/comments/1jbky3f/ridiculous_api_cost_of_perplexity_ai/
[4] Perplexity API Overview: Key Features & Use Cases https://apipie.ai/docs/Models/Perplexity
[5] Perplexity pricing in 2025: Free vs. Pro, features, and costs https://www.withorb.com/blog/perplexity-pricing
[6] API Pricing & How to Use DeepSeek R1 API - Apidogapidog.com › blog › deepseek-r1-review-api https://apidog.com/blog/deepseek-r1-review-api/
[7] DeepSeek's new V3.2-Exp model cuts API pricing in half to less than 3 cents per 1M input tokens https://venturebeat.com/ai/deepseeks-new-v3-2-exp-model-cuts-api-pricing-in-half-to-less-than-3-cents
[8] Perplexity Pro Code: Features, API & Pricing 2025 https://www.byteplus.com/en/topic/431665
[9] Perplexity AI API Pricing: Plans & Costs Explained (2024) https://ashvanikumar.com/perplexity-ai-api-pricing-plans-costs-explained-2024/
[10] DeepSeek API Pricing (2025) — Models, Token Costs ... https://www.deepseek.international/deepseek-api-pricing-2025-the-no-bs-guide-to-real-costs-smart-savings/
[11] DeepSeek API Pricing 2025: Complete Cost Guide for ... https://www.byteplus.com/en/topic/376626
[12] Perplexity AI All Models Available: list, categories, usage, etc https://www.datastudios.org/post/perplexity-ai-all-models-available-list-categories-usage-etc
[13] Pricing - Perplexity https://perplexity.mintlify.app/getting-started/pricing
[14] Models & Pricing | DeepSeek API Docs https://api-docs.deepseek.com/quick_start/pricing
[15] DeepSeek V3.2 Price Drop 2025: Up to 75% Lower ... https://skywork.ai/blog/deepseek-v32-price-drop-2025/
[16] Perplexity Enterprise Pricing - Get Started Today https://www.perplexity.ai/enterprise/pricing
[17] Perplexity API Pricing: How Much Does It Cost? (03/2025) https://openaidiscovery.com/perplexity-api-pricing/
[18] pricing-details-usd | DeepSeek API Docs https://api-docs.deepseek.com/quick_start/pricing-details-usd
[19] Deepseek API Pricing (Updated 2025) - Price Per Token https://pricepertoken.com/pricing-page/provider/deepseek
[20] Perplexity Pricing Guide for the UK (2025) https://wise.com/gb/blog/perplexity-pricing
