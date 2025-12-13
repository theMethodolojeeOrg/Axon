//
//  LocalConversationStore.swift
//  Axon
//
//  Offline-first conversation storage with sync queue
//  Enables fully local operation with background sync when connected
//

import Foundation
import CoreData
import Combine

// MARK: - Sync Status

enum SyncStatus: String {
    case synced = "synced"
    case pending = "pending"
    case failed = "failed"
    case conflict = "conflict"
    case deleted = "deleted"  // Soft-delete tombstone - prevents resurrection during sync
}

// MARK: - Pending Operation

struct PendingOperation: Codable, Identifiable {
    let id: String
    let type: OperationType
    let entityType: EntityType
    let entityId: String
    let payload: Data?
    let createdAt: Date
    var retryCount: Int
    var lastError: String?

    enum OperationType: String, Codable {
        case create
        case update
        case delete
    }

    enum EntityType: String, Codable {
        case conversation
        case message
    }

    init(type: OperationType, entityType: EntityType, entityId: String, payload: Data? = nil) {
        self.id = UUID().uuidString
        self.type = type
        self.entityType = entityType
        self.entityId = entityId
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
        self.lastError = nil
    }
}

// MARK: - Local Conversation Store

@MainActor
class LocalConversationStore: ObservableObject {
    static let shared = LocalConversationStore()

    private let persistence = PersistenceController.shared
    private let apiClient = APIClient.shared
    private let defaults = UserDefaults.standard

    // Sync queue
    @Published var pendingOperations: [PendingOperation] = []
    @Published var isSyncing = false
    @Published var lastSyncError: String?

    private let pendingOpsKey = "LocalConversationStore.pendingOperations"
    private let maxRetries = 3

    private init() {
        loadPendingOperations()
    }

    // MARK: - Offline Conversation Creation

    /// Create a conversation locally (no API required)
    /// Returns immediately with a local conversation that will sync later
    func createLocalConversation(title: String, projectId: String = "default") throws -> Conversation {
        let context = persistence.container.viewContext

        // Generate a local ID (will be replaced by server ID on sync)
        let localId = "local_\(UUID().uuidString)"
        let now = Date()

        // Create Core Data entity
        let entity = ConversationEntity(context: context)
        entity.id = localId
        entity.title = title
        entity.projectId = projectId
        entity.createdAt = now
        entity.updatedAt = now
        entity.messageCount = 0
        entity.archived = false
        entity.syncStatus = SyncStatus.pending.rawValue
        entity.locallyModified = true

        try persistence.saveContext(context)

        // Create the conversation model
        let conversation = Conversation(
            id: localId,
            userId: nil,
            title: title,
            projectId: projectId,
            createdAt: now,
            updatedAt: now,
            messageCount: 0,
            lastMessageAt: nil,
            archived: false
        )

        // Queue for sync
        let operation = PendingOperation(
            type: .create,
            entityType: .conversation,
            entityId: localId,
            payload: try? JSONEncoder().encode(conversation)
        )
        addPendingOperation(operation)

        print("[LocalConversationStore] Created local conversation: \(localId)")
        return conversation
    }

    /// Save a message locally (no API required)
    func saveLocalMessage(_ message: Message, conversationId: String) throws {
        let context = persistence.container.viewContext

        // Create or update message entity
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", message.id)

        let entity: MessageEntity
        if let existing = try context.fetch(fetchRequest).first {
            entity = existing
        } else {
            entity = MessageEntity(context: context)
        }

        entity.id = message.id
        entity.conversationId = conversationId
        entity.role = message.role.rawValue
        entity.content = message.content
        entity.timestamp = message.timestamp
        entity.modelName = message.modelName
        entity.providerName = message.providerName

        if let attachments = message.attachments, !attachments.isEmpty {
            if let data = try? JSONEncoder().encode(attachments),
               let json = String(data: data, encoding: .utf8) {
                entity.attachmentsJSON = json
            }
        }

        // Serialize grounding sources to JSON if present
        if let groundingSources = message.groundingSources, !groundingSources.isEmpty {
            if let data = try? JSONEncoder().encode(groundingSources),
               let json = String(data: data, encoding: .utf8) {
                entity.groundingSourcesJSON = json
            }
        }

        // Serialize memory operations to JSON if present
        if let memoryOperations = message.memoryOperations, !memoryOperations.isEmpty {
            if let data = try? JSONEncoder().encode(memoryOperations),
               let json = String(data: data, encoding: .utf8) {
                entity.memoryOperationsJSON = json
            }
        }

        // Update conversation message count
        let convFetch: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        convFetch.predicate = NSPredicate(format: "id == %@", conversationId)
        if let convEntity = try context.fetch(convFetch).first {
            convEntity.messageCount += 1
            convEntity.lastMessageAt = message.timestamp
            convEntity.lastMessage = String(message.content.prefix(100))
            convEntity.updatedAt = Date()
            convEntity.locallyModified = true
        }

        try persistence.saveContext(context)
        print("[LocalConversationStore] Saved local message: \(message.id)")
    }

    /// Update a conversation locally
    func updateLocalConversation(id: String, title: String) throws {
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)

        guard let entity = try context.fetch(fetchRequest).first else {
            throw LocalStoreError.notFound
        }

        entity.title = title
        entity.updatedAt = Date()
        entity.locallyModified = true

        // Only queue for sync if it's a synced conversation (not local-only)
        if !id.hasPrefix("local_") {
            entity.syncStatus = SyncStatus.pending.rawValue

            let operation = PendingOperation(
                type: .update,
                entityType: .conversation,
                entityId: id,
                payload: try? JSONEncoder().encode(["title": title])
            )
            addPendingOperation(operation)
        }

        try persistence.saveContext(context)
        print("[LocalConversationStore] Updated local conversation: \(id)")
    }

    /// Delete a conversation locally (uses soft-delete to prevent resurrection)
    func deleteLocalConversation(id: String) throws {
        let context = persistence.container.viewContext

        // For local-only conversations, hard delete immediately
        if id.hasPrefix("local_") {
            let convFetch: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
            convFetch.predicate = NSPredicate(format: "id == %@", id)

            if let entity = try context.fetch(convFetch).first {
                context.delete(entity)
            }

            // Delete associated messages
            let msgFetch: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
            msgFetch.predicate = NSPredicate(format: "conversationId == %@", id)

            let messages = try context.fetch(msgFetch)
            for msg in messages {
                context.delete(msg)
            }

            try persistence.saveContext(context)

            // Remove any pending create operations for this local conversation
            pendingOperations.removeAll { $0.entityId == id }
            savePendingOperations()

            print("[LocalConversationStore] Hard deleted local-only conversation: \(id)")
            return
        }

        // For synced conversations, use soft-delete (tombstone pattern)
        // This prevents resurrection during sync until server confirms deletion
        let convFetch: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        convFetch.predicate = NSPredicate(format: "id == %@", id)

        if let entity = try context.fetch(convFetch).first {
            entity.syncStatus = SyncStatus.deleted.rawValue
            entity.updatedAt = Date()
            print("[LocalConversationStore] Soft-deleted conversation (tombstone): \(id)")
        }

        try persistence.saveContext(context)

        // Queue the API deletion
        let operation = PendingOperation(
            type: .delete,
            entityType: .conversation,
            entityId: id
        )
        addPendingOperation(operation)

        print("[LocalConversationStore] Queued delete operation for conversation: \(id)")
    }

    /// Hard delete a conversation after server confirms deletion
    func hardDeleteLocalConversation(id: String) throws {
        let context = persistence.container.viewContext

        // Delete conversation
        let convFetch: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        convFetch.predicate = NSPredicate(format: "id == %@", id)

        if let entity = try context.fetch(convFetch).first {
            context.delete(entity)
        }

        // Delete associated messages
        let msgFetch: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        msgFetch.predicate = NSPredicate(format: "conversationId == %@", id)

        let messages = try context.fetch(msgFetch)
        for msg in messages {
            context.delete(msg)
        }

        try persistence.saveContext(context)
        print("[LocalConversationStore] Hard deleted conversation after server confirmation: \(id)")
    }

    // MARK: - Load Local Data

    /// Load all local conversations (excludes soft-deleted and archived)
    func loadConversations() -> [Conversation] {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        // CRITICAL: Filter out soft-deleted (syncStatus == "deleted") AND archived conversations
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "archived == %@", NSNumber(value: false)),
            NSPredicate(format: "syncStatus != %@", SyncStatus.deleted.rawValue)
        ])

        do {
            let entities = try context.fetch(fetchRequest)
            return entities.compactMap { $0.toConversation() }
        } catch {
            print("[LocalConversationStore] Error loading conversations: \(error)")
            return []
        }
    }

    /// Load messages for a conversation
    func loadMessages(conversationId: String) -> [Message] {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "conversationId == %@", conversationId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        do {
            let entities = try context.fetch(fetchRequest)
            return entities.compactMap { entity -> Message? in
                guard let id = entity.id,
                      let conversationId = entity.conversationId,
                      let roleString = entity.role,
                      let role = MessageRole(rawValue: roleString),
                      let content = entity.content,
                      let timestamp = entity.timestamp else {
                    return nil
                }

                var attachments: [MessageAttachment]? = nil
                if let json = entity.attachmentsJSON,
                   let data = json.data(using: .utf8) {
                    attachments = try? JSONDecoder().decode([MessageAttachment].self, from: data)
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
            print("[LocalConversationStore] Error loading messages: \(error)")
            return []
        }
    }

    // MARK: - Sync Queue Management

    private func addPendingOperation(_ operation: PendingOperation) {
        pendingOperations.append(operation)
        savePendingOperations()
    }

    private func loadPendingOperations() {
        guard let data = defaults.data(forKey: pendingOpsKey),
              let ops = try? JSONDecoder().decode([PendingOperation].self, from: data) else {
            pendingOperations = []
            return
        }
        pendingOperations = ops
        print("[LocalConversationStore] Loaded \(ops.count) pending operations")
    }

    private func savePendingOperations() {
        if let data = try? JSONEncoder().encode(pendingOperations) {
            defaults.set(data, forKey: pendingOpsKey)
        }
    }

    // MARK: - Sync Execution

    /// Process all pending operations
    func processPendingOperations() async {
        // Check if backend is configured before attempting to sync pending operations
        guard apiClient.isBackendConfigured else {
            print("[LocalConversationStore] No backend configured, keeping \(pendingOperations.count) operations pending")
            return
        }

        guard !isSyncing else {
            print("[LocalConversationStore] Sync already in progress")
            return
        }

        guard !pendingOperations.isEmpty else {
            print("[LocalConversationStore] No pending operations")
            return
        }

        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        print("[LocalConversationStore] Processing \(pendingOperations.count) pending operations")

        var completedIds: [String] = []
        var failedOps: [PendingOperation] = []

        for operation in pendingOperations {
            do {
                try await executeOperation(operation)
                completedIds.append(operation.id)
                print("[LocalConversationStore] Completed operation: \(operation.type) \(operation.entityType) \(operation.entityId)")
            } catch {
                print("[LocalConversationStore] Failed operation: \(error)")
                var failedOp = operation
                failedOp.retryCount += 1
                failedOp.lastError = error.localizedDescription

                if failedOp.retryCount < maxRetries {
                    failedOps.append(failedOp)
                } else {
                    print("[LocalConversationStore] Operation exceeded max retries, dropping: \(operation.id)")
                    // Update entity status to failed
                    await markEntityAsFailed(operation)
                }
            }
        }

        // Update pending operations
        pendingOperations = failedOps
        savePendingOperations()

        if !completedIds.isEmpty {
            print("[LocalConversationStore] Sync completed: \(completedIds.count) operations succeeded")
        }
    }

    private func executeOperation(_ operation: PendingOperation) async throws {
        switch (operation.type, operation.entityType) {
        case (.create, .conversation):
            try await syncCreateConversation(operation)
        case (.update, .conversation):
            try await syncUpdateConversation(operation)
        case (.delete, .conversation):
            try await syncDeleteConversation(operation)
        case (.create, .message), (.update, .message), (.delete, .message):
            // Messages are synced as part of conversation operations for now
            break
        }
    }

    private func syncCreateConversation(_ operation: PendingOperation) async throws {
        guard let payload = operation.payload,
              let conversation = try? JSONDecoder().decode(Conversation.self, from: payload) else {
            throw LocalStoreError.invalidPayload
        }

        struct CreateRequest: Encodable {
            let title: String
            let projectId: String
        }

        struct CreateResponse: Decodable {
            let conversation: Conversation
            let message: String?
        }

        let request = CreateRequest(title: conversation.title, projectId: conversation.projectId)

        let response: CreateResponse = try await apiClient.request(
            endpoint: "/apiCreateConversation",
            method: .post,
            body: request
        )

        // Update local entity with server ID
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", operation.entityId)

        if let entity = try context.fetch(fetchRequest).first {
            // Update messages to use new conversation ID
            let msgFetch: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
            msgFetch.predicate = NSPredicate(format: "conversationId == %@", operation.entityId)
            let messages = try context.fetch(msgFetch)
            for msg in messages {
                msg.conversationId = response.conversation.id
            }

            // Update conversation with server data
            entity.id = response.conversation.id
            entity.userId = response.conversation.userId
            entity.syncStatus = SyncStatus.synced.rawValue
            entity.locallyModified = false

            try persistence.saveContext(context)
        }

        print("[LocalConversationStore] Synced local conversation \(operation.entityId) -> \(response.conversation.id)")
    }

    private func syncUpdateConversation(_ operation: PendingOperation) async throws {
        guard let payload = operation.payload,
              let updates = try? JSONDecoder().decode([String: String].self, from: payload),
              let title = updates["title"] else {
            throw LocalStoreError.invalidPayload
        }

        struct UpdateRequest: Encodable {
            let title: String
        }

        struct UpdateResponse: Decodable {
            let conversation: Conversation
            let message: String?
        }

        let request = UpdateRequest(title: title)

        let _: UpdateResponse = try await apiClient.request(
            endpoint: "/apiUpdateConversation/\(operation.entityId)",
            method: .patch,
            body: request
        )

        // Mark as synced
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", operation.entityId)

        if let entity = try context.fetch(fetchRequest).first {
            entity.syncStatus = SyncStatus.synced.rawValue
            entity.locallyModified = false
            try persistence.saveContext(context)
        }
    }

    private func syncDeleteConversation(_ operation: PendingOperation) async throws {
        struct DeleteResponse: Decodable {
            let message: String
            let hardDelete: Bool?
        }

        let _: DeleteResponse = try await apiClient.request(
            endpoint: "/apiDeleteConversation/\(operation.entityId)?hardDelete=true",
            method: .delete
        )

        // Server confirmed deletion - now hard delete locally
        try hardDeleteLocalConversation(id: operation.entityId)
        print("[LocalConversationStore] ✅ Server confirmed deletion, hard-deleted locally: \(operation.entityId)")
    }

    private func markEntityAsFailed(_ operation: PendingOperation) async {
        let context = persistence.container.viewContext

        switch operation.entityType {
        case .conversation:
            let fetchRequest: NSFetchRequest<ConversationEntity> = ConversationEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", operation.entityId)
            if let entity = try? context.fetch(fetchRequest).first {
                entity.syncStatus = SyncStatus.failed.rawValue
                try? persistence.saveContext(context)
            }
        case .message:
            break
        }
    }

    // MARK: - Utility

    /// Check if there are pending operations
    var hasPendingOperations: Bool {
        !pendingOperations.isEmpty
    }

    /// Get count of pending operations
    var pendingOperationCount: Int {
        pendingOperations.count
    }

    /// Clear all pending operations (use with caution)
    func clearPendingOperations() {
        pendingOperations = []
        savePendingOperations()
    }
}

// MARK: - Errors

enum LocalStoreError: LocalizedError {
    case notFound
    case invalidPayload
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Entity not found"
        case .invalidPayload:
            return "Invalid operation payload"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        }
    }
}
