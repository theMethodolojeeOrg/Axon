//
//  CloudKitSyncService.swift
//  Axon
//
//  iCloud/CloudKit sync service for cross-device synchronization
//  Provides Apple-native sync without requiring external servers
//

import Foundation
import CloudKit
import CoreData
import Combine

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    // CloudKit containers
    private let container: CKContainer
    private let privateDatabase: CKDatabase

    // Record types
    private let conversationRecordType = "Conversation"
    private let messageRecordType = "Message"
    private let memoryRecordType = "Memory"

    // Local store access
    private let persistence = PersistenceController.shared

    // Sync state
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?
    @Published var isCloudKitAvailable = false

    // Zone for private data
    private let zoneID = CKRecordZone.ID(zoneName: "AxonData", ownerName: CKCurrentUserDefaultName)
    private var zoneCreated = false

    // Subscription for push notifications
    private var subscriptionSaved = false

    // Used for lightweight “I pulled something” UI refresh triggers.
    let didCompletePull = PassthroughSubject<Void, Never>()

    private init() {
        // Use the specific container matching entitlements
        // Container ID must match com.apple.developer.icloud-container-identifiers in Axon.entitlements
        self.container = CKContainer(identifier: "iCloud.NeurXAxon")
        self.privateDatabase = container.privateCloudDatabase

        // Check availability on init
        Task {
            await checkCloudKitAvailability()
        }
    }

    // MARK: - Availability Check

    func checkCloudKitAvailability() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                isCloudKitAvailable = true
                syncError = nil
                print("[CloudKitSync] iCloud account available")
            case .noAccount:
                isCloudKitAvailable = false
                syncError = "No iCloud account. Sign in to iCloud in Settings."
                print("[CloudKitSync] No iCloud account configured")
            case .restricted:
                isCloudKitAvailable = false
                syncError = "iCloud access is restricted on this device."
                print("[CloudKitSync] iCloud access restricted")
            case .couldNotDetermine:
                isCloudKitAvailable = false
                syncError = "Could not determine iCloud status."
                print("[CloudKitSync] Could not determine iCloud status")
            case .temporarilyUnavailable:
                isCloudKitAvailable = false
                syncError = "iCloud is temporarily unavailable."
                print("[CloudKitSync] iCloud temporarily unavailable")
            @unknown default:
                isCloudKitAvailable = false
                syncError = "Unknown iCloud status."
            }
        } catch let error as CKError {
            isCloudKitAvailable = false
            // Handle specific CloudKit errors
            switch error.code {
            case .notAuthenticated:
                syncError = "Not signed in to iCloud. Check Settings > Apple ID > iCloud."
            case .networkFailure, .networkUnavailable:
                syncError = "Network unavailable. Check your connection."
            case .quotaExceeded:
                syncError = "iCloud storage is full."
            default:
                syncError = "CloudKit error: \(error.localizedDescription)"
            }
            print("[CloudKitSync] CloudKit error: \(error)")
        } catch {
            isCloudKitAvailable = false
            // Check for entitlement errors
            let errorString = String(describing: error)
            if errorString.contains("entitlement") {
                syncError = "CloudKit entitlements not configured. Please set up iCloud capability in Xcode."
                print("[CloudKitSync] Entitlement error - CloudKit container needs to be created in Apple Developer Portal")
            } else {
                syncError = "Error checking iCloud: \(error.localizedDescription)"
            }
            print("[CloudKitSync] Error checking iCloud status: \(error)")
        }
    }

    // MARK: - Zone Setup

    private func ensureZoneExists() async throws {
        guard !zoneCreated else { return }

        let zone = CKRecordZone(zoneID: zoneID)

        do {
            _ = try await privateDatabase.save(zone)
            zoneCreated = true
            print("[CloudKitSync] Created custom zone: \(zoneID.zoneName)")
        } catch let error as CKError {
            // Zone might already exist
            if error.code == .serverRecordChanged || error.code == .zoneNotFound {
                // Try to fetch existing zone
                let zones = try await privateDatabase.allRecordZones()
                if zones.contains(where: { $0.zoneID == zoneID }) {
                    zoneCreated = true
                    print("[CloudKitSync] Zone already exists: \(zoneID.zoneName)")
                } else {
                    throw error
                }
            } else {
                throw error
            }
        }
    }

    // MARK: - Sync Conversations

    /// Sync all conversations to iCloud
    func syncConversations(_ conversations: [Conversation]) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        try await ensureZoneExists()

        // Convert conversations to CKRecords
        var records: [CKRecord] = []
        for conversation in conversations {
            let record = conversationToRecord(conversation)
            records.append(record)
        }

        // Batch save
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("[CloudKitSync] Synced \(records.count) conversations to iCloud")
                    continuation.resume()
                case .failure(let error):
                    print("[CloudKitSync] Failed to sync conversations: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            privateDatabase.add(operation)
        }

        lastSyncTime = Date()
    }

    /// Fetch conversations from iCloud
    func fetchConversations() async throws -> [Conversation] {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        try await ensureZoneExists()

        let query = CKQuery(recordType: conversationRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await privateDatabase.records(matching: query, inZoneWith: zoneID)

        var conversations: [Conversation] = []
        for (_, result) in results.matchResults {
            if case .success(let record) = result {
                if let conversation = recordToConversation(record) {
                    conversations.append(conversation)
                }
            }
        }

        lastSyncTime = Date()
        print("[CloudKitSync] Fetched \(conversations.count) conversations from iCloud")
        return conversations
    }

    // MARK: - Sync Messages

    /// Sync messages for a conversation to iCloud
    func syncMessages(_ messages: [Message], conversationId: String) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        try await ensureZoneExists()

        var records: [CKRecord] = []
        for message in messages {
            let record = messageToRecord(message, conversationId: conversationId)
            records.append(record)
        }

        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("[CloudKitSync] Synced \(records.count) messages to iCloud")
                    continuation.resume()
                case .failure(let error):
                    print("[CloudKitSync] Failed to sync messages: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            privateDatabase.add(operation)
        }
    }

    /// Fetch messages for a conversation from iCloud
    func fetchMessages(conversationId: String) async throws -> [Message] {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        try await ensureZoneExists()

        let predicate = NSPredicate(format: "conversationId == %@", conversationId)
        let query = CKQuery(recordType: messageRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]

        let results = try await privateDatabase.records(matching: query, inZoneWith: zoneID)

        var messages: [Message] = []
        for (_, result) in results.matchResults {
            if case .success(let record) = result {
                if let message = recordToMessage(record) {
                    messages.append(message)
                }
            }
        }

        print("[CloudKitSync] Fetched \(messages.count) messages from iCloud for conversation \(conversationId)")
        return messages
    }

    // MARK: - Delete Operations

    /// Delete a conversation from iCloud
    func deleteConversation(id: String) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        try await ensureZoneExists()

        let recordID = CKRecord.ID(recordName: "conv_\(id)", zoneID: zoneID)

        try await privateDatabase.deleteRecord(withID: recordID)
        print("[CloudKitSync] Deleted conversation \(id) from iCloud")
    }

    // MARK: - Record Conversion

    private func conversationToRecord(_ conversation: Conversation) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "conv_\(conversation.id)", zoneID: zoneID)
        let record = CKRecord(recordType: conversationRecordType, recordID: recordID)

        record["id"] = conversation.id
        record["title"] = conversation.title
        record["projectId"] = conversation.projectId
        record["createdAt"] = conversation.createdAt
        record["updatedAt"] = conversation.updatedAt
        record["messageCount"] = conversation.messageCount
        record["archived"] = conversation.archived
        record["summary"] = conversation.summary
        record["lastMessage"] = conversation.lastMessage

        if let lastMessageAt = conversation.lastMessageAt {
            record["lastMessageAt"] = lastMessageAt
        }

        if let tags = conversation.tags {
            record["tags"] = tags
        }

        record["isPinned"] = conversation.isPinned ?? false

        return record
    }

    private func recordToConversation(_ record: CKRecord) -> Conversation? {
        guard let id = record["id"] as? String,
              let title = record["title"] as? String,
              let projectId = record["projectId"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date,
              let messageCount = record["messageCount"] as? Int,
              let archived = record["archived"] as? Bool else {
            return nil
        }

        return Conversation(
            id: id,
            userId: nil,
            title: title,
            projectId: projectId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            messageCount: messageCount,
            lastMessageAt: record["lastMessageAt"] as? Date,
            archived: archived,
            summary: record["summary"] as? String,
            lastMessage: record["lastMessage"] as? String,
            tags: record["tags"] as? [String],
            isPinned: record["isPinned"] as? Bool
        )
    }

    private func messageToRecord(_ message: Message, conversationId: String) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "msg_\(message.id)", zoneID: zoneID)
        let record = CKRecord(recordType: messageRecordType, recordID: recordID)

        record["id"] = message.id
        record["conversationId"] = conversationId
        record["role"] = message.role.rawValue
        record["content"] = message.content
        record["timestamp"] = message.timestamp
        record["modelName"] = message.modelName
        record["providerName"] = message.providerName

        return record
    }

    private func recordToMessage(_ record: CKRecord) -> Message? {
        guard let id = record["id"] as? String,
              let conversationId = record["conversationId"] as? String,
              let roleString = record["role"] as? String,
              let role = MessageRole(rawValue: roleString),
              let content = record["content"] as? String,
              let timestamp = record["timestamp"] as? Date else {
            return nil
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
            modelName: record["modelName"] as? String,
            providerName: record["providerName"] as? String,
            attachments: nil,
            groundingSources: nil,
            memoryOperations: nil
        )
    }

    // MARK: - Sync Memories

    func syncMemories(_ memories: [Memory]) async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        try await ensureZoneExists()

        let records = memories.map { memoryToRecord($0) }
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    print("[CloudKitSync] Synced \(records.count) memories to iCloud")
                    continuation.resume()
                case .failure(let error):
                    print("[CloudKitSync] Failed to sync memories: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            privateDatabase.add(operation)
        }

        lastSyncTime = Date()
    }

    func fetchMemories() async throws -> [Memory] {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        try await ensureZoneExists()

        let query = CKQuery(recordType: memoryRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await privateDatabase.records(matching: query, inZoneWith: zoneID)

        var memories: [Memory] = []
        for (_, result) in results.matchResults {
            if case .success(let record) = result {
                if let memory = recordToMemory(record) {
                    memories.append(memory)
                }
            }
        }

        lastSyncTime = Date()
        print("[CloudKitSync] Fetched \(memories.count) memories from iCloud")
        return memories
    }

    private func memoryToRecord(_ memory: Memory) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "mem_\(memory.id)", zoneID: zoneID)
        let record = CKRecord(recordType: memoryRecordType, recordID: recordID)

        record["id"] = memory.id
        record["userId"] = memory.userId
        record["content"] = memory.content
        record["type"] = memory.type.rawValue
        record["confidence"] = memory.confidence
        record["tags"] = memory.tags
        record["context"] = memory.context
        record["createdAt"] = memory.createdAt
        record["updatedAt"] = memory.updatedAt
        record["lastAccessedAt"] = memory.lastAccessedAt
        record["accessCount"] = memory.accessCount

        // Source (optional)
        if let source = memory.source {
            record["sourceConversationId"] = source.conversationId
            record["sourceMessageId"] = source.messageId
            record["sourceTimestamp"] = source.timestamp
        }

        // Related memory IDs
        if let related = memory.relatedMemories {
            record["relatedMemories"] = related
        }

        // Metadata: store as JSON string for portability
        if !memory.metadata.isEmpty,
           let data = try? JSONEncoder().encode(memory.metadata),
           let json = String(data: data, encoding: .utf8) {
            record["metadataJSON"] = json
        }

        return record
    }

    private func recordToMemory(_ record: CKRecord) -> Memory? {
        guard let id = record["id"] as? String,
              let content = record["content"] as? String,
              let typeString = record["type"] as? String,
              let type = MemoryType(rawValue: typeString),
              let confidence = record["confidence"] as? Double,
              let tags = record["tags"] as? [String],
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }

        let userId = (record["userId"] as? String) ?? ""
        let context = record["context"] as? String
        let lastAccessedAt = record["lastAccessedAt"] as? Date
        let accessCount = (record["accessCount"] as? Int) ?? 0

        var source: MemorySource? = nil
        if let ts = record["sourceTimestamp"] as? Date {
            source = MemorySource(
                conversationId: record["sourceConversationId"] as? String,
                messageId: record["sourceMessageId"] as? String,
                timestamp: ts
            )
        }

        let relatedMemories = record["relatedMemories"] as? [String]

        var metadata: [String: AnyCodable] = [:]
        if let json = record["metadataJSON"] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
            metadata = decoded
        }

        return Memory(
            id: id,
            userId: userId,
            content: content,
            type: type,
            confidence: confidence,
            tags: tags,
            context: context,
            metadata: metadata,
            source: source,
            relatedMemories: relatedMemories,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastAccessedAt: lastAccessedAt,
            accessCount: accessCount
        )
    }

    private func loadLocalMemories() -> [Memory] {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        do {
            let entities = try context.fetch(fetchRequest)
            return entities.compactMap { $0.toMemory() }
        } catch {
            print("[CloudKitSync] Error loading local memories: \(error)")
            return []
        }
    }

    private func saveMemoriesToCoreData(_ memories: [Memory]) async throws {
        // Reuse existing MemorySyncManager logic to avoid duplicating Core Data mapping.
        try await MemorySyncManager.shared.saveMemoriesToCoreData(memories)
    }

    // MARK: - Full Sync

    /// Perform a full bidirectional sync
    func performFullSync() async throws {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        print("[CloudKitSync] Starting full iCloud sync...")

        // 1. Fetch remote conversations + memories
        let remoteConversations = try await fetchConversations()
        let remoteMemories = try await fetchMemories()

        if remoteConversations.isEmpty {
            print("[CloudKitSync] ⚠️  No remote conversations returned. If you just enabled iCloud sync, you may need to run a sync on your source device first to push local chats up to CloudKit.")
        }

        // 2. Load local conversations + memories from Core Data
        let localConversations = ConversationSyncManager.shared.loadLocalConversations()
        let localMemories = loadLocalMemories()

        // 3. Merge strategy: newer wins
        var conversationsToSaveLocally: [Conversation] = []
        var conversationsToSaveRemote: [Conversation] = []

        var memoriesToSaveLocally: [Memory] = []
        var memoriesToSaveRemote: [Memory] = []

        // Create lookup maps
        let remoteMap = Dictionary(uniqueKeysWithValues: remoteConversations.map { ($0.id, $0) })
        let localMap = Dictionary(uniqueKeysWithValues: localConversations.map { ($0.id, $0) })

        let remoteMemMap = Dictionary(uniqueKeysWithValues: remoteMemories.map { ($0.id, $0) })
        let localMemMap = Dictionary(uniqueKeysWithValues: localMemories.map { ($0.id, $0) })

        // Check all local conversations
        for local in localConversations {
            if let remote = remoteMap[local.id] {
                // Both exist - use newer
                if local.updatedAt > remote.updatedAt {
                    conversationsToSaveRemote.append(local)
                } else if remote.updatedAt > local.updatedAt {
                    conversationsToSaveLocally.append(remote)
                }
            } else {
                // Only local - push to remote
                conversationsToSaveRemote.append(local)
            }
        }

        // Check remote-only conversations
        for remote in remoteConversations {
            if localMap[remote.id] == nil {
                conversationsToSaveLocally.append(remote)
            }
        }

        // Merge memories (newer wins)
        for local in localMemories {
            if let remote = remoteMemMap[local.id] {
                if local.updatedAt > remote.updatedAt {
                    memoriesToSaveRemote.append(local)
                } else if remote.updatedAt > local.updatedAt {
                    memoriesToSaveLocally.append(remote)
                }
            } else {
                memoriesToSaveRemote.append(local)
            }
        }

        for remote in remoteMemories {
            if localMemMap[remote.id] == nil {
                memoriesToSaveLocally.append(remote)
            }
        }

        // 4. Save merged data
        if !conversationsToSaveLocally.isEmpty {
            try await ConversationSyncManager.shared.saveConversationsToCoreData(conversationsToSaveLocally)
            print("[CloudKitSync] Saved \(conversationsToSaveLocally.count) conversations from iCloud to local")
        }

        if !memoriesToSaveLocally.isEmpty {
            try await saveMemoriesToCoreData(memoriesToSaveLocally)
            print("[CloudKitSync] Saved \(memoriesToSaveLocally.count) memories from iCloud to local")
        }

        if !conversationsToSaveRemote.isEmpty {
            try await syncConversations(conversationsToSaveRemote)
            print("[CloudKitSync] Pushed \(conversationsToSaveRemote.count) local conversations to iCloud")
        }

        if !memoriesToSaveRemote.isEmpty {
            try await syncMemories(memoriesToSaveRemote)
            print("[CloudKitSync] Pushed \(memoriesToSaveRemote.count) local memories to iCloud")
        }

        lastSyncTime = Date()
        didCompletePull.send()
        print("[CloudKitSync] Full sync completed")
    }

    // MARK: - Complete Data Deletion

    /// Delete all CloudKit data in the AxonData zone (conversations, messages, memories)
    /// This is a destructive operation - use with caution!
    func deleteAllCloudKitData() async throws -> (conversations: Int, messages: Int, memories: Int) {
        guard isCloudKitAvailable else {
            throw CloudKitSyncError.notAvailable
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        print("[CloudKitSync] Starting complete CloudKit data deletion...")

        try await ensureZoneExists()

        // Delete all records of each type (gracefully handles missing record types)
        let deletedConversations = await deleteAllRecordsOfType(conversationRecordType)
        let deletedMessages = await deleteAllRecordsOfType(messageRecordType)
        let deletedMemories = await deleteAllRecordsOfType(memoryRecordType)

        print("[CloudKitSync] Complete CloudKit deletion finished: \(deletedConversations) conversations, \(deletedMessages) messages, \(deletedMemories) memories")

        return (deletedConversations, deletedMessages, deletedMemories)
    }

    /// Helper to delete all records of a given type, gracefully handling missing record types
    private func deleteAllRecordsOfType(_ recordType: String) async -> Int {
        do {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let results = try await privateDatabase.records(matching: query, inZoneWith: zoneID)
            var recordIDs: [CKRecord.ID] = []
            for (recordID, _) in results.matchResults {
                recordIDs.append(recordID)
            }

            if !recordIDs.isEmpty {
                try await deleteRecords(recordIDs)
                print("[CloudKitSync] Deleted \(recordIDs.count) \(recordType) records from CloudKit")
                return recordIDs.count
            } else {
                print("[CloudKitSync] No \(recordType) records to delete")
                return 0
            }
        } catch let error as CKError {
            // "Unknown Item" (code 11) means the record type doesn't exist yet - that's fine
            if error.code == .unknownItem {
                print("[CloudKitSync] Record type '\(recordType)' doesn't exist in CloudKit schema (no data synced yet) - skipping")
                return 0
            }
            print("[CloudKitSync] Error deleting \(recordType) records: \(error.localizedDescription)")
            return 0
        } catch {
            print("[CloudKitSync] Error deleting \(recordType) records: \(error.localizedDescription)")
            return 0
        }
    }

    /// Helper to batch delete records (CloudKit has a 400 record limit per operation)
    private func deleteRecords(_ recordIDs: [CKRecord.ID]) async throws {
        let batchSize = 400

        for startIndex in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let endIndex = min(startIndex + batchSize, recordIDs.count)
            let batch = Array(recordIDs[startIndex..<endIndex])

            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
            operation.qualityOfService = .userInitiated

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                privateDatabase.add(operation)
            }
        }
    }
}

// MARK: - Errors

enum CloudKitSyncError: LocalizedError {
    case notAvailable
    case zoneCreationFailed
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "iCloud is not available. Please sign in to iCloud in Settings."
        case .zoneCreationFailed:
            return "Failed to create iCloud sync zone."
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        }
    }
}
