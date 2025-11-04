/**
 * Conversation Management API - Phase 2 (Updated: Provider API Key Prioritization)
 *
 * Full conversation lifecycle management:
 * - Create conversations
 * - List with pagination and filtering
 * - Retrieve single conversation with full history
 * - Update conversation metadata
 * - Delete conversations
 * - Manage messages within conversations
 * - Auto-inject relevant memories before chat
 *
 * All data is encrypted at rest in Firestore
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import cors from 'cors';
import { withApiKeyAndCors } from '../utils/apiKeyMiddleware';
import { v4 as uuidv4 } from 'uuid';
import {
  retrieveRelevantMemories,
  formatMemoriesForInjection,
  StoredMemory,
} from '../utils/memoryScoring';
import { OpenAIProvider } from '../providers/openaiProvider';
import { AnthropicProvider } from '../providers/anthropicProvider';
import { GeminiProvider } from '../providers/geminiProvider';
import { OpenAICompatibleProvider } from '../providers/openaiCompatibleProvider';
import { ProviderRequest, ProviderResponse } from '../providers/types';

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
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
});

// Firebase services
const getDb = () => admin.firestore();
const getAuth = () => admin.auth();

// Initialize providers for integrated message + response
const providers = {
  openai: new OpenAIProvider(),
  anthropic: new AnthropicProvider(),
  gemini: new GeminiProvider(),
  'openai-compatible': new OpenAICompatibleProvider(),
};

/**
 * Parse response for code blocks (artifacts)
 */
function extractCodeBlocks(content: string): Array<{ language: string; code: string; title?: string }> {
  const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
  const blocks: Array<{ language: string; code: string; title?: string }> = [];
  let match;

  while ((match = codeBlockRegex.exec(content)) !== null) {
    const language = match[1] || 'plaintext';
    const code = match[2].trim();

    if (code.length > 0) {
      blocks.push({
        language,
        code,
        title: `${language} Code Block`,
      });
    }
  }

  return blocks;
}

/**
 * Parse response for learnings (memories)
 */
function extractLearnings(content: string): Array<{ content: string; type: string }> {
  const learnings: Array<{ content: string; type: string }> = [];

  // Look for common learning patterns
  const patterns = [
    { regex: /(?:I learned|I discovered|I found out|Note:|Key point:)\s*(.+?)(?:\n|$)/gi, type: 'fact' },
    { regex: /(?:This means|This implies|This shows)\s*(.+?)(?:\n|$)/gi, type: 'insight' },
    { regex: /(?:Question:|I wonder|Consider:)\s*(.+?)(?:\n|$)/gi, type: 'question' },
  ];

  for (const { regex, type } of patterns) {
    let match;
    while ((match = regex.exec(content)) !== null) {
      const text = match[1].trim();
      if (text.length > 10 && text.length < 500) {
        learnings.push({
          content: text,
          type,
        });
      }
    }
  }

  // Also extract sentences that look like learnings
  const sentences = content.split(/[.!?]+/).filter(s => s.trim().length > 20);
  for (const sentence of sentences.slice(0, 3)) {
    const trimmed = sentence.trim();
    if (!learnings.some(l => l.content.toLowerCase() === trimmed.toLowerCase())) {
      learnings.push({
        content: trimmed,
        type: 'fact',
      });
    }
  }

  return learnings.slice(0, 5); // Limit to 5 learnings
}

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
 * Type definitions
 */

export interface ConversationMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  createdAt: number;
  updatedAt: number;
  metadata?: {
    model?: string;
    providerId?: string;
    memoryContext?: string;
    tokensUsed?: number;
    isRegenerated?: boolean;
    regeneratedFrom?: string;
  };
}

export interface ConversationData {
  id: string;
  userId: string;
  projectId: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messageCount: number;
  lastMessageAt?: number;
  archived: boolean;
}

/**
 * Function: apiCreateConversation
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiCreateConversation
 * Create a new conversation
 *
 * Request body:
 * {
 *   "projectId": "project-id",
 *   "title": "Conversation Title",
 *   "initialMessage": "First message content (optional)"
 * }
 */
export const apiCreateConversation = functions.https.onRequest(async (req, res) => {
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

      const { projectId, title, initialMessage } = req.body;

      // Validate input
      if (!projectId || typeof projectId !== 'string') {
        return res.status(400).json({ error: 'Project ID is required' });
      }

      if (!title || typeof title !== 'string' || title.length === 0) {
        return res.status(400).json({ error: 'Title is required' });
      }

      const now = Date.now();
      const conversationId = uuidv4();

      const conversation: ConversationData = {
        id: conversationId,
        userId: uid,
        projectId,
        title,
        createdAt: now,
        updatedAt: now,
        messageCount: 0,
        archived: false,
      };

      // Create conversation document
      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .set(conversation);

      // If initial message provided, add it
      if (initialMessage && typeof initialMessage === 'string') {
        const messageId = uuidv4();
        const message: ConversationMessage = {
          id: messageId,
          role: 'user',
          content: initialMessage,
          createdAt: now,
          updatedAt: now,
        };

        await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .set(message);

        // Update conversation with message count
        await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .update({
            messageCount: 1,
            lastMessageAt: now,
          });

        conversation.messageCount = 1;
        conversation.lastMessageAt = now;
      }

      return res.status(201).json({
        conversation,
        message: 'Conversation created successfully',
      });
    } catch (error: any) {
      console.error('Create Conversation Error:', error);

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
 * Function: apiListConversations
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiListConversations
 * List all conversations for user with pagination and filtering
 *
 * Query parameters:
 * - projectId: Filter by project (optional)
 * - sortBy: Field to sort by (createdAt, updatedAt, title) - default: -updatedAt
 * - limit: Results per page (default 20, max 100)
 * - offset: Pagination offset (default 0)
 * - archived: Include archived conversations (default false)
 * - listAll: Fetch all conversations at once, ignoring pagination (optional, default false, max 5000)
 * - updatedSince: Return only conversations updated after this Unix timestamp (optional, enables delta sync)
 * - fields: Comma-separated fields to include (optional, e.g., "id,title,updatedAt" for minimal payload)
 */
export const apiListConversations = functions.https.onRequest(async (req, res) => {
  if (req.method === 'OPTIONS') {
    corsHandler(req, res, () => res.status(204).send(''));
    return;
  }

  corsHandler(req, res, async () => {
    const startTime = Date.now();
    const operationsPerformed: string[] = [];
    const warnings: string[] = [];

    try {
      const { uid } = await verifyToken(req);

      if (req.method !== 'GET') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      // Constants
      const DEFAULT_LIMIT = 20;
      const MAX_LIMIT = 100;
      const MAX_LISTALL = 5000;

      // Parse query parameters
      const projectId = req.query.projectId as string | undefined;
      const sortBy = (req.query.sortBy as string) || '-updatedAt';
      const listAll = req.query.listAll === 'true';
      const updatedSince = req.query.updatedSince ? parseInt(req.query.updatedSince as string) : undefined;
      const fieldsParam = req.query.fields as string | undefined;

      // Parse requested fields if specified
      let requestedFields: Set<string> | null = null;
      if (fieldsParam) {
        requestedFields = new Set(fieldsParam.split(',').map(f => f.trim()));
        operationsPerformed.push('fields_filter');
      }

      // Determine pagination limits
      let limit = DEFAULT_LIMIT;
      let offset = 0;
      if (listAll) {
        limit = MAX_LISTALL;
        operationsPerformed.push('listAll_mode');
        if (req.query.limit || req.query.offset) {
          warnings.push('listAll=true overrides limit and offset parameters');
        }
      } else {
        limit = Math.min(parseInt(req.query.limit as string) || DEFAULT_LIMIT, MAX_LIMIT);
        offset = parseInt(req.query.offset as string) || 0;
      }

      const includeArchived = req.query.archived === 'true';

      // Build Firestore query
      let query = getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations') as FirebaseFirestore.Query<FirebaseFirestore.DocumentData>;

      // Apply archived filter
      if (!includeArchived) {
        query = query.where('archived', '==', false);
      }

      // Filter by project if specified
      if (projectId) {
        query = query.where('projectId', '==', projectId);
      }

      operationsPerformed.push('query_execute');

      // Get all matching conversations
      const snapshot = await query.get();

      let conversations = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
      } as ConversationData));

      operationsPerformed.push('data_retrieve');

      // Filter by updatedSince if specified (delta sync)
      let deletedConversationIds: string[] = [];
      if (updatedSince !== undefined) {
        conversations = conversations.filter(conv => conv.updatedAt > updatedSince);
        operationsPerformed.push('delta_sync_filter');

        // Also query for deleted conversations (tombstones) since the last sync
        const tombstonesSnapshot = await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversationTombstones')
          .where('deletedAt', '>', updatedSince)
          .get();

        deletedConversationIds = tombstonesSnapshot.docs.map(doc => doc.id);

        if (conversations.length === 0 && deletedConversationIds.length === 0) {
          warnings.push('No conversations updated or deleted since the specified timestamp');
        }

        operationsPerformed.push('tombstone_query');
      }

      // Apply field filtering if specified (reduces payload)
      if (requestedFields) {
        conversations = conversations.map(conv => {
          const filtered: any = {};
          requestedFields!.forEach(field => {
            if (field in conv) {
              filtered[field] = (conv as any)[field];
            }
          });
          return filtered;
        });
      }

      // Validate sort field
      const validSortFields = ['createdAt', 'updatedAt', 'title', 'messageCount'];
      let [field, direction] = sortBy.startsWith('-')
        ? [sortBy.substring(1), 'desc' as const]
        : [sortBy, 'asc' as const];

      if (!validSortFields.includes(field)) {
        warnings.push(`Invalid sort field: ${field}. Using default sort (updatedAt descending).`);
        field = 'updatedAt';
      }

      // Sort in memory
      conversations.sort((a: any, b: any) => {
        const aValue = a[field];
        const bValue = b[field];

        if (typeof aValue === 'number' && typeof bValue === 'number') {
          return direction === 'desc' ? bValue - aValue : aValue - bValue;
        }

        if (typeof aValue === 'string' && typeof bValue === 'string') {
          return direction === 'desc'
            ? bValue.localeCompare(aValue)
            : aValue.localeCompare(bValue);
        }

        return 0;
      });

      operationsPerformed.push('sort_apply');

      // Fetch all messages for each conversation if listAll=true
      let messagesIncluded = false;
      let totalMessagesCount = 0;
      if (listAll) {
        try {
          const conversationsWithMessages = await Promise.all(
            conversations.map(async (conv) => {
              const messagesSnapshot = await getDb()
                .collection('users')
                .doc(uid)
                .collection('conversations')
                .doc(conv.id)
                .collection('messages')
                .orderBy('createdAt', 'asc')
                .get();

              const messages = messagesSnapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data(),
              } as ConversationMessage));

              totalMessagesCount += messages.length;

              return {
                ...conv,
                messages,
              };
            })
          );

          conversations = conversationsWithMessages as any;
          messagesIncluded = true;
          operationsPerformed.push('messages_fetch');

          // Warn if payload is getting very large
          if (totalMessagesCount > 10000) {
            warnings.push(`Large payload warning: ${totalMessagesCount} messages being returned. Consider breaking initial sync into multiple requests.`);
          }
        } catch (error: any) {
          warnings.push(`Failed to fetch messages for listAll mode: ${error.message}`);
          console.warn('Message fetch error in listAll mode:', error);
          // Continue without messages rather than failing the entire request
        }
      }

      // Check if we're hitting the listAll safety limit
      if (listAll && conversations.length >= MAX_LISTALL) {
        warnings.push(`Query result capped at ${MAX_LISTALL} conversations. Use pagination or filters to retrieve more.`);
      }

      // Paginate
      const total = conversations.length;
      const paginatedConversations = conversations.slice(offset, offset + limit);

      if (total === 0 && (projectId || includeArchived || updatedSince)) {
        warnings.push('Query returned 0 results. Consider adjusting filters.');
      }

      operationsPerformed.push('pagination_apply');

      const totalTime = Date.now() - startTime;
      const serverTimestamp = Date.now();

      return res.status(200).json({
        conversations: paginatedConversations,
        deletedConversations: deletedConversationIds.length > 0 ? deletedConversationIds : undefined,
        pagination: {
          total,
          limit,
          offset,
          hasMore: offset + limit < total,
        },
        sync: {
          mode: listAll ? 'full' : updatedSince ? 'delta' : 'paginated',
          timestamp: serverTimestamp,
          updatedSince: updatedSince || null,
          conversationsUpdated: conversations.length,
          conversationsDeleted: deletedConversationIds.length,
          messagesIncluded,
          totalMessagesIncluded: messagesIncluded ? totalMessagesCount : undefined,
        },
        metadata: {
          projectId: projectId || null,
          sortBy,
          includeArchived,
          fieldsRequested: fieldsParam || null,
          totalTime,
          operationsPerformed,
          warnings: warnings.length > 0 ? warnings : undefined,
        },
      });
    } catch (error: any) {
      console.error('List Conversations Error:', error, {
        query: {
          projectId: req.query.projectId,
          sortBy: req.query.sortBy,
          listAll: req.query.listAll,
          updatedSince: req.query.updatedSince,
          fields: req.query.fields,
          limit: req.query.limit,
          offset: req.query.offset,
          archived: req.query.archived,
        },
      });

      if (error instanceof functions.https.HttpsError) {
        return res.status(401).json({ error: error.message });
      }

      return res.status(500).json({
        error: error?.message || 'Internal server error',
        operationsPerformed,
      });
    }
  });
});

/**
 * Function: apiGetConversation
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiGetConversation
 * Retrieve a single conversation with full message history (conversationId passed as path parameter)
 *
 * Query parameters:
 * - messagesLimit: Max messages to return (default 50, max 100)
 * - messagesOffset: Message pagination offset (default 0)
 * - includeMemories: Include relevant memories for context (default false)
 */
export const apiGetConversation = functions.https.onRequest(async (req, res) => {
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

      // Extract conversation ID from path
      const pathParts = req.path.split('/');
      const conversationId = pathParts[pathParts.length - 1];

      if (!conversationId) {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      // Get conversation
      const conversationDoc = await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .get();

      if (!conversationDoc.exists) {
        return res.status(404).json({ error: 'Conversation not found' });
      }

      const conversation = {
        id: conversationDoc.id,
        ...conversationDoc.data(),
      } as ConversationData;

      // Get messages
      const messagesLimit = Math.min(parseInt(req.query.messagesLimit as string) || 50, 100);
      const messagesOffset = parseInt(req.query.messagesOffset as string) || 0;
      const includeMemories = req.query.includeMemories === 'true';

      const messagesSnapshot = await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', 'asc')
        .get();

      const allMessages = messagesSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
      } as ConversationMessage));

      const paginatedMessages = allMessages.slice(messagesOffset, messagesOffset + messagesLimit).map(msg => ({
        ...msg,
        conversationId,
      }));

      // Optionally retrieve relevant memories
      let relevantMemories = null;
      if (includeMemories) {
        const conversationText = allMessages
          .filter(m => m.role === 'user')
          .map(m => m.content)
          .join(' ');

        // Fetch user's memories
        const memoriesSnapshot = await getDb()
          .collection('users')
          .doc(uid)
          .collection('memories')
          .get();

        const memories: StoredMemory[] = memoriesSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data(),
        } as StoredMemory));

        const relevant = retrieveRelevantMemories(conversationText, memories, {
          maxMemories: 10,
          minConfidence: 0.3,
          excludeArchived: true,
        });

        relevantMemories = {
          memories: relevant,
          injection: formatMemoriesForInjection(relevant),
        };
      }

      return res.status(200).json({
        conversation,
        messages: paginatedMessages,
        messagePagination: {
          total: allMessages.length,
          limit: messagesLimit,
          offset: messagesOffset,
          hasMore: messagesOffset + messagesLimit < allMessages.length,
        },
        memories: includeMemories ? relevantMemories : undefined,
      });
    } catch (error: any) {
      console.error('Get Conversation Error:', error);

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
 * Function: apiUpdateConversation
 * Method: PATCH
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiUpdateConversation
 * Update conversation metadata (conversationId passed as path parameter)
 *
 * Request body:
 * {
 *   "title": "New Title",
 *   "archived": false
 * }
 */
export const apiUpdateConversation = functions.https.onRequest(async (req, res) => {
  if (req.method === 'OPTIONS') {
    corsHandler(req, res, () => res.status(204).send(''));
    return;
  }

  corsHandler(req, res, async () => {
    try {
      const { uid } = await verifyToken(req);

      if (req.method !== 'PATCH') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      // Extract conversation ID from path
      const pathParts = req.path.split('/');
      const conversationId = pathParts[pathParts.length - 1];

      if (!conversationId) {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      const { title, archived } = req.body;

      // Build update object
      const updateData: any = {
        updatedAt: Date.now(),
      };

      if (title !== undefined) {
        if (typeof title !== 'string' || title.length === 0) {
          return res.status(400).json({ error: 'Title must be non-empty string' });
        }
        updateData.title = title;
      }

      if (archived !== undefined) {
        if (typeof archived !== 'boolean') {
          return res.status(400).json({ error: 'Archived must be boolean' });
        }
        updateData.archived = archived;
      }

      if (Object.keys(updateData).length === 1) {
        // Only updatedAt, nothing to update
        return res.status(400).json({ error: 'No fields to update' });
      }

      // Update conversation
      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .update(updateData);

      // Return updated conversation
      const updatedDoc = await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .get();

      return res.status(200).json({
        conversation: {
          id: updatedDoc.id,
          ...updatedDoc.data(),
        },
        message: 'Conversation updated successfully',
      });
    } catch (error: any) {
      console.error('Update Conversation Error:', error);

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
 * Function: apiDeleteConversation
 * Method: DELETE
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiDeleteConversation
 * Delete (archive) a conversation (conversationId passed as path parameter)
 *
 * Query parameters:
 * - hardDelete: Permanently delete if true, archive if false (default false)
 *
 * Notes:
 * - hardDelete=false: Soft delete, marks as archived (recoverable)
 * - hardDelete=true: Hard delete, permanently removes conversation and creates tombstone for sync
 * - Tombstones are used for delta sync detection and auto-cleanup after 30 days via Firestore TTL
 */
export const apiDeleteConversation = functions.https.onRequest(async (req, res) => {
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

      // Extract conversation ID from path
      const pathParts = req.path.split('/');
      const conversationId = pathParts[pathParts.length - 1];

      if (!conversationId) {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      const hardDelete = req.query.hardDelete === 'true';
      const now = Date.now();

      if (hardDelete) {
        // Hard delete: Permanently remove conversation and create tombstone for sync detection
        const messagesSnapshot = await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .get();

        // Delete all messages and conversation in batch
        const batch = admin.firestore().batch();
        messagesSnapshot.docs.forEach(doc => {
          batch.delete(doc.ref);
        });

        // Delete conversation
        const conversationRef = getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId);

        batch.delete(conversationRef);

        // Create tombstone record for delta sync detection
        // TTL policy should be configured in Firestore to auto-delete after 30 days
        const tombstoneRef = getDb()
          .collection('users')
          .doc(uid)
          .collection('conversationTombstones')
          .doc(conversationId);

        batch.set(tombstoneRef, {
          id: conversationId,
          deletedAt: now,
          // TTL timestamp for Firestore auto-delete (30 days from now)
          expireAt: new Date(now + 30 * 24 * 60 * 60 * 1000),
        });

        await batch.commit();
      } else {
        // Soft delete: just mark as archived (recoverable)
        await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .update({
            archived: true,
            updatedAt: now,
          });
      }

      return res.status(200).json({
        message: `Conversation ${hardDelete ? 'permanently deleted' : 'archived'} successfully`,
        hardDelete,
        timestamp: now,
      });
    } catch (error: any) {
      console.error('Delete Conversation Error:', error);

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
 * Function: apiAddMessage
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiAddMessage
 * Add a message to a conversation (conversationId passed as path parameter)
 *
 * Request body:
 * {
 *   "role": "user" | "assistant",
 *   "content": "Message content",
 *   "metadata": {...}
 * }
 */
export const apiAddMessage = functions.https.onRequest(async (req, res) => {
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

      // Extract conversation ID from path
      const pathParts = req.path.split('/');
      const conversationId = pathParts[pathParts.length - 2]; // before /messages

      if (!conversationId) {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      const { role, content, metadata } = req.body;

      // Validate input
      if (!role || !['user', 'assistant'].includes(role)) {
        return res.status(400).json({ error: 'Role must be "user" or "assistant"' });
      }

      if (!content || typeof content !== 'string' || content.length === 0) {
        return res.status(400).json({ error: 'Content is required' });
      }

      const now = Date.now();
      const messageId = uuidv4();

      const message: ConversationMessage = {
        id: messageId,
        role,
        content,
        createdAt: now,
        updatedAt: now,
        ...(metadata && { metadata }),
      };

      // Add message
      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .set(message);

      // Update conversation message count
      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .update({
          messageCount: admin.firestore.FieldValue.increment(1),
          lastMessageAt: now,
          updatedAt: now,
        });

      return res.status(201).json({
        message: {
          ...message,
          conversationId,
        },
        conversationUpdated: true,
      });
    } catch (error: any) {
      console.error('Add Message Error:', error);

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
 * Function: apiGetMessages
 * Method: GET
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiGetMessages
 * Get messages for a conversation with pagination
 *
 * Conversation ID can be passed as:
 * - Path parameter: /conversations/{conversationId}/messages
 * - Query parameter: ?conversationId={conversationId}
 *
 * Query parameters:
 * - conversationId: Conversation ID (optional if passed in path)
 * - limit: Messages per page (default 50, max 100)
 * - offset: Pagination offset (default 0)
 */
export const apiGetMessages = functions.https.onRequest(async (req, res) => {
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

      // Extract conversation ID from query params or path
      const pathParts = req.path.split('/');
      const conversationId = (req.query.conversationId as string) || pathParts[pathParts.length - 2]; // before /messages

      if (!conversationId) {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);
      const offset = parseInt(req.query.offset as string) || 0;

      // Get messages
      const snapshot = await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', 'asc')
        .get();

      const allMessages = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
      } as ConversationMessage));

      const paginatedMessages = allMessages.slice(offset, offset + limit).map(msg => ({
        ...msg,
        conversationId,
      }));

      return res.status(200).json({
        messages: paginatedMessages,
        pagination: {
          total: allMessages.length,
          limit,
          offset,
          hasMore: offset + limit < allMessages.length,
        },
      });
    } catch (error: any) {
      console.error('Get Messages Error:', error);

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
 * Function: apiAddMessageWithResponse
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiAddMessageWithResponse
 * Add a user message and get LLM response in a single call (conversationId passed as path parameter)
 *
 * Request body:
 * {
 *   "content": "User message content",
 *   "provider": "anthropic" | "openai" | "gemini",
 *   "model": "claude-3-5-sonnet" (optional),
 *   "includeMemories": true (optional, default: true),
 *   "projectId": "project-id" (optional),
 *   "temperature": 0.7 (optional),
 *   "maxTokens": 2048 (optional)
 * }
 *
 * Response:
 * {
 *   "userMessage": { id, role: "user", content, conversationId, createdAt, updatedAt },
 *   "assistantMessage": { id, role: "assistant", content, conversationId, createdAt, updatedAt, metadata },
 *   "conversationUpdated": true
 * }
 */
export const apiAddMessageWithResponse = functions.https.onRequest(async (req, res) => {
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

      // Extract conversation ID from path
      const pathParts = req.path.split('/');
      const conversationId = pathParts[pathParts.length - 3]; // before /messages-with-response

      if (!conversationId) {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      const {
        content,
        provider,
        model,
        includeMemories = true,
        projectId,
        temperature,
        maxTokens,
        anthropic,
        openai,
        gemini,
        openaiCompatible,
      } = req.body;

      // Validate input
      if (!content || typeof content !== 'string' || content.length === 0) {
        return res.status(400).json({ error: 'Content is required' });
      }

      if (!provider || !['openai', 'anthropic', 'gemini', 'openai-compatible'].includes(provider)) {
        return res.status(400).json({ error: 'Valid provider is required: openai, anthropic, gemini, or openai-compatible' });
      }

      // Create provider instances with request-provided API keys if available
      // This allows clients to pass their own keys in the request body
      let selectedProviderInstance = providers[provider as keyof typeof providers];

      if (provider === 'anthropic' && anthropic) {
        const apiKey = typeof anthropic === 'string' ? anthropic : anthropic.apiKey;
        selectedProviderInstance = new AnthropicProvider(apiKey);
      } else if (provider === 'openai' && openai) {
        const apiKey = typeof openai === 'string' ? openai : openai.apiKey;
        selectedProviderInstance = new OpenAIProvider(apiKey);
      } else if (provider === 'gemini' && gemini) {
        const apiKey = typeof gemini === 'string' ? gemini : gemini.apiKey;
        selectedProviderInstance = new GeminiProvider(apiKey);
      } else if (provider === 'openai-compatible' && openaiCompatible) {
        const apiKey = typeof openaiCompatible === 'string'
          ? openaiCompatible
          : openaiCompatible.apiKey;
        const baseUrl = typeof openaiCompatible === 'object'
          ? openaiCompatible.baseUrl
          : undefined;
        selectedProviderInstance = new OpenAICompatibleProvider(apiKey, baseUrl);
      }

      const now = Date.now();

      // 1. Save user message
      const userMessageId = uuidv4();
      const userMessage: ConversationMessage = {
        id: userMessageId,
        role: 'user',
        content,
        createdAt: now,
        updatedAt: now,
      };

      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(userMessageId)
        .set(userMessage);

      // 2. Get all conversation messages (including the one we just added)
      const messagesSnapshot = await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', 'asc')
        .get();

      const allMessages = messagesSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
      } as ConversationMessage));

      // 3. Prepare system prompt with memories
      let systemPrompt = 'You are Axon, a helpful AI assistant that evolves slowly over time as you make memories about yourself and the user..';
      let memoryContext = null;

      if (includeMemories) {
        // Fetch user's memories
        const memoriesSnapshot = await getDb()
          .collection('users')
          .doc(uid)
          .collection('memories')
          .get();

        const memories: StoredMemory[] = memoriesSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data(),
        } as StoredMemory));

        // Retrieve relevant memories
        const conversationText = allMessages
          .filter(m => m.role === 'user')
          .map(m => m.content)
          .join(' ');

        const relevantMemories = retrieveRelevantMemories(conversationText, memories, {
          maxMemories: 20,
          minConfidence: 0.3,
          excludeArchived: true,
          ...(projectId && { projectId }),
        });

        // Inject memories into system prompt
        const memoryInjection = formatMemoriesForInjection(relevantMemories);
        if (memoryInjection) {
          systemPrompt += memoryInjection;
        }

        memoryContext = {
          memoriesIncluded: relevantMemories.length,
          allocentricMemories: relevantMemories.filter((m: any) => m.type === 'allocentric').length,
          egoicMemories: relevantMemories.filter((m: any) => m.type === 'egoic').length,
          averageConfidence: relevantMemories.length > 0
            ? relevantMemories.reduce((sum: number, m: any) => sum + m.confidence, 0) / relevantMemories.length
            : 0,
        };
      }

      // 4. Prepare messages for LLM
      const llmMessages = [
        { role: 'system' as const, content: systemPrompt },
        ...allMessages.map(m => ({
          role: m.role as 'user' | 'assistant',
          content: m.content,
        })),
      ];

      // 5. Call LLM provider
      if (!selectedProviderInstance) {
        return res.status(400).json({ error: `Invalid provider: ${provider}` });
      }

      const providerRequest: ProviderRequest = {
        messages: llmMessages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      };

      const response: ProviderResponse = await selectedProviderInstance.invoke(providerRequest, uid);

      // 6. Save assistant message
      const assistantMessageId = uuidv4();
      const assistantResponseTime = Date.now();
      const assistantMessage: ConversationMessage = {
        id: assistantMessageId,
        role: 'assistant',
        content: response.content,
        createdAt: assistantResponseTime,
        updatedAt: assistantResponseTime,
        metadata: {
          model: response.model || model || 'unknown',
          providerId: provider,
          tokensUsed: response.usage?.totalTokens,
          memoryContext: memoryContext ? JSON.stringify(memoryContext) : undefined,
        },
      };

      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(assistantMessageId)
        .set(assistantMessage);

      // 7. Update conversation with new message count
      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .update({
          messageCount: admin.firestore.FieldValue.increment(2), // user + assistant
          lastMessageAt: assistantResponseTime,
          updatedAt: assistantResponseTime,
        });

      // 8. Return both messages to client
      return res.status(201).json({
        userMessage: {
          ...userMessage,
          conversationId,
        },
        assistantMessage: {
          ...assistantMessage,
          conversationId,
        },
        conversationUpdated: true,
      });
    } catch (error: any) {
      console.error('Add Message With Response Error:', error);

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
 * Function: apiRegenerateMessage
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiRegenerateMessage
 * Regenerate the last assistant response with the same context (conversationId passed as path parameter)
 * Useful for getting a different response without changing the conversation state
 *
 * Request body:
 * {
 *   "provider": "anthropic",
 *   "options": {
 *     "model": "claude-3-5-sonnet" (optional),
 *     "temperature": 0.8 (optional, can differ from original),
 *     "maxTokens": 2048 (optional),
 *     "includeMemories": true (default),
 *     "replaceLastMessage": false (default: false - creates new message, true - replaces),
 *     "projectId": "project-123" (optional)
 *   }
 * }
 *
 * Response:
 * {
 *   "userMessage": { the last user message that prompted regeneration },
 *   "assistantMessage": { the newly generated assistant response },
 *   "replacedMessageId": "msg-id" (only if replaceLastMessage was true),
 *   "conversationUpdated": true,
 *   "metadata": { timing and operations performed }
 * }
 */
export const apiRegenerateMessage = functions.https.onRequest(async (req, res) => {
  if (req.method === 'OPTIONS') {
    corsHandler(req, res, () => res.status(204).send(''));
    return;
  }

  corsHandler(req, res, async () => {
    const startTime = Date.now();
    const operationsPerformed: string[] = [];
    const warnings: string[] = [];

    try {
      const { uid } = await verifyToken(req);

      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      // Extract conversation ID from path
      const pathParts = req.path.split('/');
      const conversationId = pathParts[pathParts.length - 2]; // before /regenerate

      if (!conversationId) {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      const {
        provider,
        options = {},
        anthropic,
        openai,
        gemini,
      } = req.body;

      // Validate input
      if (!provider || !['openai', 'anthropic', 'gemini', 'openai-compatible'].includes(provider)) {
        return res.status(400).json({ error: 'Valid provider is required: openai, anthropic, gemini, or openai-compatible' });
      }

      const {
        model,
        temperature,
        maxTokens,
        includeMemories = true,
        replaceLastMessage = false,
        projectId,
      } = options;

      // Get all conversation messages
      const messagesSnapshot = await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .orderBy('createdAt', 'asc')
        .get();

      const allMessages = messagesSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
      } as ConversationMessage));

      if (allMessages.length < 2) {
        return res.status(400).json({
          error: 'Conversation must have at least one user message and one assistant response to regenerate',
        });
      }

      // Find the last assistant message to understand what we're regenerating
      let lastAssistantIndex = -1;
      for (let i = allMessages.length - 1; i >= 0; i--) {
        if (allMessages[i].role === 'assistant') {
          lastAssistantIndex = i;
          break;
        }
      }

      if (lastAssistantIndex === -1) {
        return res.status(400).json({
          error: 'No assistant message found to regenerate',
        });
      }

      const lastAssistantMessage = allMessages[lastAssistantIndex];
      const replacedMessageId = lastAssistantMessage.id;

      // Messages up to (but not including) the last assistant message
      const contextMessages = allMessages.slice(0, lastAssistantIndex);

      // Create provider instances with request-provided API keys if available
      let selectedProviderInstance = providers[provider as keyof typeof providers];

      if (provider === 'anthropic' && anthropic) {
        selectedProviderInstance = new AnthropicProvider(anthropic);
      } else if (provider === 'openai' && openai) {
        selectedProviderInstance = new OpenAIProvider(openai);
      } else if (provider === 'gemini' && gemini) {
        selectedProviderInstance = new GeminiProvider(gemini);
      }

      // Prepare system prompt with memories
      let systemPrompt = 'You are Axon, a helpful AI assistant that evolves slowly over time as you make memories about yourself and the user..';
      let memoryContext = null;

      if (includeMemories) {
        const memoriesSnapshot = await getDb()
          .collection('users')
          .doc(uid)
          .collection('memories')
          .get();

        const memories: StoredMemory[] = memoriesSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data(),
        } as StoredMemory));

        const conversationText = contextMessages
          .filter(m => m.role === 'user')
          .map(m => m.content)
          .join(' ');

        const relevantMemories = retrieveRelevantMemories(conversationText, memories, {
          maxMemories: 20,
          minConfidence: 0.3,
          excludeArchived: true,
          ...(projectId && { projectId }),
        });

        const memoryInjection = formatMemoriesForInjection(relevantMemories);
        if (memoryInjection) {
          systemPrompt += memoryInjection;
        }

        memoryContext = {
          memoriesIncluded: relevantMemories.length,
          allocentricMemories: relevantMemories.filter((m: any) => m.type === 'allocentric').length,
          egoicMemories: relevantMemories.filter((m: any) => m.type === 'egoic').length,
          averageConfidence: relevantMemories.length > 0
            ? relevantMemories.reduce((sum: number, m: any) => sum + m.confidence, 0) / relevantMemories.length
            : 0,
        };
      }

      // Prepare messages for LLM (context only, no assistant response)
      const llmMessages = [
        { role: 'system' as const, content: systemPrompt },
        ...contextMessages.map(m => ({
          role: m.role as 'user' | 'assistant',
          content: m.content,
        })),
      ];

      // Call LLM provider
      if (!selectedProviderInstance) {
        return res.status(400).json({ error: `Invalid provider: ${provider}` });
      }

      const llmStartTime = Date.now();
      const providerRequest: ProviderRequest = {
        messages: llmMessages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      };

      const response: ProviderResponse = await selectedProviderInstance.invoke(providerRequest, uid);
      const llmTime = Date.now() - llmStartTime;

      operationsPerformed.push('llm_regenerate');

      // Prepare the new assistant message
      const now = Date.now();
      const newAssistantMessageId = uuidv4();
      const newAssistantMessage: ConversationMessage = {
        id: newAssistantMessageId,
        role: 'assistant',
        content: response.content,
        createdAt: now,
        updatedAt: now,
        metadata: {
          model: response.model || model || 'unknown',
          providerId: provider,
          tokensUsed: response.usage?.totalTokens,
          memoryContext: memoryContext ? JSON.stringify(memoryContext) : undefined,
          isRegenerated: true,
          regeneratedFrom: replacedMessageId,
        },
      };

      if (replaceLastMessage) {
        // Replace the old assistant message
        await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(replacedMessageId)
          .set(newAssistantMessage);

        operationsPerformed.push('message_replace');
      } else {
        // Create new message alongside the old one
        await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(newAssistantMessageId)
          .set(newAssistantMessage);

        operationsPerformed.push('message_create');

        // Update conversation message count
        await getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .update({
            messageCount: admin.firestore.FieldValue.increment(1),
            lastMessageAt: now,
            updatedAt: now,
          });

        operationsPerformed.push('conversation_update');
      }

      // Get the last user message for context in response
      let userMessage = contextMessages[contextMessages.length - 1];
      if (!userMessage) {
        // Fallback if no user message found in context
        userMessage = allMessages.find(m => m.role === 'user') || ({} as ConversationMessage);
      }

      // Return response
      const totalTime = Date.now() - startTime;

      const responseBody: any = {
        userMessage: {
          ...userMessage,
          conversationId,
        },
        assistantMessage: {
          ...newAssistantMessage,
          conversationId,
        },
        conversationUpdated: !replaceLastMessage, // Only updated if we added a new message
        metadata: {
          totalTime,
          llmTime,
          operationsPerformed,
          replacedMessageId: replaceLastMessage ? replacedMessageId : undefined,
          warnings: warnings.length > 0 ? warnings : undefined,
        },
      };

      return res.status(201).json(responseBody);
    } catch (error: any) {
      console.error('Regenerate Message Error:', error);

      if (error instanceof functions.https.HttpsError) {
        return res.status(401).json({ error: error.message });
      }

      return res.status(500).json({
        error: error?.message || 'Internal server error',
      });
    }
  });
});

/**
 * Function: apiOrchestrate
 * Method: POST
 * Endpoint: https://us-central1-neurx-8f122.cloudfunctions.net/apiOrchestrate
 * Unified chat orchestrator - handles messages, memories, and artifacts in one call
 *
 * Request body:
 * {
 *   "conversationId": "conv-123",
 *   "message": "Write a Python function",
 *   "provider": "anthropic",
 *   "options": {
 *     "model": "claude-3-5-sonnet" (optional),
 *     "includeMemories": true (default),
 *     "createArtifacts": true (default),
 *     "saveMemories": true (default),
 *     "projectId": "project-123" (optional)
 *   }
 * }
 */
export const apiOrchestrate = functions.https.onRequest(async (req, res) => {
  if (req.method === 'OPTIONS') {
    corsHandler(req, res, () => res.status(204).send(''));
    return;
  }

  corsHandler(req, res, async () => {
    const startTime = Date.now();
    const operationsPerformed: string[] = [];
    const warnings: string[] = [];

    try {
      const { uid } = await verifyToken(req);

      if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
      }

      const {
        conversationId,
        message,
        provider,
        options = {},
        anthropic,
        openai,
        gemini,
        openaiCompatible,
      } = req.body;

      // Validate input
      if (!conversationId || typeof conversationId !== 'string') {
        return res.status(400).json({ error: 'Conversation ID is required' });
      }

      if (!message || typeof message !== 'string' || message.length === 0) {
        return res.status(400).json({ error: 'Message content is required' });
      }

      if (!provider || !['openai', 'anthropic', 'gemini', 'openai-compatible'].includes(provider)) {
        return res.status(400).json({ error: 'Valid provider is required: openai, anthropic, gemini, or openai-compatible' });
      }

      const {
        model,
        temperature,
        maxTokens,
        includeMemories = true,
        createArtifacts = true,
        saveMemories = true,
        projectId,
      } = options;

      // Create provider instances with request-provided API keys if available
      // This allows clients to pass their own keys in the request body
      let selectedProviderInstance = providers[provider as keyof typeof providers];

      if (provider === 'anthropic' && anthropic) {
        const apiKey = typeof anthropic === 'string' ? anthropic : anthropic.apiKey;
        selectedProviderInstance = new AnthropicProvider(apiKey);
      } else if (provider === 'openai' && openai) {
        const apiKey = typeof openai === 'string' ? openai : openai.apiKey;
        selectedProviderInstance = new OpenAIProvider(apiKey);
      } else if (provider === 'gemini' && gemini) {
        const apiKey = typeof gemini === 'string' ? gemini : gemini.apiKey;
        selectedProviderInstance = new GeminiProvider(apiKey);
      } else if (provider === 'openai-compatible' && openaiCompatible) {
        const apiKey = typeof openaiCompatible === 'string'
          ? openaiCompatible
          : openaiCompatible.apiKey;
        const baseUrl = typeof openaiCompatible === 'object'
          ? openaiCompatible.baseUrl
          : undefined;
        selectedProviderInstance = new OpenAICompatibleProvider(apiKey, baseUrl);
      }

      const now = Date.now();

      // 1. Save user message
      const userMessageId = uuidv4();
      const userMessage: ConversationMessage = {
        id: userMessageId,
        role: 'user',
        content: message,
        createdAt: now,
        updatedAt: now,
      };

      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(userMessageId)
        .set(userMessage);

      operationsPerformed.push('message_save');

      // 2. Get conversation messages and user memories
      const [messagesSnapshot, memoriesSnapshot] = await Promise.all([
        getDb()
          .collection('users')
          .doc(uid)
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .orderBy('createdAt', 'asc')
          .get(),
        getDb()
          .collection('users')
          .doc(uid)
          .collection('memories')
          .get(),
      ]);

      const allMessages = messagesSnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data(),
      } as ConversationMessage));

      // 3. Prepare system prompt with memories
      let systemPrompt = 'You are Axon, a helpful AI assistant that evolves slowly over time as you make memories about yourself and the user.';
      let memoryContext = null;

      if (includeMemories) {
        const memories: StoredMemory[] = memoriesSnapshot.docs.map(doc => ({
          id: doc.id,
          ...doc.data(),
        } as StoredMemory));

        const conversationText = allMessages
          .filter(m => m.role === 'user')
          .map(m => m.content)
          .join(' ');

        const relevantMemories = retrieveRelevantMemories(conversationText, memories, {
          maxMemories: 20,
          minConfidence: 0.3,
          excludeArchived: true,
          ...(projectId && { projectId }),
        });

        const memoryInjection = formatMemoriesForInjection(relevantMemories);
        if (memoryInjection) {
          systemPrompt += memoryInjection;
        }

        memoryContext = {
          memoriesIncluded: relevantMemories.length,
          allocentricMemories: relevantMemories.filter((m: any) => m.type === 'allocentric').length,
          egoicMemories: relevantMemories.filter((m: any) => m.type === 'egoic').length,
          averageConfidence: relevantMemories.length > 0
            ? relevantMemories.reduce((sum: number, m: any) => sum + m.confidence, 0) / relevantMemories.length
            : 0,
        };
      }

      // 4. Prepare messages for LLM
      const llmMessages = [
        { role: 'system' as const, content: systemPrompt },
        ...allMessages.map(m => ({
          role: m.role as 'user' | 'assistant',
          content: m.content,
        })),
      ];

      // 5. Call LLM provider
      if (!selectedProviderInstance) {
        return res.status(400).json({ error: `Invalid provider: ${provider}` });
      }

      const llmStartTime = Date.now();
      const providerRequest: ProviderRequest = {
        messages: llmMessages,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
      };

      const response: ProviderResponse = await selectedProviderInstance.invoke(providerRequest, uid);
      const llmTime = Date.now() - llmStartTime;

      operationsPerformed.push('llm_chat');

      // 6. Parse response for artifacts and memories
      const codeBlocks = createArtifacts ? extractCodeBlocks(response.content) : [];
      const learnings = saveMemories ? extractLearnings(response.content) : [];

      const createdArtifacts: any[] = [];
      const createdMemories: any[] = [];

      // 7. Create artifacts
      if (createArtifacts && codeBlocks.length > 0) {
        try {
          for (const block of codeBlocks) {
            const artifactId = uuidv4();
            const artifact = {
              id: artifactId,
              type: 'code',
              language: block.language,
              title: block.title || `${block.language} Code`,
              content: block.code,
              description: '',
              createdAt: now,
              updatedAt: now,
              archived: false,
              conversationId: conversationId,
              userId: uid,
            };

            await getDb()
              .collection('users')
              .doc(uid)
              .collection('artifacts')
              .doc(artifactId)
              .set(artifact);

            createdArtifacts.push(artifact);
          }

          operationsPerformed.push('artifact_create');
        } catch (error: any) {
          warnings.push(`Artifact creation failed: ${error.message}`);
        }
      }

      // 8. Create memories
      if (saveMemories && learnings.length > 0) {
        try {
          for (const learning of learnings) {
            const memoryId = uuidv4();
            const memory = {
              id: memoryId,
              type: learning.type,
              content: learning.content,
              confidence: 0.8,
              tags: [],
              context: `Learned from conversation in ${conversationId}`,
              evidence: '',
              createdAt: now,
              updatedAt: now,
              archived: false,
              userId: uid,
              ...(projectId && { projectId }),
            };

            await getDb()
              .collection('users')
              .doc(uid)
              .collection('memories')
              .doc(memoryId)
              .set(memory);

            createdMemories.push(memory);
          }

          operationsPerformed.push('memory_create');
        } catch (error: any) {
          warnings.push(`Memory creation failed: ${error.message}`);
        }
      }

      // 9. Save assistant message
      const assistantMessageId = uuidv4();
      const assistantResponseTime = Date.now();
      const assistantMessage: ConversationMessage = {
        id: assistantMessageId,
        role: 'assistant',
        content: response.content,
        createdAt: assistantResponseTime,
        updatedAt: assistantResponseTime,
        metadata: {
          model: response.model || model || 'unknown',
          providerId: provider,
          tokensUsed: response.usage?.totalTokens,
          memoryContext: memoryContext ? JSON.stringify(memoryContext) : undefined,
        },
      };

      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(assistantMessageId)
        .set(assistantMessage);

      operationsPerformed.push('assistant_message_save');

      // 10. Update conversation metadata
      await getDb()
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(conversationId)
        .update({
          messageCount: admin.firestore.FieldValue.increment(2),
          lastMessageAt: assistantResponseTime,
          updatedAt: assistantResponseTime,
        });

      operationsPerformed.push('conversation_update');

      // 11. Return unified response
      const totalTime = Date.now() - startTime;

      return res.status(201).json({
        userMessage: {
          ...userMessage,
          conversationId,
        },
        assistantMessage: {
          ...assistantMessage,
          conversationId,
        },
        artifacts: createdArtifacts,
        memories: createdMemories,
        conversationUpdated: true,
        metadata: {
          totalTime,
          llmTime,
          operationsPerformed,
          artifactsCreated: createdArtifacts.length,
          memoriesCreated: createdMemories.length,
          warnings: warnings.length > 0 ? warnings : undefined,
        },
      });
    } catch (error: any) {
      console.error('Orchestrate Error:', error);

      if (error instanceof functions.https.HttpsError) {
        return res.status(401).json({ error: error.message });
      }

      return res.status(500).json({
        error: error?.message || 'Internal server error',
      });
    }
  });
});
