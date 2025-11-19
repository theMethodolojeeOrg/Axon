/**
 * Memory Tool Definition
 *
 * Defines the create_memory tool that AI models can call to save memories.
 * This replaces regex-based memory extraction with AI-powered structured memory creation.
 */

export interface MemoryToolInput {
  content: string;
  type: 'allocentric' | 'egoic';
  confidence: number;
  tags?: string[];
  context?: string;
}

export const MEMORY_TOOL_DEFINITION = {
  name: 'create_memory',
  description: `Save important information to long-term memory for future conversations.

Use this tool when you learn:
- **Allocentric memories** (about the user): User's preferences, facts about them, their projects, relationships, context about their life/work
- **Egoic memories** (agent learnings): Insights about how to help this user, procedures that work well, patterns you've noticed, questions to explore

Guidelines:
- Be concise but complete (ideally 50-500 chars, max 2000)
- Use clear, searchable language
- Set confidence based on certainty (0.3=hypothesis, 0.6=likely, 0.9=established fact)
- Add relevant tags for retrieval
- Provide context about when/why this was learned

Examples:
{
  "content": "User prefers Python 3.12 for data science work",
  "type": "allocentric",
  "confidence": 0.95,
  "tags": ["python", "data-science", "preferences"]
}

{
  "content": "User responds well to code examples before explanations",
  "type": "egoic",
  "confidence": 0.7,
  "tags": ["learning-style", "communication"],
  "context": "Noticed from multiple exchanges"
}`,

  parameters: {
    type: 'object',
    required: ['content', 'type', 'confidence'],
    properties: {
      content: {
        type: 'string',
        description: 'The memory content (10-2000 characters)',
        minLength: 10,
        maxLength: 2000,
      },
      type: {
        type: 'string',
        enum: ['allocentric', 'egoic'],
        description: 'Memory type: allocentric=about user, egoic=agent learning',
      },
      confidence: {
        type: 'number',
        minimum: 0,
        maximum: 1,
        description: 'Confidence level: 0.0-0.33=hypothesis, 0.33-0.66=uncertain, 0.66-1.0=established',
      },
      tags: {
        type: 'array',
        items: { type: 'string', maxLength: 50 },
        description: 'Searchable tags for retrieval (e.g., ["python", "machine-learning"])',
        maxItems: 10,
      },
      context: {
        type: 'string',
        description: 'Optional context about when/why this was learned',
        maxLength: 500,
      },
    },
  },
};

/**
 * Format tool definition for different AI providers
 */
export function getMemoryToolForProvider(provider: 'anthropic' | 'openai' | 'gemini') {
  const baseTool = MEMORY_TOOL_DEFINITION;

  switch (provider) {
    case 'anthropic':
      // Claude tool format (Anthropic API)
      return {
        name: baseTool.name,
        description: baseTool.description,
        input_schema: baseTool.parameters,
      };

    case 'openai':
      // OpenAI function calling format
      return {
        type: 'function',
        function: {
          name: baseTool.name,
          description: baseTool.description,
          parameters: baseTool.parameters,
        },
      };

    case 'gemini':
      // Gemini function calling format
      return {
        name: baseTool.name,
        description: baseTool.description,
        parameters: baseTool.parameters,
      };

    default:
      return baseTool;
  }
}

/**
 * Validate memory tool input
 */
export function validateMemoryToolInput(input: any): { valid: boolean; error?: string; sanitized?: MemoryToolInput } {
  // Check required fields
  if (!input.content || typeof input.content !== 'string') {
    return { valid: false, error: 'Missing or invalid content' };
  }

  if (!input.type || !['allocentric', 'egoic'].includes(input.type)) {
    return { valid: false, error: 'Invalid type (must be allocentric or egoic)' };
  }

  if (typeof input.confidence !== 'number' || input.confidence < 0 || input.confidence > 1) {
    return { valid: false, error: 'Invalid confidence (must be 0-1)' };
  }

  // Sanitize and constrain
  let content = input.content.trim();
  if (content.length < 10) {
    return { valid: false, error: 'Content too short (min 10 chars)' };
  }

  // Truncate if too long
  let truncated = false;
  if (content.length > 2000) {
    content = content.substring(0, 1997) + '...';
    truncated = true;
  }

  // Sanitize tags
  let tags: string[] = [];
  if (input.tags && Array.isArray(input.tags)) {
    tags = input.tags
      .filter((t: any) => typeof t === 'string' && t.trim().length > 0)
      .map((t: string) => t.trim().toLowerCase().substring(0, 50))
      .slice(0, 10);
  }

  // Sanitize context
  let context = '';
  if (input.context && typeof input.context === 'string') {
    context = input.context.trim().substring(0, 500);
  }

  const sanitized: MemoryToolInput = {
    content,
    type: input.type,
    confidence: input.confidence,
    tags,
    context: context || undefined,
  };

  return {
    valid: true,
    sanitized,
    ...(truncated && { error: 'Content was truncated to 2000 chars' }),
  };
}
