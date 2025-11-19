/**
 * Memory-Augmented Cloud Functions API
 *
 * Provides Cloud Function HTTP endpoints for remote clients to:
 * - Query the AI agent with memory context
 * - Manage memories (create, retrieve, search, delete)
 * - Get memory analytics and insights
 *
 * All endpoints require Firebase Authentication via Bearer token
 * in the Authorization header.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import cors from 'cors';
import { withApiKeyAndCors } from '../utils/apiKeyMiddleware';
import { OpenAIProvider } from '../providers/openaiProvider';
import { AnthropicProvider } from '../providers/anthropicProvider';
import { GeminiProvider } from '../providers/geminiProvider';
import { ProviderRequest, ProviderResponse } from '../providers/types';

// CORS configuration for API endpoints
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

// Initialize providers
const providers = {
    openai: new OpenAIProvider(),
    anthropic: new AnthropicProvider(),
    gemini: new GeminiProvider(),
};

// Firebase Admin services - initialized lazily to avoid circular dependency
// (admin.initializeApp() is called in index.ts before these are used)
const getDb = () => admin.firestore();
const getAuth = () => admin.auth();

/**
 * Model configuration mirrors src/config/models.ts
 */
const MODEL_CATALOG = {
    anthropic: [
        {
            id: 'claude-sonnet-4-5-20250929',
            name: 'Claude 4.5 Sonnet (Latest)',
            description: 'Most capable model, best for complex tasks',
            contextWindow: 200000,
        },
        {
            id: 'claude-sonnet-4-5-20250929:1m',
            name: 'Claude 4.5 Sonnet 1M Context',
            description: 'Same as Sonnet with extended context',
            contextWindow: 1000000,
        },
        {
            id: 'claude-haiku-4-5-20251001',
            name: 'Claude 4.5 Haiku',
            description: 'Fast and compact, good for simple tasks',
            contextWindow: 200000,
        },
    ],
    gemini: [
        {
            id: 'gemini-2.5-pro',
            name: 'Gemini 2.5 Pro',
            description: 'Most capable Gemini model',
            contextWindow: 1000000,
        },
        {
            id: 'gemini-2.5-flash',
            name: 'Gemini 2.5 Flash',
            description: 'Fast and efficient',
            contextWindow: 1000000,
        },
    ],
    openai: [
        {
            id: 'gpt-4o',
            name: 'GPT-4o',
            description: 'Latest GPT-4 optimized version',
            contextWindow: 128000,
        },
        {
            id: 'gpt-4o-mini',
            name: 'GPT-4o Mini',
            description: 'Fast GPT-4o variant',
            contextWindow: 128000,
        },
        {
            id: 'gpt-5-2025-08-07',
            name: 'GPT-5 (Latest)',
            description: 'Most capable model available',
            contextWindow: 128000,
        },
    ],
};

/**
 * Type definitions for API requests/responses
 */

export interface ChatRequest {
    /** AI provider to use (openai, anthropic, gemini) */
    provider: string;
    /** Messages array for the conversation */
    messages: Array<{
        role: 'user' | 'assistant' | 'system';
        content: string;
    }>;
    /** Model ID to use for this request (overrides default) */
    model?: string;
    /** Whether to auto-inject relevant memories into system prompt */
    includeMemories?: boolean;
    /** Project ID to filter memories by (optional) */
    projectId?: string;
    /** Maximum memories to include (default: 20) */
    maxMemories?: number;
    /** Minimum confidence threshold for memories (default: 0.3) */
    minConfidenceThreshold?: number;
    /** Model-specific parameters */
    temperature?: number;
    maxTokens?: number;
}

export interface ChatResponse {
    /** Generated response content */
    content: string;
    /** Metadata about the response */
    metadata: {
        model: string;
        provider: string;
        tokensUsed?: number;
        memoryContext?: {
            memoriesIncluded: number;
            allocentricMemories: number;
            egoicMemories: number;
            averageConfidence: number;
        };
        timestamp: number;
    };
}

export interface MemoryCreateRequest {
    type: 'allocentric' | 'egoic';
    content: string;
    confidence: number;
    context: string;
    evidence: string;
    tags: string[];
    projectId?: string;
    conversationId?: string;
}

export interface MemoryResponse {
    id: string;
    type: string;
    content: string;
    contentCompact?: string;
    confidence: number;
    tags: string[];
    context: string;
    evidence: string;
    createdAt: number;
    updatedAt: number;
    projectId?: string;
    archived?: boolean;
}

export interface MemorySearchQuery {
    query?: string;
    type?: 'allocentric' | 'egoic';
    tags?: string[];
    minConfidence?: number;
    projectId?: string;
    limit?: number;
    offset?: number;
}

export interface MemoryAnalyticsResponse {
    totalMemories: number;
    allocentricCount: number;
    egoicCount: number;
    averageConfidence: number;
    confidenceDistribution: {
        hypothesis: number;      // 0-0.33
        uncertain: number;       // 0.33-0.66
        established: number;     // 0.66-1.0
    };
    topTags: Array<{ tag: string; count: number }>;
    memorysByProject: Record<string, number>;
    recentMemories: MemoryResponse[];
}

/**
 * Verify Firebase token from Authorization header
 */
async function verifyToken(req: functions.https.Request): Promise<{ uid: string; claims: any }> {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        throw new functions.https.HttpsError(
            'unauthenticated',
            'Missing or invalid Authorization header. Use: Authorization: Bearer <token>'
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
 * Retrieve user's memories from Firestore
 */
async function getUserMemories(userId: string): Promise<any[]> {
    try {
        const snapshot = await getDb().collection('users').doc(userId).collection('memories').get();
        return snapshot.docs.map(doc => ({
            id: doc.id,
            ...doc.data(),
        }));
    } catch (error) {
        console.error('Error retrieving memories:', error);
        return [];
    }
}

/**
 * Format memories for system prompt injection
 */
function formatMemoriesForInjection(memories: any[]): string {
    if (memories.length === 0) return '';

    const allocentric = memories.filter(m => m.type === 'allocentric');
    const egoic = memories.filter(m => m.type === 'egoic');

    let output = '\n## Relevant Memories\n\n';

    if (allocentric.length > 0) {
        output += '### About the User\n';
        allocentric.forEach((m, idx) => {
            const content = m.contentCompact || m.content;
            output += `${idx + 1}. ${content} (confidence: ${(m.confidence * 100).toFixed(0)}%)\n`;
            if (m.contextCompact || m.context) {
                output += `   Context: ${m.contextCompact || m.context}\n`;
            }
        });
        output += '\n';
    }

    if (egoic.length > 0) {
        output += '### Agent Learnings\n';
        egoic.forEach((m, idx) => {
            const content = m.contentCompact || m.content;
            output += `${idx + 1}. ${content} (confidence: ${(m.confidence * 100).toFixed(0)}%)\n`;
            if (m.contextCompact || m.context) {
                output += `   Context: ${m.contextCompact || m.context}\n`;
            }
        });
        output += '\n';
    }

    return output;
}

/**
 * Filter and score memories by relevance
 */
function retrieveRelevantMemories(
    query: string,
    memories: any[],
    options: {
        type?: 'all' | 'allocentric' | 'egoic';
        maxMemories?: number;
        minConfidence?: number;
        projectId?: string;
    } = {}
): any[] {
    const {
        type = 'all',
        maxMemories = 20,
        minConfidence = 0.3,
        projectId,
    } = options;

    // Filter by criteria
    let filtered = memories.filter(m => {
        if (m.archived) return false;
        if (type !== 'all' && m.type !== type) return false;
        if (m.confidence < minConfidence) return false;
        if (projectId && m.projectId && m.projectId !== projectId) return false;
        return true;
    });

    // Score relevance
    const queryLower = query.toLowerCase();
    const words = queryLower.split(/\s+/).filter(w => w.length > 2);

    const scored = filtered.map(memory => {
        let score = 0;

        if (words.length > 0) {
            // Content match (50%)
            const contentLower = memory.content.toLowerCase();
            const contentMatches = words.filter(w => contentLower.includes(w)).length;
            score += (contentMatches / words.length) * 0.5;

            // Tags match (30%)
            const tagMatches = words.filter(w =>
                memory.tags.some(t => t.toLowerCase().includes(w) || w.includes(t.toLowerCase()))
            ).length;
            score += (tagMatches / words.length) * 0.3;

            // Context/evidence match (20%)
            const contextLower = (memory.context || '').toLowerCase();
            const evidenceLower = (memory.evidence || '').toLowerCase();
            const contextMatches = words.filter(
                w => contextLower.includes(w) || evidenceLower.includes(w)
            ).length;
            score += (contextMatches / words.length) * 0.2;

            score = Math.min(1, score);
        } else {
            score = memory.confidence * 0.7 + 0.3;
        }

        // Blend with confidence
        score = score * 0.8 + memory.confidence * 0.2;

        return { memory, relevance: score };
    });

    // Sort by relevance, then confidence, then recency
    scored.sort((a, b) => {
        if (a.relevance !== b.relevance) return b.relevance - a.relevance;
        if (a.memory.confidence !== b.memory.confidence) {
            return b.memory.confidence - a.memory.confidence;
        }
        return new Date(b.memory.updatedAt).getTime() - new Date(a.memory.updatedAt).getTime();
    });

    return scored.slice(0, maxMemories).map(s => s.memory);
}

/**
 * Function: apiGetModels
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiGetModels
 * Get available models for each provider
 *
 * Returns a catalog of all available models organized by provider
 */
export const apiGetModels = functions.https.onRequest(async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        corsHandler(req, res, () => {
            res.status(204).send('');
        });
        return;
    }

    corsHandler(req, res, async () => {
        try {
            // Verify authentication
            await verifyToken(req);

            if (req.method !== 'GET') {
                return res.status(405).json({ error: 'Method not allowed' });
            }

            // Get provider from query params (optional, returns all if not specified)
            const provider = req.query.provider as string | undefined;

            if (provider) {
                // Return models for specific provider
                const models = MODEL_CATALOG[provider as keyof typeof MODEL_CATALOG];
                if (!models) {
                    return res.status(400).json({
                        error: `Unknown provider: ${provider}. Valid providers: anthropic, gemini, openai`
                    });
                }
                return res.status(200).json({
                    provider,
                    models,
                });
            }

            // Return all models organized by provider
            return res.status(200).json({
                providers: ['anthropic', 'gemini', 'openai'],
                models: MODEL_CATALOG,
            });
        } catch (error: any) {
            console.error('Get Models Error:', error);

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
 * Function: apiChat
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiChat
 * Query the AI agent with optional memory context
 *
 * Request body:
 * {
 *   "provider": "anthropic" | "openai" | "gemini",
 *   "messages": [...],
 *   "includeMemories": true,
 *   "projectId": "optional-project-id",
 *   "model": "claude-3-5-sonnet"
 * }
 */
export const apiChat = functions.https.onRequest(async (req, res) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        corsHandler(req, res, () => {
            res.status(204).send('');
        });
        return;
    }

    corsHandler(req, res, async () => {
        try {
            // Verify authentication
            const { uid } = await verifyToken(req);

            if (req.method !== 'POST') {
                return res.status(405).json({ error: 'Method not allowed' });
            }

            const body = req.body as ChatRequest;

            // Validate request
            if (!body.provider || !['openai', 'anthropic', 'gemini'].includes(body.provider)) {
                return res.status(400).json({ error: 'Invalid provider' });
            }

            if (!body.messages || !Array.isArray(body.messages)) {
                return res.status(400).json({ error: 'Messages array is required' });
            }

            // Prepare system prompt
            let systemPrompt = body.messages[0]?.role === 'system'
                ? body.messages[0].content
                : 'You are a helpful AI assistant.';

            // Retrieve and inject memories if requested
            let memoryContext = null;
            let relevantMemories: any[] = [];

            if (body.includeMemories !== false) {
                const allMemories = await getUserMemories(uid);
                const conversationText = body.messages
                    .filter(m => m.role === 'user')
                    .map(m => m.content)
                    .join(' ');

                relevantMemories = retrieveRelevantMemories(conversationText, allMemories, {
                    type: 'all',
                    maxMemories: body.maxMemories || 20,
                    minConfidence: body.minConfidenceThreshold || 0.3,
                    projectId: body.projectId,
                });

                const memoryInjection = formatMemoriesForInjection(relevantMemories);
                if (memoryInjection) {
                    systemPrompt += memoryInjection;
                }

                memoryContext = {
                    memoriesIncluded: relevantMemories.length,
                    allocentricMemories: relevantMemories.filter(m => m.type === 'allocentric').length,
                    egoicMemories: relevantMemories.filter(m => m.type === 'egoic').length,
                    averageConfidence: relevantMemories.length > 0
                        ? relevantMemories.reduce((sum, m) => sum + m.confidence, 0) / relevantMemories.length
                        : 0,
                };
            }

            // Prepare messages with system prompt
            const messages = [
                { role: 'system' as const, content: systemPrompt },
                ...body.messages.filter(m => m.role !== 'system'),
            ];

            // Invoke provider
            const provider = providers[body.provider as keyof typeof providers];

            // Validate model if provided
            const modelId = body.model;
            if (modelId) {
                const providerModels = MODEL_CATALOG[body.provider as keyof typeof MODEL_CATALOG];
                if (!providerModels || !providerModels.find(m => m.id === modelId)) {
                    return res.status(400).json({
                        error: `Invalid model "${modelId}" for provider "${body.provider}"`
                    });
                }
            }

            const request: ProviderRequest = {
                messages,
                model: body.model,
                temperature: body.temperature,
                maxTokens: body.maxTokens,
            };

            const response: ProviderResponse = await provider.invoke(request, uid);

            // Return response with metadata
            const chatResponse: ChatResponse = {
                content: response.content,
                metadata: {
                    model: response.model || body.model || 'unknown',
                    provider: body.provider,
                    tokensUsed: response.usage?.totalTokens,
                    memoryContext: memoryContext || undefined,
                    timestamp: Date.now(),
                },
            };

            return res.status(200).json(chatResponse);
        } catch (error: any) {
            console.error('API Chat Error:', error);

            if (error instanceof functions.https.HttpsError) {
                return res.status(
                    error.code === 'unauthenticated' ? 401 :
                        error.code === 'permission-denied' ? 403 :
                            error.code === 'invalid-argument' ? 400 : 500
                ).json({ error: error.message });
            }

            return res.status(500).json({
                error: error?.message || 'Internal server error'
            });
        }
    });
});

/**
 * Function: apiCreateMemory
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateMemory
 * Create a new memory
 */
export const apiCreateMemory = functions.https.onRequest(async (req, res) => {
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

            const body = req.body as MemoryCreateRequest;

            // Validate required fields
            if (!body.type || !['allocentric', 'egoic'].includes(body.type)) {
                return res.status(400).json({ error: 'Invalid memory type' });
            }

            if (!body.content || body.content.length === 0) {
                return res.status(400).json({ error: 'Content is required' });
            }

            if (typeof body.confidence !== 'number' || body.confidence < 0 || body.confidence > 1) {
                return res.status(400).json({ error: 'Confidence must be between 0 and 1' });
            }

            if (!Array.isArray(body.tags)) {
                return res.status(400).json({ error: 'Tags must be an array' });
            }

            // Create memory document
            const now = Date.now();
            const memoryId = `mem_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

            const memory = {
                id: memoryId,
                type: body.type,
                content: body.content,
                confidence: body.confidence,
                context: body.context || '',
                evidence: body.evidence || '',
                tags: body.tags || [],
                createdAt: now,
                updatedAt: now,
                projectId: body.projectId || null,
                conversationId: body.conversationId || null,
                archived: false,
            };

            // Save to Firestore
            await getDb().collection('users').doc(uid).collection('memories').doc(memoryId).set(memory);

            // Return created memory
            return res.status(201).json(memory as MemoryResponse);
        } catch (error: any) {
            console.error('Create Memory Error:', error);

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
 * Map legacy memory types to new schema (allocentric/egoic)
 */
function mapMemoryType(type: string): 'allocentric' | 'egoic' {
    // Already using new schema
    if (type === 'allocentric' || type === 'egoic') {
        return type;
    }

    // Map legacy types to allocentric (user-focused)
    if (['fact', 'preference', 'context', 'relationship'].includes(type)) {
        return 'allocentric';
    }

    // Map legacy types to egoic (agent learning)
    if (['question', 'insight', 'learning', 'procedure'].includes(type)) {
        return 'egoic';
    }

    // Default fallback
    console.warn(`Unknown memory type "${type}", defaulting to allocentric`);
    return 'allocentric';
}

/**
 * Function: apiGetMemories
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemories
 * Search and retrieve memories
 *
 * Query parameters:
 * - query: search text
 * - type: 'allocentric' | 'egoic'
 * - tags: comma-separated tags
 * - minConfidence: 0-1
 * - projectId: filter by project
 * - limit: max results (default 50)
 * - offset: pagination offset (default 0)
 */
export const apiGetMemories = functions.https.onRequest(async (req, res) => {
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
            const searchQuery: MemorySearchQuery = {
                query: req.query.query as string | undefined,
                type: req.query.type as 'allocentric' | 'egoic' | undefined,
                minConfidence: req.query.minConfidence
                    ? parseFloat(req.query.minConfidence as string)
                    : undefined,
                projectId: req.query.projectId as string | undefined,
                limit: req.query.limit ? parseInt(req.query.limit as string) : 50,
                offset: req.query.offset ? parseInt(req.query.offset as string) : 0,
            };

            if (req.query.tags && typeof req.query.tags === 'string') {
                searchQuery.tags = req.query.tags.split(',').map(t => t.trim());
            }

            // Get all memories
            const allMemories = await getUserMemories(uid);

            // Filter by criteria
            let filtered = allMemories.filter(m => {
                if (searchQuery.type && m.type !== searchQuery.type) return false;
                if (searchQuery.minConfidence && m.confidence < searchQuery.minConfidence) return false;
                if (searchQuery.projectId && m.projectId !== searchQuery.projectId) return false;

                if (searchQuery.tags && searchQuery.tags.length > 0) {
                    const hasTag = searchQuery.tags.some(t =>
                        m.tags.some(mt => mt.toLowerCase().includes(t.toLowerCase()))
                    );
                    if (!hasTag) return false;
                }

                if (searchQuery.query) {
                    const q = searchQuery.query.toLowerCase();
                    const matches =
                        m.content.toLowerCase().includes(q) ||
                        m.context.toLowerCase().includes(q) ||
                        m.evidence.toLowerCase().includes(q) ||
                        m.tags.some(t => t.toLowerCase().includes(q));
                    if (!matches) return false;
                }

                return true;
            });

            // Sort by recency
            filtered.sort((a, b) =>
                new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime()
            );

            // Paginate
            const total = filtered.length;
            const memories = filtered.slice(
                searchQuery.offset || 0,
                (searchQuery.offset || 0) + (searchQuery.limit || 50)
            );

            return res.status(200).json({
                memories: memories.map(m => ({
                    id: m.id,
                    userId: uid,  // Add userId
                    content: m.content,
                    type: mapMemoryType(m.type),  // Use helper function to map legacy types
                    confidence: m.confidence,
                    tags: m.tags || [],
                    metadata: {},  // Add empty metadata object
                    source: m.conversationId ? {  // Convert conversationId to source object
                        conversationId: String(m.conversationId),
                        messageId: null,
                        timestamp: m.createdAt
                    } : null,
                    relatedMemories: null,  // Add relatedMemories field
                    createdAt: m.createdAt,
                    updatedAt: m.updatedAt,
                    lastAccessedAt: null,  // Add lastAccessedAt field
                    accessCount: 0  // Add accessCount field
                })),
                pagination: {
                    total,
                    limit: searchQuery.limit,
                    offset: searchQuery.offset,
                    hasMore: ((searchQuery.offset || 0) + memories.length) < total,
                },
            });
        } catch (error: any) {
            console.error('Get Memories Error:', error);

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
 * Function: apiGetMemory
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMemory
 * Get a specific memory by ID (memoryId passed as query parameter)
 */
export const apiGetMemory = functions.https.onRequest(async (req, res) => {
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

            // Extract memory ID from path
            const pathParts = req.path.split('/');
            const memoryId = pathParts[pathParts.length - 1];

            if (!memoryId) {
                return res.status(400).json({ error: 'Memory ID is required' });
            }

            // Retrieve memory
            const doc = await getDb()
                .collection('users')
                .doc(uid)
                .collection('memories')
                .doc(memoryId)
                .get();

            if (!doc.exists) {
                return res.status(404).json({ error: 'Memory not found' });
            }

            return res.status(200).json({
                id: doc.id,
                ...doc.data(),
            } as MemoryResponse);
        } catch (error: any) {
            console.error('Get Memory Error:', error);

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
 * Function: apiDeleteMemory
 * Method: DELETE
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiDeleteMemory
 * Delete a memory (archive it) - memoryId passed as query parameter
 */
export const apiDeleteMemory = functions.https.onRequest(async (req, res) => {
    if (req.method === 'OPTIONS') {
        corsHandler(req, res, () => res.status(204).send(''));
        return;
    }

    corsHandler(req, res, async () => {
        try {
            const { uid } = await verifyToken(req);

            if (req.method !== 'DELETE') {
                return res.status(405).json({ error: 'Method not allowed' });
            }

            const pathParts = req.path.split('/');
            const memoryId = pathParts[pathParts.length - 1];

            if (!memoryId) {
                return res.status(400).json({ error: 'Memory ID is required' });
            }

            // Archive memory (soft delete)
            await getDb()
                .collection('users')
                .doc(uid)
                .collection('memories')
                .doc(memoryId)
                .update({ archived: true, updatedAt: Date.now() });

            return res.status(200).json({ success: true });
        } catch (error: any) {
            console.error('Delete Memory Error:', error);

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
 * Function: apiMemoryAnalytics
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiMemoryAnalytics
 * Get memory analytics and statistics
 */
export const apiMemoryAnalytics = functions.https.onRequest(async (req, res) => {
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

            // Get all memories
            const memories = await getUserMemories(uid);

            // Calculate statistics
            const allocentric = memories.filter(m => m.type === 'allocentric');
            const egoic = memories.filter(m => m.type === 'egoic');

            const avgConfidence = memories.length > 0
                ? memories.reduce((sum, m) => sum + m.confidence, 0) / memories.length
                : 0;

            // Confidence distribution
            const hypothesis = memories.filter(m => m.confidence >= 0 && m.confidence <= 0.33).length;
            const uncertain = memories.filter(m => m.confidence > 0.33 && m.confidence <= 0.66).length;
            const established = memories.filter(m => m.confidence > 0.66 && m.confidence <= 1).length;

            // Top tags
            const tagCounts: Record<string, number> = {};
            memories.forEach(m => {
                m.tags.forEach(tag => {
                    tagCounts[tag] = (tagCounts[tag] || 0) + 1;
                });
            });

            const topTags = Object.entries(tagCounts)
                .map(([tag, count]) => ({ tag, count }))
                .sort((a, b) => b.count - a.count)
                .slice(0, 10);

            // Memories by project
            const byProject: Record<string, number> = {};
            memories.forEach(m => {
                if (m.projectId) {
                    byProject[m.projectId] = (byProject[m.projectId] || 0) + 1;
                }
            });

            // Recent memories
            const recent = memories
                .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
                .slice(0, 5);

            const analytics: MemoryAnalyticsResponse = {
                totalMemories: memories.length,
                allocentricCount: allocentric.length,
                egoicCount: egoic.length,
                averageConfidence: avgConfidence,
                confidenceDistribution: {
                    hypothesis,
                    uncertain,
                    established,
                },
                topTags,
                memorysByProject: byProject,
                recentMemories: recent as MemoryResponse[],
            };

            return res.status(200).json(analytics);
        } catch (error: any) {
            console.error('Analytics Error:', error);

            if (error instanceof functions.https.HttpsError) {
                return res.status(401).json({ error: error.message });
            }

            return res.status(500).json({
                error: error?.message || 'Internal server error'
            });
        }
    });
});
