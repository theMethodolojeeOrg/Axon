//
//  ConversationSyncManager.swift
//  Axon
//
//  Manages conversation synchronization between Core Data (local) and API (remote)
//  Implements delta sync for efficient data transfer
//

import Foundation
import CoreData
import Combine

@MainActor
class ConversationSyncManager: ObservableObject {
    static let shared = ConversationSyncManager()

    private let persistence = PersistenceController.shared
    private let apiClient = APIClient.shared
    private let userDefaults = UserDefaults.standard

    // Sync state
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?

    private let lastSyncTimestampKey = "lastConversationSyncTimestamp"
    private let syncMode = "conversation_sync_mode"

    private init() {
        // Load last sync time
        if let timestamp = userDefaults.object(forKey: lastSyncTimestampKey) as? Double {
            lastSyncTime = Date(timeIntervalSince1970: timestamp / 1000)
        }
    }

    // MARK: - Public API

    /// Load conversations from local Core Data (instant)
    /// Excludes soft-deleted (syncStatus == "deleted") and archived conversations
    func loadLocalConversations() -> [Conversation] {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        // CRITICAL: Filter out soft-deleted AND archived conversations
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "archived == %@", NSNumber(value: false)),
            NSPredicate(format: "syncStatus != %@", "deleted")
        ])

        do {
            let entities = try context.fetch(fetchRequest)
            return entities.compactMap { entity in
                return entity.toConversation()
            }
        } catch {
            print("[ConversationSyncManager] Error loading local conversations: \(error)")
            return []
        }
    }

    /// Sync conversations with the server (full or delta based on last sync)
    func syncConversations() async throws {
        // Check if backend is configured before attempting sync
        guard apiClient.isBackendConfigured else {
            print("[ConversationSyncManager] No backend configured, skipping sync")
            return
        }

        guard !isSyncing else {
            print("[ConversationSyncManager] Sync already in progress")
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        let lastSyncTimestamp = userDefaults.object(forKey: lastSyncTimestampKey) as? Double

        if lastSyncTimestamp == nil {
            // First sync - fetch all conversations
            try await performFullSync()
        } else {
            // Delta sync - fetch only changes since last sync
            try await performDeltaSync(since: lastSyncTimestamp!)
        }
    }

    /// Force full sync, ignoring last sync timestamp (for pull-to-refresh)
    func forceFullSync() async throws {
        // Check if backend is configured before attempting sync
        guard apiClient.isBackendConfigured else {
            print("[ConversationSyncManager] No backend configured, skipping force sync")
            return
        }

        guard !isSyncing else {
            print("[ConversationSyncManager] Sync already in progress")
            return
        }

        print("[ConversationSyncManager] 🔄 Force full sync requested - clearing local data first")
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // Clear Core Data to ensure fresh sync
        try await clearAllLocalData()

        // Reset sync timestamp to force full sync
        userDefaults.removeObject(forKey: lastSyncTimestampKey)
        lastSyncTime = nil

        try await performFullSync()
    }
    
    /// Clear all conversations and messages from Core Data
    private func clearAllLocalData() async throws {
        print("[ConversationSyncManager] 🗑️ Clearing all local conversations and messages...")
        let context = persistence.newBackgroundContext()
        
        try await context.perform {
            // Delete all conversations
            let conversationFetch: NSFetchRequest<NSFetchRequestResult> = ConversationEntity.fetchRequest()
            let conversationDelete = NSBatchDeleteRequest(fetchRequest: conversationFetch)
            try context.execute(conversationDelete)
            
            // Delete all messages
            let messageFetch: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
            let messageDelete = NSBatchDeleteRequest(fetchRequest: messageFetch)
            try context.execute(messageDelete)
            
            try self.persistence.saveContext(context)
            print("[ConversationSyncManager] ✅ Local data cleared successfully")
        }
    }

    // MARK: - Full Sync (First Launch)

    private func performFullSync() async throws {
        print("[ConversationSyncManager] ⚡ Performing FULL sync (listAll=true)")
        print("[ConversationSyncManager] This will fetch ALL conversations with messages from server")

        struct ConversationWithMessages: Decodable {
            let id: String
            let userId: String?
            let title: String
            let projectId: String
            let createdAt: Double
            let updatedAt: Double
            let messageCount: Int
            let lastMessageAt: Double?
            let archived: Bool
            let summary: String?
            let lastMessage: String?
            let tags: [String]?
            let isPinned: Bool?
            let messages: [Message]?  // ← Messages included in full sync
        }

        struct ListAllResponse: Decodable {
            let conversations: [ConversationWithMessages]
            let sync: SyncMetadata
            let pagination: PaginationMeta?
            let metadata: AnyCodable?
        }

        struct SyncMetadata: Decodable {
            let mode: String
            let timestamp: Double
            let conversationsUpdated: Int
            let conversationsDeleted: Int
            let messagesIncluded: Bool?
            let totalMessagesIncluded: Int?
        }

        do {
            let response: ListAllResponse = try await apiClient.request(
                endpoint: "/apiListConversations?projectId=default&listAll=true&archived=false",
                method: .get
            )

            print("[ConversationSyncManager] ✅ Full sync fetched \(response.conversations.count) conversations")
            print("[ConversationSyncManager] Sync mode: \(response.sync.mode)")
            print("[ConversationSyncManager] Messages included: \(response.sync.messagesIncluded ?? false)")
            
            if let totalMessages = response.sync.totalMessagesIncluded {
                print("[ConversationSyncManager] 📨 Total messages in response: \(totalMessages)")
            } else {
                print("[ConversationSyncManager] ⚠️ WARNING: No message count in response!")
            }

            // Convert to Conversation models
            let conversations: [Conversation] = response.conversations.map { conv in
                Conversation(
                    id: conv.id,
                    userId: conv.userId,
                    title: conv.title,
                    projectId: conv.projectId,
                    createdAt: Date(timeIntervalSince1970: conv.createdAt / 1000),
                    updatedAt: Date(timeIntervalSince1970: conv.updatedAt / 1000),
                    messageCount: conv.messageCount,
                    lastMessageAt: conv.lastMessageAt.map { Date(timeIntervalSince1970: $0 / 1000) },
                    archived: conv.archived,
                    summary: conv.summary,
                    lastMessage: conv.lastMessage,
                    tags: conv.tags,
                    isPinned: conv.isPinned
                )
            }

            // Save all conversations to Core Data
            try await saveConversationsToCoreData(conversations)

            // Save messages if included
            if response.sync.messagesIncluded == true {
                print("[ConversationSyncManager] 💾 Saving messages to Core Data...")
                var totalMessagesSaved = 0
                var conversationsWithMessages = 0
                
                for convWithMessages in response.conversations {
                    if let messages = convWithMessages.messages, !messages.isEmpty {
                        print("[ConversationSyncManager]   - Conversation '\(convWithMessages.title)': \(messages.count) messages")
                        try await saveMessagesToCoreData(messages, conversationId: convWithMessages.id)
                        totalMessagesSaved += messages.count
                        conversationsWithMessages += 1
                    }
                }
                print("[ConversationSyncManager] ✅ Saved \(totalMessagesSaved) messages from \(conversationsWithMessages) conversations to Core Data")
            } else {
                print("[ConversationSyncManager] ⚠️ WARNING: Messages were NOT included in sync response!")
                print("[ConversationSyncManager] This means messages will need to be fetched individually per conversation")
            }

            // Store server timestamp for future delta syncs
            userDefaults.set(response.sync.timestamp, forKey: lastSyncTimestampKey)
            lastSyncTime = Date(timeIntervalSince1970: response.sync.timestamp / 1000)

            print("[ConversationSyncManager] ✅ Full sync completed successfully!")
            print("[ConversationSyncManager] Server timestamp: \(response.sync.timestamp)")
        } catch {
            syncError = error.localizedDescription
            print("[ConversationSyncManager] ❌ Full sync FAILED: \(error)")
            if let urlError = error as? URLError {
                print("[ConversationSyncManager] URL Error code: \(urlError.code.rawValue)")
            }
            throw error
        }
    }

    // MARK: - Delta Sync (Subsequent Launches)

    private func performDeltaSync(since timestamp: Double) async throws {
        print("[ConversationSyncManager] Performing delta sync (updatedSince=\(timestamp))")

        struct DeltaSyncResponse: Decodable {
            let conversations: [Conversation]
            let deletedConversations: [String]?
            let sync: SyncMetadata
            let pagination: PaginationMeta?
            let metadata: AnyCodable?
        }

        struct SyncMetadata: Decodable {
            let mode: String
            let timestamp: Double
            let updatedSince: Double?
            let conversationsUpdated: Int
            let conversationsDeleted: Int
        }

        do {
            let response: DeltaSyncResponse = try await apiClient.request(
                endpoint: "/apiListConversations?projectId=default&updatedSince=\(Int(timestamp))&archived=false",
                method: .get
            )

            print("[ConversationSyncManager] Delta sync: \(response.conversations.count) updated, \(response.deletedConversations?.count ?? 0) deleted")

            // Process updates
            if !response.conversations.isEmpty {
                try await saveConversationsToCoreData(response.conversations)
            }

            // Process deletions (tombstones)
            if let deletedIds = response.deletedConversations, !deletedIds.isEmpty {
                try await deleteConversationsFromCoreData(ids: deletedIds)
            }

            // Update last sync timestamp ONLY after successful completion
            userDefaults.set(response.sync.timestamp, forKey: lastSyncTimestampKey)
            lastSyncTime = Date(timeIntervalSince1970: response.sync.timestamp / 1000)

            print("[ConversationSyncManager] ✅ Delta sync completed. Server timestamp: \(response.sync.timestamp)")
        } catch {
            syncError = error.localizedDescription
            print("[ConversationSyncManager] ❌ Delta sync failed: \(error)")
            throw error
        }
    }

    // MARK: - Core Data Operations

    func saveConversationsToCoreData(_ conversations: [Conversation]) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            var savedCount = 0
            var skippedCount = 0

            for conversation in conversations {
                let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", conversation.id)

                let entity: ConversationEntity
                if let existing = try context.fetch(fetchRequest).first {
                    // CRITICAL: Don't overwrite soft-deleted conversations
                    // This prevents resurrection during sync
                    if existing.syncStatus == "deleted" {
                        print("[ConversationSyncManager] ⚠️ Skipping soft-deleted conversation: \(conversation.id)")
                        skippedCount += 1
                        continue
                    }
                    // Update existing
                    entity = existing
                } else {
                    // Create new
                    entity = ConversationEntity(context: context)
                }

                // Populate entity from conversation
                entity.id = conversation.id
                entity.userId = conversation.userId
                entity.title = conversation.title
                entity.projectId = conversation.projectId
                entity.createdAt = conversation.createdAt
                entity.updatedAt = conversation.updatedAt
                entity.messageCount = Int32(conversation.messageCount)
                entity.lastMessageAt = conversation.lastMessageAt
                entity.archived = conversation.archived
                entity.summary = conversation.summary
                entity.lastMessage = conversation.lastMessage
                entity.tags = conversation.tags as NSArray?
                entity.isPinned = conversation.isPinned ?? false
                entity.syncStatus = "synced"
                entity.locallyModified = false
                savedCount += 1
            }

            try self.persistence.saveContext(context)
            if skippedCount > 0 {
                print("[ConversationSyncManager] Saved \(savedCount) conversations, skipped \(skippedCount) soft-deleted")
            } else {
                print("[ConversationSyncManager] Saved \(savedCount) conversations to Core Data")
            }
        }
    }

    private func deleteConversationsFromCoreData(ids: [String]) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            let entities = try context.fetch(fetchRequest)
            for entity in entities {
                context.delete(entity)
            }

            try self.persistence.saveContext(context)
            print("[ConversationSyncManager] Deleted \(entities.count) conversations from Core Data")
        }
    }

    /// Clean up old soft-deleted conversation tombstones (call periodically)
    func cleanupOldTombstones(olderThan days: Int = 7) async throws {
        let context = persistence.newBackgroundContext()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        try await context.perform {
            // Find old conversation tombstones
            let convFetch: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
            convFetch.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "syncStatus == %@", "deleted"),
                NSPredicate(format: "updatedAt < %@", cutoffDate as NSDate)
            ])

            let convEntities = try context.fetch(convFetch)
            var deletedConvIds: [String] = []

            for entity in convEntities {
                if let id = entity.id {
                    deletedConvIds.append(id)
                }
                context.delete(entity)
            }

            // Also delete messages for those conversations
            if !deletedConvIds.isEmpty {
                let msgFetch: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
                msgFetch.predicate = NSPredicate(format: "conversationId IN %@", deletedConvIds)

                let msgEntities = try context.fetch(msgFetch)
                for entity in msgEntities {
                    context.delete(entity)
                }
            }

            if !convEntities.isEmpty {
                try self.persistence.saveContext(context)
                print("[ConversationSyncManager] Cleaned up \(convEntities.count) old conversation tombstones")
            }
        }
    }

    func saveMessagesToCoreData(_ messages: [Message], conversationId: String) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            for message in messages {
                let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", message.id)

                let entity: MessageEntity
                if let existing = try context.fetch(fetchRequest).first {
                    // Update existing
                    entity = existing
                } else {
                    // Create new
                    entity = MessageEntity(context: context)
                }

                // Populate entity from message
                entity.id = message.id
                entity.conversationId = conversationId
                entity.role = message.role.rawValue
                entity.content = message.content
                entity.timestamp = message.timestamp
                entity.modelName = message.modelName
                entity.providerName = message.providerName
                if let tokens = message.tokens {
                    entity.tokensUsed = Int32(tokens.total)
                }

                // Serialize attachments to JSON if present
                if let attachments = message.attachments, !attachments.isEmpty {
                    if let attachmentsData = try? JSONEncoder().encode(attachments),
                       let attachmentsJSON = String(data: attachmentsData, encoding: .utf8) {
                        entity.attachmentsJSON = attachmentsJSON
                    }
                } else {
                    entity.attachmentsJSON = nil
                }

                // Serialize grounding sources to JSON if present
                if let groundingSources = message.groundingSources, !groundingSources.isEmpty {
                    if let data = try? JSONEncoder().encode(groundingSources),
                       let json = String(data: data, encoding: .utf8) {
                        entity.groundingSourcesJSON = json
                    }
                } else {
                    entity.groundingSourcesJSON = nil
                }

                // Serialize memory operations to JSON if present
                if let memoryOperations = message.memoryOperations, !memoryOperations.isEmpty {
                    if let data = try? JSONEncoder().encode(memoryOperations),
                       let json = String(data: data, encoding: .utf8) {
                        entity.memoryOperationsJSON = json
                    }
                } else {
                    entity.memoryOperationsJSON = nil
                }
            }

            try self.persistence.saveContext(context)
        }
    }

    /// Load messages for a conversation from Core Data
    func loadLocalMessages(conversationId: String) -> [Message] {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "conversationId == %@", conversationId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        do {
            let entities = try context.fetch(fetchRequest)
            return entities.compactMap { entity in
                guard let id = entity.id,
                      let conversationId = entity.conversationId,
                      let roleString = entity.role,
                      let role = MessageRole(rawValue: roleString),
                      let content = entity.content,
                      let timestamp = entity.timestamp else {
                    return nil
                }

                // Deserialize attachments from JSON if present
                var attachments: [MessageAttachment]? = nil
                if let attachmentsJSON = entity.attachmentsJSON,
                   let attachmentsData = attachmentsJSON.data(using: .utf8) {
                    attachments = try? JSONDecoder().decode([MessageAttachment].self, from: attachmentsData)
                }

                // Deserialize grounding sources from JSON if present
                var groundingSources: [MessageGroundingSource]? = nil
                if let json = entity.groundingSourcesJSON,
                   let data = json.data(using: .utf8) {
                    groundingSources = try? JSONDecoder().decode([MessageGroundingSource].self, from: data)
                }

                // Deserialize memory operations from JSON if present
                var memoryOperations: [MessageMemoryOperation]? = nil
                if let json = entity.memoryOperationsJSON,
                   let data = json.data(using: .utf8) {
                    memoryOperations = try? JSONDecoder().decode([MessageMemoryOperation].self, from: data)
                }

                return Message(
                    id: id,
                    conversationId: conversationId,
                    role: role,
                    content: content,
                    timestamp: timestamp,
                    tokens: nil,
                    artifacts: nil,
                    toolCalls: nil,
                    isStreaming: nil,
                    modelName: entity.modelName,
                    providerName: entity.providerName,
                    attachments: attachments,
                    groundingSources: groundingSources,
                    memoryOperations: memoryOperations
                )
            }
        } catch {
            print("[ConversationSyncManager] Error loading local messages: \(error)")
            return []
        }
    }
}

// MARK: - ConversationEntity Extension

extension ConversationEntity {
    func toConversation() -> Conversation? {
        guard let id = self.id,
              let title = self.title,
              let projectId = self.projectId,
              let createdAt = self.createdAt,
              let updatedAt = self.updatedAt else {
            return nil
        }

        return Conversation(
            id: id,
            userId: self.userId,
            title: title,
            projectId: projectId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: Int(self.messageCount),
            lastMessageAt: self.lastMessageAt,
            archived: self.archived,
            summary: self.summary,
            lastMessage: self.lastMessage,
            tags: self.tags as? [String],
            isPinned: self.isPinned ? true : nil
        )
    }
}

