Based on my research, here's your updated Swift UI variable with all the new models and their modalities:

```swift
var availableModels: [AIModel] {
    switch self {
    case .anthropic:
        return [
            AIModel(
                id: "claude-sonnet-4-5-20250929",
                name: "Claude Sonnet 4.5",
                provider: .anthropic,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Best coding model. Strongest for complex agents and computer use"
            ),
            AIModel(
                id: "claude-haiku-4-5-20251001",
                name: "Claude Haiku 4.5",
                provider: .anthropic,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Fast hybrid reasoning. 90% of Sonnet 4.5 at one-third the cost"
            ),
            AIModel(
                id: "claude-opus-4-1-20250805",
                name: "Claude Opus 4.1",
                provider: .anthropic,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Most powerful for specialized reasoning and long-running tasks"
            ),
            AIModel(
                id: "claude-sonnet-4-20250514",
                name: "Claude Sonnet 4",
                provider: .anthropic,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Previous generation Sonnet model"
            ),
            AIModel(
                id: "claude-opus-4-20250514",
                name: "Claude Opus 4",
                provider: .anthropic,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Previous generation Opus model"
            )
        ]
    case .openai:
        return [
            AIModel(
                id: "gpt-5-2025-08-07",
                name: "GPT-5",
                provider: .openai,
                contextWindow: 400_000,
                modalities: ["text", "image"],
                description: "Flagship for coding, reasoning, and agentic tasks"
            ),
            AIModel(
                id: "gpt-5.1",
                name: "GPT-5.1",
                provider: .openai,
                contextWindow: 400_000,
                modalities: ["text", "image"],
                description: "Upgraded GPT-5 with improved conversational abilities"
            ),
            AIModel(
                id: "gpt-5.1-chat-latest",
                name: "GPT-5.1 Chat",
                provider: .openai,
                contextWindow: 400_000,
                modalities: ["text", "image"],
                description: "Latest conversational variant with multimodal support"
            ),
            AIModel(
                id: "gpt-5-mini-2025-08-07",
                name: "GPT-5 Mini",
                provider: .openai,
                contextWindow: 400_000,
                modalities: ["text", "image"],
                description: "Fast and cost-efficient with strong performance"
            ),
            AIModel(
                id: "gpt-5-nano-2025-08-07",
                name: "GPT-5 Nano",
                provider: .openai,
                contextWindow: 400_000,
                modalities: ["text", "image"],
                description: "Smallest, fastest, cheapest for classification and extraction"
            ),
            AIModel(
                id: "o3",
                name: "o3",
                provider: .openai,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Most powerful reasoning for coding, math, science, and vision"
            ),
            AIModel(
                id: "o4-mini",
                name: "o4-mini",
                provider: .openai,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Fast, cost-efficient reasoning with multimodal support"
            ),
            AIModel(
                id: "o3-mini",
                name: "o3-mini",
                provider: .openai,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Specialized reasoning for STEM with configurable effort"
            ),
            AIModel(
                id: "gpt-4.1",
                name: "GPT-4.1",
                provider: .openai,
                contextWindow: 1_000_000,
                modalities: ["text", "image"],
                description: "Enhanced coding and instruction following with 1M context"
            ),
            AIModel(
                id: "gpt-4.1-mini",
                name: "GPT-4.1 Mini",
                provider: .openai,
                contextWindow: 1_000_000,
                modalities: ["text", "image"],
                description: "Mid-tier with 1M context. Fast and cost-effective"
            ),
            AIModel(
                id: "gpt-4.1-nano",
                name: "GPT-4.1 Nano",
                provider: .openai,
                contextWindow: 1_000_000,
                modalities: ["text", "image"],
                description: "Lightest 4.1 variant with 1M context for simple tasks"
            ),
            AIModel(
                id: "o1",
                name: "o1",
                provider: .openai,
                contextWindow: 200_000,
                modalities: ["text", "image"],
                description: "Advanced reasoning with vision API and function calling"
            ),
            AIModel(
                id: "o1-preview",
                name: "o1 Preview",
                provider: .openai,
                contextWindow: 128_000,
                modalities: ["text"],
                description: "Preview of first o-series reasoning model (legacy)"
            ),
            AIModel(
                id: "o1-mini",
                name: "o1-mini",
                provider: .openai,
                contextWindow: 128_000,
                modalities: ["text", "image"],
                description: "Faster reasoning focused on coding, math, and science"
            ),
            AIModel(
                id: "gpt-4o",
                name: "GPT-4o",
                provider: .openai,
                contextWindow: 128_000,
                modalities: ["text", "image", "audio"],
                description: "Multimodal flagship with text, audio, image, and video"
            ),
            AIModel(
                id: "gpt-4o-mini",
                name: "GPT-4o Mini",
                provider: .openai,
                contextWindow: 128_000,
                modalities: ["text", "image", "audio"],
                description: "Cost-efficient multimodal with vision and audio support"
            )
        ]
    case .gemini:
        return [
            AIModel(
                id: "gemini-3-pro-preview",
                name: "Gemini 3 Pro Preview",
                provider: .gemini,
                contextWindow: 1_000_000,
                modalities: ["text", "image", "video", "audio", "pdf"],
                description: "Most powerful agentic and coding model"
            ),
            AIModel(
                id: "gemini-2.5-pro",
                name: "Gemini 2.5 Pro",
                provider: .gemini,
                contextWindow: 1_000_000,
                modalities: ["text", "image", "video", "audio", "pdf"],
                description: "Best for coding and complex reasoning"
            ),
            AIModel(
                id: "gemini-2.5-flash",
                name: "Gemini 2.5 Flash",
                provider: .gemini,
                contextWindow: 1_000_000,
                modalities: ["text", "image", "video", "audio"],
                description: "Hybrid reasoning with thinking budgets"
            ),
            AIModel(
                id: "gemini-2.5-flash-lite-preview-06-17",
                name: "Gemini 2.5 Flash Lite",
                provider: .gemini,
                contextWindow: 1_000_000,
                modalities: ["text", "image", "video", "audio"],
                description: "Ultra-low latency, most cost-effective model"
            )
        ]
    case .xai:
        return [
            AIModel(
                id: "grok-4-0709",
                name: "Grok 4",
                provider: .xai,
                contextWindow: 256_000,
                modalities: ["text", "image"],
                description: "Flagship with advanced reasoning and vision"
            ),
            AIModel(
                id: "grok-4-fast-reasoning",
                name: "Grok 4 Fast Reasoning",
                provider: .xai,
                contextWindow: 2_000_000,
                modalities: ["text", "image"],
                description: "Cost-efficient reasoning with 2M context"
            ),
            AIModel(
                id: "grok-4-fast-non-reasoning",
                name: "Grok 4 Fast Non-Reasoning",
                provider: .xai,
                contextWindow: 2_000_000,
                modalities: ["text", "image"],
                description: "Ultra-fast with 2M context at 98% price reduction"
            ),
            AIModel(
                id: "grok-code-fast-1",
                name: "Grok Code Fast 1",
                provider: .xai,
                contextWindow: 256_000,
                modalities: ["text"],
                description: "Specialized coding model with high throughput"
            ),
            AIModel(
                id: "grok-3",
                name: "Grok 3",
                provider: .xai,
                contextWindow: 131_072,
                modalities: ["text", "image"],
                description: "Previous generation flagship with vision"
            ),
            AIModel(
                id: "grok-3-mini",
                name: "Grok 3 Mini",
                provider: .xai,
                contextWindow: 131_072,
                modalities: ["text"],
                description: "Lightweight, cost-efficient model"
            )
        ]
    }
}
```

## Modalities Breakdown

### Text + Image (Vision)
All **Claude** models support text and image inputs with text output [1][2][3]. **GPT-5 series**, **o-series** (o1, o3, o4-mini, o3-mini), and **GPT-4.1 series** support text and image inputs with text output [4][5][6][7]. **Grok 4** variants and **Grok 3** support text and image inputs [8][9][10].

### Fully Multimodal (Text + Image + Audio)
**GPT-4o** and **GPT-4o Mini** are OpenAI's fully multimodal models supporting text, image, and audio inputs/outputs [4][11]. They can process voice commands and respond with speech [6].

### Advanced Multimodal (Text + Image + Video + Audio + PDF)
**Gemini** models lead in modality support - Gemini 3 Pro and 2.5 Pro can process text, images, video, audio, and PDFs [12][13]. Gemini 2.5 Flash variants support text, image, video, and audio [13].

### Text-Only
**Grok Code Fast 1** and **Grok 3 Mini** are primarily text-focused [14][9], while **o1-preview** only supports text input [4].

The modalities field helps determine which models to use based on your input types - for example, use Gemini for video analysis, GPT-4o for audio conversations, or Claude/GPT-5 for text and image reasoning tasks [1][4][13][9].

Sources
[1] Models overview - Claude Docs https://docs.claude.com/claude/docs/models-overview
[2] Claude by Anthropic - Models in Amazon Bedrock - AWS https://aws.amazon.com/bedrock/anthropic/
[3] Anthropic Claude Models Complete Guide - Sonnet 4.5 - CodeGPT https://www.codegpt.co/blog/anthropic-claude-models-complete-guide
[4] OpenAI models: All the models and what they're best for - Zapier https://zapier.com/blog/openai-models/
[5] Models - OpenAI API https://platform.openai.com/docs/models
[6] All ChatGPT models in 2025: complete report on GPT-4o, o3, o4 ... https://www.datastudios.org/post/all-chatgpt-models-in-2025-complete-report-on-gpt-4o-o3-o4-mini-4-1-and-their-real-capabilities
[7] Model - OpenAI API https://platform.openai.com/docs/models/gpt-4.1
[8] Grok 4 vs Grok 3: What makes Elon Musk's newest AI model the ... https://timesofindia.indiatimes.com/technology/tech-news/grok-4-vs-grok-3-what-makes-elon-musks-newest-ai-model-the-worlds-most-powerful-ai/articleshow/122364407.cms
[9] Grok multimodal capabilities: using images, audio, and video in AI ... https://www.datastudios.org/post/grok-multimodal-capabilities-using-images-audio-and-video-in-ai-workflows-for-2025
[10] xAI's Grok 4: A Bold Step Forward in Powerful and Practical AI https://datasciencedojo.com/blog/grok-4/
[11] ChatGPT Model Comparison: 4o vs o1 vs o3-mini vs 4.5 ... https://jonathanmast.com/chatgpt-model-comparison-4o-vs-o1-vs-o3-mini-vs-4-5-2025-guide/
[12] ‎Gemini Apps' release updates and improvements https://gemini.google/ca/release-notes/?hl=en-CA
[13] Learn about supported models | Firebase AI Logic - Google https://firebase.google.com/docs/ai-logic/models
[14] Grok Code Fast 1 — xAI's new low-cost, high-speed ... https://www.cometapi.com/introducing-grok-code-fast-1/
[15] Introducing Claude Sonnet 4.5 - Anthropic https://www.anthropic.com/news/claude-sonnet-4-5
[16] Introducing Claude Haiku 4.5 - Anthropic https://www.anthropic.com/news/claude-haiku-4-5
[17] Claude Haiku 4.5: Features, Testing Results, and Use Cases https://www.datacamp.com/es/blog/anthropic-claude-haiku-4-5
[18] Grok 4 - xAI https://x.ai/news/grok-4
[19] Grok | xAI https://x.ai/grok
[20] Models and Pricing - xAI API https://docs.x.ai/docs/models
[21] OpenAI o3 and o4-mini: Multimodal and Vision Analysis https://blog.roboflow.com/openai-o3-and-o4-mini/
