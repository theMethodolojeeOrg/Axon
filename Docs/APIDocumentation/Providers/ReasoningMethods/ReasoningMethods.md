Here is the breakdown of how each provider currently signifies reasoning (Chain of Thought) tokens in their API responses as of late 2025:

| Provider | Model(s) | Reasoning Signal / Location | Notes |
| :--- | :--- | :--- | :--- |
| **DeepSeek** | `deepseek-reasoner` | **`reasoning_content`** field | The API response object has a distinct top-level `reasoning_content` string separate from the standard `content` string. |
| **Z.ai (Zhipu)** | `glm-4.6`, `glm-4.6v` | **`<think>...</think>`** | Reasoning text is typically embedded at the start of the `content` string, wrapped in XML-like tags. (Beta API may also use a separate field; check `thinking` param status). |
| **Perplexity** | `sonar-reasoning-pro` | **`<think>...</think>`** | The reasoning tokens are prepended directly to the main `content` string, wrapped in `<think>` tags. You must strip these manually if you only want the final answer. |
| **OpenAI** | `o1`, `o3` family | **Hidden (Internal)** | Reasoning tokens are **not** visible in the API response. They are billed as output tokens but filtered out before you see the final text. |
| **Anthropic** | Claude 4.5 family | **`type: "thinking"`** block | The API returns a distinct content block type. You receive a `thinking` block first, followed by a `text` block. |
| **Kimi (Moonshot)** | `kimi-k2-thinking` | **`reasoning_content`** field | Similar to DeepSeek, Kimi exposes a dedicated `reasoning_content` field in the response object alongside `content`. |
| **Mistral** | `mistral-large` (Thinking) | **`additionalContent`** block | Reasoning is returned in a structured `additionalContent['thinking']` block, separate from the main `content`. |
| **MiniMax** | `MiniMax-M2` | **Text Prefix (Standard)** | Typically outputs reasoning directly in the text, often starting with "Thinking Process:" or similar if prompted, but less standardized than others. |
| **Google** | `gemini-3-pro` (Deep Think) | **Hidden / `thinking_process`** | Like OpenAI, thinking tokens are often hidden by default in the standard response, though some Vertex AI previews expose a `thinking_process` field. |

### **Integration Tip for Your Subroutine**

To normalize this across your app, your agent should look for these patterns and extract them into a unified `reasoning` field in your internal data model:

1. **Check for dedicated fields first:** `reasoning_content` (DeepSeek/Kimi), `thinking` block (Anthropic).
2. **Fallback to regex parsing:** If those are empty, check `content` for `<think>(.*?)</think>` (Perplexity/Z.ai).
3. **Handle Hidden:** For OpenAI, note that reasoning is "Internal/Hidden".

This ensures your users can always see the "Thought Process" in a consistent UI element, regardless of which provider is doing the thinking.

Sources
[1] Reasoning Model (deepseek... https://api-docs.deepseek.com/guides/reasoning_model
[2] Your First API Call | DeepSeek API Docs https://api-docs.deepseek.com
[3] Deepseek Reasoning Chat Format (Reasoning Content)¶ https://docs.newapi.pro/en/api/deepseek-reasoning-chat/
[4] DeepSeek API: A Guide With Examples and Cost ... https://www.datacamp.com/tutorial/deepseek-api
[5] Deepseek reasoning 格式（Reasoning Content） - New API https://docs.newapi.pro/api/deepseek-reasoning-chat/
[6] Core Parameters - Z.AI DEVELOPER DOCUMENT https://docs.z.ai/guides/overview/concept-param
[7] OpenAI o1: What Developers Need to Know https://zilliz.com/blog/openai-o1-what-developers-need-to-know
[8] Mistral - Prism https://prismphp.com/providers/mistral.html
[9] How to Use Kimi K2 Thinking API— a practical guide https://www.cometapi.com/how-to-use-kimi-k2-thinking-api-a-practical-guide/
[10] Sonar reasoning pro https://docs.perplexity.ai/getting-started/models/models/sonar-reasoning-pro
[11] Building with extended thinking - Claude Docs https://platform.claude.com/docs/en/build-with-claude/extended-thinking
[12] grok-4-fast-reasoning https://docs.aimlapi.com/api-references/text-models-llm/xai/grok-4-fast-reasoning
[13] DeepSeek models - Amazon Bedrock - AWS Documentation https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-deepseek.html
[14] GLM-4.6 - Z.AI DEVELOPER DOCUMENT https://docs.z.ai/guides/llm/glm-4.6
[15] Reasoning models | OpenAI API https://platform.openai.com/docs/guides/reasoning
[16] REST API (experimental) - Mistral-common https://mistralai.github.io/mistral-common/usage/experimental/
[17] Kimi K2 Thinking: Open-Source LLM Guide, Benchmarks ... https://www.datacamp.com/fr/tutorial/kimi-k2-thinking-guide
[18] Structured Outputs Guide https://docs.perplexity.ai/guides/structured-outputs
[19] Building with extended thinking - Claude Docs https://anthropic.mintlify.app/en/docs/build-with-claude/extended-thinking
[20] Welcome to the xAI documentation https://docs.x.ai/docs/models/grok-4-0709
