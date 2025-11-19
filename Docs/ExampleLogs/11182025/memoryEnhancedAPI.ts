/**
 * Memory Enhanced API - Phase 1
 *
 * Advanced memory operations including:
 * - Batch memory creation with validation and compaction
 * - Memory parsing from LLM responses
 * - Memory compaction via Haiku subagent
 * - Context-aware memory retrieval with scoring
 *
 * These endpoints complement the base memory CRUD in memoryAugmentedAPI.ts
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import cors from 'cors';
import { withApiKeyAndCors } from '../utils/apiKeyMiddleware';
import {
    parseMemoriesFromText,
    ParsedMemory,
    formatMemoryForStorage,
} from '../utils/memoryParser';
import {
    retrieveRelevantMemories,
    formatMemoriesForInjection,
    StoredMemory,
    calculateMemoryStats,
} from '../utils/memoryScoring';
import { AnthropicProvider } from '../providers/anthropicProvider';

// CORS configuration
const corsHandler = cors({
    origin: [
        'http://localhost:3000',
        'http://localhost:5173',
        'https://axon.neurx.org',
        'https://axon-neurx-chat.web.app',
        'https://axon-neurx-chat.firebaseapp.com'
    ],
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
});

// Firebase services
const getDb = () => admin.firestore();
const getAuth = () => admin.auth();

// Anthropic provider for memory compaction
const anthropicProvider = new AnthropicProvider();

/**
 * Verify Firebase token
 */
async function verifyToken(req: functions.https.Request): Promise<{ uid: string; claims: any }> {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Missing or invalid Authorization header'
        );
    }

    const token = authHeader.substring(7);

    try {
        const decodedToken = await getAuth().verifyIdToken(token);
        return {
            uid: decodedToken.uid,
            claims: decodedToken,
        };
    } catch (error) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Invalid or expired token'
        );
    }
}

/**
 * Generate memory ID
 */
function generateMemoryId(): string {
    return `mem_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

/**
 * Compact a single memory using Haiku subagent
 */
async function compactMemory(memory: any, userId: string): Promise<{
    contentCompact: string;
    contentSummary: string;
    contextCompact: string;
    evidenceCompact: string;
    compressionRatio: number;
}> {
    try {
        // Build prompt for Haiku to compact memory
        const prompt = `You are a memory compression expert. Compress this memory while preserving all critical information.

Original Memory:
Content: ${memory.content}
Context: ${memory.context}
Evidence: ${memory.evidence}
Tags: ${memory.tags.join(', ')}

Provide a compressed version as JSON with these fields:
{
  "contentCompact": "1-2 sentence compressed version",
  "contentSummary": "Single line summary with emoji",
  "contextCompact": "Max 80 chars of context",
  "evidenceCompact": "Key supporting points (max 150 chars)"
}`;

        // Call Haiku via Anthropic provider
        const response = await anthropicProvider.invoke(
            {
                messages: [
                    {
                        role: 'user',
                        content: prompt,
                    },
                ],
                model: 'claude-haiku-4-5-20251001',
                maxTokens: 500,
            },
            userId
        );

        // Parse JSON response
        const jsonMatch = response.content.match(/\{[\s\S]*\}/);
        if (!jsonMatch) {
            throw new Error('Could not extract JSON from response');
        }

        const compressed = JSON.parse(jsonMatch[0]);

        // Calculate compression ratio
        const originalSize = memory.content.length + memory.context.length + memory.evidence.length;
        const compressedSize = (compressed.contentCompact?.length || 0)
            + (compressed.contextCompact?.length || 0)
            + (compressed.evidenceCompact?.length || 0);
        const compressionRatio = originalSize > 0 ? compressedSize / originalSize : 1;

        return {
            contentCompact: compressed.contentCompact || '',
            contentSummary: compressed.contentSummary || '',
            contextCompact: compressed.contextCompact || '',
            evidenceCompact: compressed.evidenceCompact || '',
            compressionRatio,
        };
    } catch (error) {
        // Fallback: simple rule-based compaction
        console.warn('Memory compaction via Haiku failed, using fallback:', error);

        return {
            contentCompact: memory.content.substring(0, 150),
            contentSummary: `💡 ${memory.content.substring(0, 60)}...`,
            contextCompact: memory.context.substring(0, 80),
            evidenceCompact: memory.evidence.substring(0, 150),
            compressionRatio: 0.5,
        };
    }
}

/**
 * Function: apiParseMemories
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiParseMemories
 * Parse memory tags from LLM response
 *
 * Request body:
 * {
 *   "text": "Raw LLM response with <create_memory> tags",
 *   "projectId": "optional-project-id",
 *   "conversationId": "optional-conversation-id"
 * }
 */
export const apiParseMemories = functions.https.onRequest(async (req, res) => {
    if (req.method === 'OPTIONS') {
        corsHandler(req, res, () => res.status(204).send(''));
        return;
    }

    corsHandler(req, res, async () => {
        try {
            await verifyToken(req);

            if (req.method !== 'POST') {
                return res.status(405).json({ error: 'Method not allowed' });
            }

            const { text, projectId, conversationId } = req.body;

            if (!text || typeof text !== 'string') {
                return res.status(400).json({ error: 'Text is required' });
            }

            // Parse memories from text
            const result = parseMemoriesFromText(text, { projectId, conversationId });

            return res.status(200).json({
                memories: result.memories,
                count: result.memories.length,
                parseErrors: result.parseErrors,
                hasErrors: result.parseErrors.length > 0,
            });
        } catch (error: any) {
            console.error('Parse Memories Error:', error);

            if (error instanceof functions.https.HttpsError) {
                return res.status(401).json({ error: error.message });
            }

            return res.status(500).json({
                error: error?.message || 'Internal server error'
            });
        }
    });
});

/**
 * Function: apiBatchCreateMemories
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiBatchCreateMemories
 * Create multiple memories in a batch with validation and compaction
 *
 * Request body:
 * {
 *   "memories": [
 *     {
 *       "type": "allocentric|egoic",
 *       "content": "...",
 *       "confidence": 0.8,
 *       "context": "...",
 *       "evidence": "...",
 *       "tags": ["tag1", "tag2"],
 *       "projectId": "optional"
 *     }
 *   ],
 *   "shouldCompact": true  // Should memories be compressed?
 * }
 */
export const apiBatchCreateMemories = functions.https.onRequest(async (req, res) => {
    if (req.method === 'OPTIONS') {
        corsHandler(req, res, () => res.status(204).send(''));
        return;
    }

    corsHandler(req, res, async () => {
        try {
            const { uid } = await verifyToken(req);

            if (req.method !== 'POST') {
                return res.status(405).json({ error: 'Method not allowed' });
            }

            const { memories: inputMemories, shouldCompact = true } = req.body;

            if (!Array.isArray(inputMemories) || inputMemories.length === 0) {
                return res.status(400).json({ error: 'Memories array is required and must be non-empty' });
            }

            if (inputMemories.length > 100) {
                return res.status(400).json({ error: 'Maximum 100 memories per batch' });
            }

            const createdMemories = [];
            const errors: Array<{ index: number; error: string }> = [];
            const now = Date.now();

            // Process each memory
            for (let i = 0; i < inputMemories.length; i++) {
                const inputMemory = inputMemories[i];

                try {
                    // Basic validation
                    if (!inputMemory.type || !['allocentric', 'egoic'].includes(inputMemory.type)) {
                        throw new Error(`Invalid type: ${inputMemory.type}`);
                    }

                    if (!inputMemory.content || typeof inputMemory.content !== 'string') {
                        throw new Error('Content is required');
                    }

                    if (typeof inputMemory.confidence !== 'number' || inputMemory.confidence < 0 || inputMemory.confidence > 1) {
                        throw new Error('Confidence must be between 0 and 1');
                    }

                    if (!Array.isArray(inputMemory.tags)) {
                        throw new Error('Tags must be an array');
                    }

                    // Generate ID
                    const memoryId = generateMemoryId();

                    // Format for storage
                    const memory = formatMemoryForStorage(inputMemory, memoryId, now);

                    // Optionally compact
                    if (shouldCompact) {
                        try {
                            const compact = await compactMemory(inputMemory, uid);
                            memory.contentCompact = compact.contentCompact;
                            memory.contentSummary = compact.contentSummary;
                        } catch (compactError) {
                            console.warn(`Could not compact memory ${memoryId}:`, compactError);
                            // Continue without compaction
                        }
                    }

                    // Save to Firestore
                    await getDb()
                        .collection('users')
                        .doc(uid)
                        .collection('memories')
                        .doc(memoryId)
                        .set(memory);

                    createdMemories.push(memory);
                } catch (error) {
                    errors.push({
                        index: i,
                        error: error instanceof Error ? error.message : String(error),
                    });
                }
            }

            return res.status(201).json({
                created: createdMemories.length,
                failed: errors.length,
                memories: createdMemories,
                errors: errors.length > 0 ? errors : undefined,
                summary: {
                    total: inputMemories.length,
                    succeeded: createdMemories.length,
                    failed: errors.length,
                },
            });
        } catch (error: any) {
            console.error('Batch Create Memories Error:', error);

            if (error instanceof functions.https.HttpsError) {
                return res.status(401).json({ error: error.message });
            }

            return res.status(500).json({
                error: error?.message || 'Internal server error'
            });
        }
    });
});

/**
 * Function: apiRetrieveMemories
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiRetrieveMemories
 * Context-aware memory retrieval with relevance scoring
 *
 * Query parameters:
 * - query: Search query for memory retrieval
 * - type: Filter by type (allocentric, egoic, or all)
 * - projectId: Filter by project
 * - maxMemories: Max memories to return (default 20, max 100)
 * - minConfidence: Min confidence threshold (0-1, default 0.3)
 * - format: Return format (full or compact, default full)
 */
export const apiRetrieveMemories = functions.https.onRequest(async (req, res) => {
    if (req.method === 'OPTIONS') {
        corsHandler(req, res, () => res.status(204).send(''));
        return;
    }

    corsHandler(req, res, async () => {
        try {
            const { uid } = await verifyToken(req);

            if (req.method !== 'GET') {
                return res.status(405).json({ error: 'Method not allowed' });
            }

            // Parse query parameters
            const query = (req.query.query as string) || '';
            const type = (req.query.type as string) || 'all';
            const projectId = req.query.projectId as string | undefined;
            const maxMemories = Math.min(parseInt(req.query.maxMemories as string) || 20, 100);
            const minConfidence = parseFloat(req.query.minConfidence as string) || 0.3;
            const format = (req.query.format as string) || 'full';

            // Fetch all user memories
            const snapshot = await getDb()
                .collection('users')
                .doc(uid)
                .collection('memories')
                .get();

            const allMemories: StoredMemory[] = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
            } as StoredMemory));

            // Retrieve relevant memories with scoring
            const relevant = retrieveRelevantMemories(query, allMemories, {
                type: type as 'all' | 'allocentric' | 'egoic',
                maxMemories,
                minConfidence,
                projectId,
                excludeArchived: true,
            });

            // Format for injection if requested
            const injection = format === 'injection'
                ? formatMemoriesForInjection(relevant)
                : '';

            // Calculate stats
            const stats = calculateMemoryStats(relevant);

            return res.status(200).json({
                memories: format === 'compact'
                    ? relevant.map(m => ({
                        id: m.id,
                        type: m.type,
                        content: m.contentCompact || m.content,
                        confidence: m.confidence,
                        tags: m.tags,
                    }))
                    : relevant,
                injection: format === 'injection' ? injection : undefined,
                statistics: stats,
                metadata: {
                    query,
                    type,
                    projectId: projectId || null,
                    maxMemories,
                    minConfidence,
                    format,
                },
            });
        } catch (error: any) {
            console.error('Retrieve Memories Error:', error);

            if (error instanceof functions.https.HttpsError) {
                return res.status(401).json({ error: error.message });
            }

            return res.status(500).json({
                error: error?.message || 'Internal server error'
            });
        }
    });
});

/**
 * Function: apiCompactMemory
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiCompactMemory
 * Compact a specific memory using Haiku subagent (memoryId passed as path parameter)
 */
export const apiCompactMemory = functions.https.onRequest(async (req, res) => {
    if (req.method === 'OPTIONS') {
        corsHandler(req, res, () => res.status(204).send(''));
        return;
    }

    corsHandler(req, res, async () => {
        try {
            const { uid } = await verifyToken(req);

            if (req.method !== 'POST') {
                return res.status(405).json({ error: 'Method not allowed' });
            }

            // Extract memory ID from path
            const pathParts = req.path.split('/');
            const memoryId = pathParts[pathParts.length - 2]; // before /compact

            if (!memoryId) {
                return res.status(400).json({ error: 'Memory ID is required' });
            }

            // Fetch memory
            const doc = await getDb()
                .collection('users')
                .doc(uid)
                .collection('memories')
                .doc(memoryId)
                .get();

            if (!doc.exists) {
                return res.status(404).json({ error: 'Memory not found' });
            }

            const memory = doc.data();

            // Compact the memory
            const compact = await compactMemory(memory, uid);

            // Update memory with compact fields
            await getDb()
                .collection('users')
                .doc(uid)
                .collection('memories')
                .doc(memoryId)
                .update({
                    contentCompact: compact.contentCompact,
                    contentSummary: compact.contentSummary,
                    contextCompact: compact.contextCompact,
                    evidenceCompact: compact.evidenceCompact,
                    updatedAt: Date.now(),
                });

            return res.status(200).json({
                id: memoryId,
                originalSize: memory.content.length,
                compactedSize: compact.contentCompact.length,
                compressionRatio: compact.compressionRatio,
                compact,
            });
        } catch (error: any) {
            console.error('Compact Memory Error:', error);

            if (error instanceof functions.https.HttpsError) {
                return res.status(401).json({ error: error.message });
            }

            return res.status(500).json({
                error: error?.message || 'Internal server error'
            });
        }
    });
});
