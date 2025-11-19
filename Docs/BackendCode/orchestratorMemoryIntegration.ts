/**
 * Orchestrator Integration for Tool-Based Memory Creation
 *
 * This code should be integrated into your apiOrchestrate endpoint
 * to replace the old regex-based extractLearnings() approach.
 */

import { v4 as uuidv4 } from 'uuid';
import { MemoryToolInput, validateMemoryToolInput } from './memoryTool';

/**
 * Process tool calls from AI response and create memories
 *
 * Call this after receiving the AI response in apiOrchestrate
 */
export async function processMemoryToolCalls(
  toolCalls: Array<{ id: string; name: string; arguments: any }>,
  context: {
    userId: string;
    conversationId: string;
    db: FirebaseFirestore.Firestore;
  }
): Promise<{ createdMemories: any[]; warnings: string[] }> {
  const createdMemories: any[] = [];
  const warnings: string[] = [];

  if (!toolCalls || toolCalls.length === 0) {
    return { createdMemories, warnings };
  }

  for (const toolCall of toolCalls) {
    if (toolCall.name !== 'create_memory') {
      continue; // Skip non-memory tool calls
    }

    try {
      // Validate and sanitize input
      const validation = validateMemoryToolInput(toolCall.arguments);

      if (!validation.valid) {
        warnings.push(`Memory tool call ${toolCall.id}: ${validation.error}`);
        continue;
      }

      const memoryInput = validation.sanitized!;

      // Add warning if content was truncated
      if (validation.error) {
        warnings.push(`Memory tool call ${toolCall.id}: ${validation.error}`);
      }

      // Create memory document
      const memoryId = uuidv4();
      const now = Date.now();

      const memory = {
        id: memoryId,
        userId: context.userId,
        content: memoryInput.content,
        type: memoryInput.type,
        confidence: memoryInput.confidence,
        tags: memoryInput.tags || [],
        metadata: {
          createdVia: 'tool_call',
          toolCallId: toolCall.id,
          ...(memoryInput.context && { context: memoryInput.context }),
        },
        source: {
          conversationId: context.conversationId,
          messageId: null,
          timestamp: now,
        },
        relatedMemories: null,
        createdAt: now,
        updatedAt: now,
        lastAccessedAt: null,
        accessCount: 0,
      };

      // Save to Firestore
      await context.db
        .collection('users')
        .doc(context.userId)
        .collection('memories')
        .doc(memoryId)
        .set(memory);

      createdMemories.push(memory);

      console.log(
        `[Orchestrator] ✅ Created ${memoryInput.type} memory via tool: "${memoryInput.content.substring(0, 60)}..."`
      );
    } catch (error: any) {
      const errorMsg = `Memory creation failed for tool call ${toolCall.id}: ${error.message}`;
      warnings.push(errorMsg);
      console.error(`[Orchestrator] ❌ ${errorMsg}`);
    }
  }

  return { createdMemories, warnings };
}

/**
 * INTEGRATION EXAMPLE
 *
 * Replace this section in your apiOrchestrate endpoint:
 *
 * // OLD CODE (DELETE THIS):
 * const learnings = extractLearnings(response.content);
 * if (saveMemories && learnings.length > 0) {
 *   for (const learning of learnings) {
 *     // ... create memory from learning
 *   }
 * }
 *
 * // NEW CODE (USE THIS):
 * const { createdMemories, warnings: memoryWarnings } = await processMemoryToolCalls(
 *   response.toolCalls || [],
 *   {
 *     userId: uid,
 *     conversationId,
 *     db: getDb(),
 *   }
 * );
 *
 * // Add memory warnings to main warnings array
 * warnings.push(...memoryWarnings);
 */

/**
 * Helper: Generate system prompt with memory tool instructions
 */
export function generateMemoryAwareSystemPrompt(
  basePrompt: string,
  memoryInjection: string,
  enableMemoryTool: boolean
): string {
  let systemPrompt = basePrompt;

  // Add memory context if available
  if (memoryInjection) {
    systemPrompt += `\n\n${memoryInjection}`;
  }

  // Add memory tool usage instructions
  if (enableMemoryTool) {
    systemPrompt += `\n\n## Memory System

You have access to a long-term memory system via the create_memory tool.

**When to create memories:**
- User shares important preferences, facts about themselves, or project details → allocentric memory
- You discover patterns in how to help this user effectively → egoic memory
- Limit to 1-3 memories per conversation (be selective!)

**Best practices:**
- Use clear, concise language (50-500 chars ideal)
- Set confidence appropriately (0.3=hypothesis, 0.6=likely, 0.9=certain)
- Add searchable tags
- Don't duplicate existing memories shown above

**Example:**
When user says "I prefer Python 3.12 for data science", create:
{
  "content": "User prefers Python 3.12 for data science projects",
  "type": "allocentric",
  "confidence": 0.95,
  "tags": ["python", "data-science", "preferences"]
}`;
  }

  return systemPrompt;
}

/**
 * Update your provider request to enable memory tool
 *
 * Example for apiOrchestrate:
 */
export function buildProviderRequestWithMemoryTool(
  messages: any[],
  options: {
    model?: string;
    temperature?: number;
    maxTokens?: number;
    saveMemories?: boolean;
  }
) {
  return {
    messages,
    model: options.model,
    temperature: options.temperature,
    maxTokens: options.maxTokens,
    enableMemoryTool: options.saveMemories !== false, // Enable by default unless explicitly disabled
  };
}
