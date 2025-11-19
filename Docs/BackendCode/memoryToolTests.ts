/**
 * Memory Tool Test Suite
 *
 * Test cases for validating the tool-based memory creation system.
 */

import { validateMemoryToolInput, MemoryToolInput } from './memoryTool';
import { processMemoryToolCalls } from './orchestratorMemoryIntegration';

/**
 * Unit Tests for validateMemoryToolInput
 */

describe('validateMemoryToolInput', () => {
  test('Valid allocentric memory', () => {
    const input = {
      content: 'User prefers Python 3.12 for data science projects',
      type: 'allocentric',
      confidence: 0.95,
      tags: ['python', 'data-science', 'preferences'],
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(true);
    expect(result.sanitized?.content).toBe(input.content);
    expect(result.sanitized?.type).toBe('allocentric');
    expect(result.sanitized?.confidence).toBe(0.95);
    expect(result.sanitized?.tags).toEqual(['python', 'data-science', 'preferences']);
  });

  test('Valid egoic memory with context', () => {
    const input = {
      content: 'User responds well to visual diagrams before text explanations',
      type: 'egoic',
      confidence: 0.7,
      tags: ['learning-style', 'communication'],
      context: 'Noticed from multiple exchanges about complex topics',
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(true);
    expect(result.sanitized?.context).toBe(input.context);
  });

  test('Truncates overly long content', () => {
    const longContent = 'A'.repeat(2500);
    const input = {
      content: longContent,
      type: 'allocentric',
      confidence: 0.8,
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(true);
    expect(result.sanitized?.content.length).toBe(2000);
    expect(result.sanitized?.content).toEndWith('...');
    expect(result.error).toBeDefined();
  });

  test('Rejects too short content', () => {
    const input = {
      content: 'Short',
      type: 'allocentric',
      confidence: 0.8,
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(false);
    expect(result.error).toContain('too short');
  });

  test('Rejects invalid type', () => {
    const input = {
      content: 'This is a valid length memory content',
      type: 'invalid_type',
      confidence: 0.8,
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(false);
    expect(result.error).toContain('Invalid type');
  });

  test('Rejects invalid confidence', () => {
    const input = {
      content: 'This is a valid length memory content',
      type: 'allocentric',
      confidence: 1.5, // Invalid: > 1
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(false);
    expect(result.error).toContain('Invalid confidence');
  });

  test('Sanitizes tags', () => {
    const input = {
      content: 'This is a valid length memory content',
      type: 'allocentric',
      confidence: 0.8,
      tags: [
        '  Python  ', // Should trim and lowercase
        'MACHINE-LEARNING', // Should lowercase
        'A'.repeat(100), // Should truncate to 50 chars
        '', // Should remove
        'valid-tag',
        ...Array(15).fill('extra'), // Should limit to 10
      ],
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(true);
    expect(result.sanitized?.tags).toHaveLength(10);
    expect(result.sanitized?.tags).toContain('python');
    expect(result.sanitized?.tags).toContain('machine-learning');
    expect(result.sanitized?.tags).toContain('valid-tag');
    expect(result.sanitized?.tags?.[2].length).toBeLessThanOrEqual(50);
  });

  test('Truncates long context', () => {
    const input = {
      content: 'This is a valid length memory content',
      type: 'egoic',
      confidence: 0.7,
      context: 'C'.repeat(1000), // Should truncate to 500
    };

    const result = validateMemoryToolInput(input);
    expect(result.valid).toBe(true);
    expect(result.sanitized?.context?.length).toBe(500);
  });
});

/**
 * Integration Test Scenarios
 */

export const TEST_SCENARIOS = [
  {
    name: 'User shares programming preference',
    userMessage: "I really prefer using Python 3.12 for all my data science projects. I find it's the most stable version.",
    expectedToolCalls: [
      {
        name: 'create_memory',
        arguments: {
          content: expect.stringContaining('Python 3.12'),
          type: 'allocentric',
          confidence: expect.any(Number),
          tags: expect.arrayContaining(['python']),
        },
      },
    ],
  },

  {
    name: 'User describes project architecture',
    userMessage: `I'm building a microservices architecture with:
- React Native frontend (TypeScript)
- Node.js backend (Express)
- PostgreSQL database
- Docker for containerization
- Jest for testing`,
    expectedToolCalls: [
      {
        name: 'create_memory',
        arguments: {
          content: expect.stringContaining('microservices'),
          type: 'allocentric',
          tags: expect.arrayContaining(['architecture']),
        },
      },
    ],
    expectedMemoryCount: { min: 1, max: 3 }, // Could create 1-3 memories
  },

  {
    name: 'AI discovers user learning pattern',
    context: 'After 3 exchanges where user asked for examples first',
    expectedToolCalls: [
      {
        name: 'create_memory',
        arguments: {
          type: 'egoic',
          content: expect.stringContaining('example'),
          confidence: expect.numberBetween(0.6, 0.8),
        },
      },
    ],
  },

  {
    name: 'Long detailed explanation from user',
    userMessage: 'A'.repeat(1500) + ' This is my detailed project explanation.',
    expectedBehavior: 'AI should summarize or create multiple focused memories, not one 1500-char memory',
    validate: (memories: any[]) => {
      // Each memory should be under 800 chars ideally
      for (const memory of memories) {
        expect(memory.content.length).toBeLessThan(800);
      }
    },
  },

  {
    name: 'Multiple learnings in one message',
    userMessage: "I'm Tom, I work as a software engineer at Google. I specialize in backend systems and prefer Go over Python. I'm currently learning Rust.",
    expectedToolCalls: [
      { arguments: { content: expect.stringContaining('Tom') } },
      { arguments: { content: expect.stringContaining('Google') } },
      { arguments: { content: expect.stringContaining('Go') } },
      { arguments: { content: expect.stringContaining('Rust') } },
    ],
    expectedMemoryCount: { min: 2, max: 4 },
  },

  {
    name: 'Casual conversation (no memories)',
    userMessage: 'Hey, how are you doing today?',
    expectedToolCalls: [],
    expectedMemoryCount: { min: 0, max: 0 },
  },
];

/**
 * Helper matchers for tests
 */

expect.extend({
  numberBetween(received: number, min: number, max: number) {
    const pass = received >= min && received <= max;
    return {
      pass,
      message: () =>
        pass
          ? `Expected ${received} not to be between ${min} and ${max}`
          : `Expected ${received} to be between ${min} and ${max}`,
    };
  },
});

/**
 * End-to-End Test Example
 *
 * This shows how to test the full flow from AI response to memory creation
 */

async function testMemoryCreationE2E() {
  // Mock Firestore
  const mockDb = {
    collection: jest.fn().mockReturnThis(),
    doc: jest.fn().mockReturnThis(),
    set: jest.fn().mockResolvedValue(undefined),
  };

  // Simulate AI response with tool calls
  const toolCalls = [
    {
      id: 'call_123',
      name: 'create_memory',
      arguments: {
        content: 'User prefers Python 3.12 for data science work',
        type: 'allocentric',
        confidence: 0.95,
        tags: ['python', 'data-science', 'preferences'],
      },
    },
    {
      id: 'call_124',
      name: 'create_memory',
      arguments: {
        content: 'User responds well to code examples before explanations',
        type: 'egoic',
        confidence: 0.7,
        tags: ['learning-style'],
        context: 'Observed from multiple exchanges',
      },
    },
  ];

  // Process tool calls
  const result = await processMemoryToolCalls(toolCalls, {
    userId: 'user123',
    conversationId: 'conv456',
    db: mockDb as any,
  });

  // Assertions
  expect(result.createdMemories).toHaveLength(2);
  expect(result.createdMemories[0].type).toBe('allocentric');
  expect(result.createdMemories[1].type).toBe('egoic');
  expect(result.warnings).toHaveLength(0);

  // Verify Firestore was called
  expect(mockDb.set).toHaveBeenCalledTimes(2);
}

/**
 * Performance Test
 */

async function testMemoryCreationPerformance() {
  const start = Date.now();

  // Create 100 memories
  const toolCalls = Array(100)
    .fill(null)
    .map((_, i) => ({
      id: `call_${i}`,
      name: 'create_memory',
      arguments: {
        content: `Test memory ${i} with enough content to pass validation`,
        type: i % 2 === 0 ? 'allocentric' : 'egoic',
        confidence: 0.8,
        tags: [`tag${i}`],
      },
    }));

  const mockDb = {
    collection: jest.fn().mockReturnThis(),
    doc: jest.fn().mockReturnThis(),
    set: jest.fn().mockResolvedValue(undefined),
  };

  await processMemoryToolCalls(toolCalls, {
    userId: 'user123',
    conversationId: 'conv456',
    db: mockDb as any,
  });

  const duration = Date.now() - start;

  console.log(`Created 100 memories in ${duration}ms`);
  expect(duration).toBeLessThan(5000); // Should complete in under 5 seconds
}

/**
 * Manual Testing Guide
 *
 * To test in your deployed environment:
 *
 * 1. Send a message: "I prefer Python 3.12 for data science"
 * 2. Check response.toolCalls in orchestrator logs
 * 3. Verify memory was created in Firestore
 * 4. Query /apiGetMemories to see it appears
 * 5. Send another message about Python - verify memory is retrieved
 */

export const MANUAL_TEST_PROMPTS = [
  {
    prompt: "I prefer Python 3.12 for all my data science projects",
    expectedMemory: {
      type: 'allocentric',
      tags: ['python', 'data-science'],
    },
  },
  {
    prompt: "I'm working on a React Native app with TypeScript and Jest for testing",
    expectedMemory: {
      type: 'allocentric',
      tags: ['react-native', 'typescript', 'jest'],
    },
    expectedCount: { min: 1, max: 3 },
  },
  {
    prompt: "Just wanted to say the code examples you provide are really helpful!",
    expectedMemory: {
      type: 'egoic',
      content: 'code examples',
    },
  },
];
