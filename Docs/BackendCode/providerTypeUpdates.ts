/**
 * Provider Type Updates
 *
 * Update your functions/src/providers/types.ts with these enhanced types
 * to support tool calling for memory creation.
 */

export interface ProviderRequest {
  messages: Array<{
    role: 'system' | 'user' | 'assistant';
    content: string;
  }>;
  model?: string;
  temperature?: number;
  maxTokens?: number;
  enableMemoryTool?: boolean; // NEW: Enable create_memory tool
  enableTools?: boolean; // NEW: Enable all tools (future: code execution, web search, etc.)
}

export interface ToolCall {
  id: string; // Unique ID for this tool call
  name: string; // Tool name (e.g., "create_memory")
  arguments: any; // Parsed JSON arguments (provider-specific parsing)
}

export interface ProviderResponse {
  content: string; // AI's text response
  model?: string; // Model used for generation
  usage?: {
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
  };
  toolCalls?: ToolCall[]; // NEW: Tool calls made by the AI
  finishReason?: string; // 'stop', 'tool_use', 'length', etc.
}

/**
 * Example Anthropic Provider Update
 *
 * Update functions/src/providers/anthropicProvider.ts
 */

import { getMemoryToolForProvider } from '../tools/memoryTool';

export class AnthropicProvider {
  async invoke(request: ProviderRequest, userId: string): Promise<ProviderResponse> {
    const apiKey = await this.getApiKey(userId);

    // Build tools array
    const tools = [];
    if (request.enableMemoryTool !== false) {
      tools.push(getMemoryToolForProvider('anthropic'));
    }

    // Format messages for Claude
    const messages = request.messages
      .filter(m => m.role !== 'system')
      .map(msg => ({
        role: msg.role as 'user' | 'assistant',
        content: msg.content,
      }));

    // Extract system message
    const systemMessage = request.messages.find(m => m.role === 'system');

    const apiRequest = {
      model: request.model || 'claude-sonnet-4-5-20250929',
      max_tokens: request.maxTokens || 4096,
      temperature: request.temperature,
      system: systemMessage?.content,
      messages,
      ...(tools.length > 0 && { tools }),
    };

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify(apiRequest),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Anthropic API error: ${error}`);
    }

    const data = await response.json();

    // Extract text content
    let content = '';
    const textBlocks = data.content.filter((block: any) => block.type === 'text');
    if (textBlocks.length > 0) {
      content = textBlocks.map((block: any) => block.text).join('\n');
    }

    // Extract tool calls
    const toolCalls = this.extractToolCalls(data);

    return {
      content,
      model: data.model,
      usage: {
        promptTokens: data.usage.input_tokens,
        completionTokens: data.usage.output_tokens,
        totalTokens: data.usage.input_tokens + data.usage.output_tokens,
      },
      toolCalls,
      finishReason: data.stop_reason,
    };
  }

  private extractToolCalls(response: any): ToolCall[] {
    const toolCalls: ToolCall[] = [];

    if (response.content) {
      for (const block of response.content) {
        if (block.type === 'tool_use') {
          toolCalls.push({
            id: block.id,
            name: block.name,
            arguments: block.input, // Already parsed JSON object
          });
        }
      }
    }

    return toolCalls;
  }

  private async getApiKey(userId: string): Promise<string> {
    // Your existing API key retrieval logic
    // ...
    return 'your-api-key';
  }
}

/**
 * Example OpenAI Provider Update
 *
 * Update functions/src/providers/openaiProvider.ts
 */

export class OpenAIProvider {
  async invoke(request: ProviderRequest, userId: string): Promise<ProviderResponse> {
    const apiKey = await this.getApiKey(userId);

    // Build tools array
    const tools = [];
    if (request.enableMemoryTool !== false) {
      tools.push(getMemoryToolForProvider('openai'));
    }

    const apiRequest = {
      model: request.model || 'gpt-4o',
      messages: request.messages,
      temperature: request.temperature,
      max_tokens: request.maxTokens,
      ...(tools.length > 0 && { tools, tool_choice: 'auto' }),
    };

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(apiRequest),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`OpenAI API error: ${error}`);
    }

    const data = await response.json();
    const message = data.choices[0]?.message;

    if (!message) {
      throw new Error('No message in OpenAI response');
    }

    // Extract tool calls
    const toolCalls: ToolCall[] = [];
    if (message.tool_calls && Array.isArray(message.tool_calls)) {
      for (const tc of message.tool_calls) {
        toolCalls.push({
          id: tc.id,
          name: tc.function.name,
          arguments: JSON.parse(tc.function.arguments), // Parse JSON string
        });
      }
    }

    return {
      content: message.content || '',
      model: data.model,
      usage: {
        promptTokens: data.usage.prompt_tokens,
        completionTokens: data.usage.completion_tokens,
        totalTokens: data.usage.total_tokens,
      },
      toolCalls,
      finishReason: data.choices[0]?.finish_reason,
    };
  }

  private async getApiKey(userId: string): Promise<string> {
    // Your existing API key retrieval logic
    return 'your-api-key';
  }
}

/**
 * Example Gemini Provider Update
 *
 * Update functions/src/providers/geminiProvider.ts
 */

export class GeminiProvider {
  async invoke(request: ProviderRequest, userId: string): Promise<ProviderResponse> {
    const apiKey = await this.getApiKey(userId);

    // Build tools array
    const tools = [];
    if (request.enableMemoryTool !== false) {
      tools.push(getMemoryToolForProvider('gemini'));
    }

    // Format for Gemini API
    const contents = request.messages.map(msg => ({
      role: msg.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: msg.content }],
    }));

    const apiRequest = {
      contents,
      generationConfig: {
        temperature: request.temperature,
        maxOutputTokens: request.maxTokens,
      },
      ...(tools.length > 0 && {
        tools: [{ functionDeclarations: tools }],
      }),
    };

    const model = request.model || 'gemini-2.5-pro';
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;

    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(apiRequest),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Gemini API error: ${error}`);
    }

    const data = await response.json();
    const candidate = data.candidates?.[0];

    if (!candidate) {
      throw new Error('No candidate in Gemini response');
    }

    // Extract text content
    let content = '';
    const textParts = candidate.content.parts.filter((p: any) => p.text);
    if (textParts.length > 0) {
      content = textParts.map((p: any) => p.text).join('\n');
    }

    // Extract tool calls
    const toolCalls: ToolCall[] = [];
    const functionCalls = candidate.content.parts.filter((p: any) => p.functionCall);
    for (const fc of functionCalls) {
      toolCalls.push({
        id: `${fc.functionCall.name}_${Date.now()}`, // Gemini doesn't provide IDs
        name: fc.functionCall.name,
        arguments: fc.functionCall.args, // Already an object
      });
    }

    return {
      content,
      model,
      usage: {
        promptTokens: data.usageMetadata?.promptTokenCount || 0,
        completionTokens: data.usageMetadata?.candidatesTokenCount || 0,
        totalTokens: data.usageMetadata?.totalTokenCount || 0,
      },
      toolCalls,
      finishReason: candidate.finishReason,
    };
  }

  private async getApiKey(userId: string): Promise<string> {
    // Your existing API key retrieval logic
    return 'your-api-key';
  }
}
