//
//  MemorySyncManager.swift
//  Axon
//
//  Manages memory synchronization between Core Data (local) and API (remote)
//

import Foundation
import CoreData
import Combine

@MainActor
class MemorySyncManager: ObservableObject {
    static let shared = MemorySyncManager()

    private let persistence = PersistenceController.shared
    private let apiClient = APIClient.shared
    private let userDefaults = UserDefaults.standard

    // Sync state
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    @Published var syncError: String?

    private let lastSyncTimestampKey = "lastMemorySyncTimestamp"

    private init() {
        // Load last sync time
        if let timestamp = userDefaults.object(forKey: lastSyncTimestampKey) as? Double {
            lastSyncTime = Date(timeIntervalSince1970: timestamp / 1000)
        }
    }

    // MARK: - Public API

    /// Load memories from local Core Data (instant)
    /// Excludes soft-deleted memories (syncStatus == "deleted")
    func loadLocalMemories() -> [Memory] {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        // CRITICAL: Filter out soft-deleted memories to prevent resurrection
        fetchRequest.predicate = NSPredicate(format: "syncStatus != %@", "deleted")

        do {
            let entities = try context.fetch(fetchRequest)
            return entities.compactMap { entity in
                return entity.toMemory()
            }
        } catch {
            print("[MemorySyncManager] Error loading local memories: \(error)")
            return []
        }
    }

    /// Sync memories with the server
    func syncMemories() async throws {
        guard !isSyncing else {
            print("[MemorySyncManager] Sync already in progress")
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        let lastSyncTimestamp = userDefaults.object(forKey: lastSyncTimestampKey) as? Double

        if lastSyncTimestamp == nil {
            // First sync - fetch all memories
            try await performFullSync()
        } else {
            // Delta sync - fetch only changes since last sync
            try await performDeltaSync(since: lastSyncTimestamp!)
        }
    }

    /// Force full sync, ignoring last sync timestamp
    func forceFullSync() async throws {
        guard !isSyncing else {
            print("[MemorySyncManager] Sync already in progress")
            return
        }

        print("[MemorySyncManager] 🔄 Force full sync requested")
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // Reset sync timestamp to force full sync
        userDefaults.removeObject(forKey: lastSyncTimestampKey)
        lastSyncTime = nil

        try await performFullSync()
    }

    // MARK: - Full Sync

    private func performFullSync() async throws {
        print("[MemorySyncManager] ⚡ Performing FULL sync")

        do {
            let response: MemoryListResponse = try await apiClient.request(
                endpoint: "/apiGetMemories?limit=1000",
                method: .get
            )

            print("[MemorySyncManager] ✅ Full sync fetched \(response.memories.count) memories")

            // Save all memories to Core Data
            try await saveMemoriesToCoreData(response.memories)

            // Store timestamp for future delta syncs
            let timestamp = Date().timeIntervalSince1970 * 1000
            userDefaults.set(timestamp, forKey: lastSyncTimestampKey)
            lastSyncTime = Date()

            print("[MemorySyncManager] ✅ Full sync completed successfully!")
        } catch {
            syncError = error.localizedDescription
            print("[MemorySyncManager] ❌ Full sync FAILED: \(error)")
            throw error
        }
    }

    // MARK: - Delta Sync

    private func performDeltaSync(since timestamp: Double) async throws {
        print("[MemorySyncManager] Performing delta sync (since=\(timestamp))")

        // Note: This assumes the API supports delta sync for memories
        // If not, fall back to full sync
        do {
            let response: MemoryListResponse = try await apiClient.request(
                endpoint: "/apiGetMemories?limit=1000",
                method: .get
            )

            print("[MemorySyncManager] Delta sync: \(response.memories.count) total memories")

            // Process updates
            if !response.memories.isEmpty {
                try await saveMemoriesToCoreData(response.memories)
            }

            // Update last sync timestamp
            let newTimestamp = Date().timeIntervalSince1970 * 1000
            userDefaults.set(newTimestamp, forKey: lastSyncTimestampKey)
            lastSyncTime = Date()

            print("[MemorySyncManager] ✅ Delta sync completed")
        } catch {
            syncError = error.localizedDescription
            print("[MemorySyncManager] ❌ Delta sync failed: \(error)")
            throw error
        }
    }

    // MARK: - Helpers

    /// Convert an `AnyCodable` value into a Foundation object suitable for `NSDictionary` storage.
    /// This uses JSON encoding/decoding to produce property-list compatible types.
    private func foundationObject(from anyCodable: AnyCodable) -> Any? {
        do {
            let data = try JSONEncoder().encode(anyCodable)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            return obj
        } catch {
            print("[MemorySyncManager] Failed to convert AnyCodable to Foundation object: \(error)")
            return nil
        }
    }

    // MARK: - Core Data Operations

    /// Save memories to Core Data
    func saveMemoriesToCoreData(_ memories: [Memory]) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            var savedCount = 0
            var skippedCount = 0

            for memory in memories {
                let fetchRequest: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", memory.id)

                let entity: MemoryEntity
                if let existing = try context.fetch(fetchRequest).first {
                    // CRITICAL: Don't overwrite soft-deleted memories
                    // This prevents resurrection during sync
                    if existing.syncStatus == "deleted" {
                        print("[MemorySyncManager] ⚠️ Skipping soft-deleted memory: \(memory.id)")
                        skippedCount += 1
                        continue
                    }
                    // Update existing
                    entity = existing
                } else {
                    // Create new
                    entity = MemoryEntity(context: context)
                }

                // Populate entity from memory
                entity.id = memory.id
                entity.userId = memory.userId
                entity.content = memory.content
                entity.type = memory.type.rawValue
                entity.confidence = memory.confidence
                entity.tags = memory.tags as NSObject
                entity.createdAt = memory.createdAt
                entity.updatedAt = memory.updatedAt
                entity.lastAccessedAt = memory.lastAccessedAt
                entity.accessCount = Int32(memory.accessCount)
                entity.syncStatus = "synced"
                entity.locallyModified = false

                // Note: 'context' field requires Core Data model update
                // entity.context = memory.context

                // Source information
                if let source = memory.source {
                    entity.sourceConversationId = source.conversationId
                    entity.sourceMessageId = source.messageId
                    entity.sourceTimestamp = source.timestamp
                }

                // Related memories
                entity.relatedMemoryIds = memory.relatedMemories as NSObject?

                // Metadata - convert to NSDictionary for Core Data
                if !memory.metadata.isEmpty {
                    var metadataDict: [String: Any] = [:]
                    for (key, anyCodableValue) in memory.metadata {
                        if let foundation = self.foundationObject(from: anyCodableValue) {
                            metadataDict[key] = foundation
                        } else {
                            // Fallback: store string description if conversion fails
                            metadataDict[key] = String(describing: anyCodableValue)
                        }
                    }
                    entity.metadata = metadataDict as NSDictionary
                }
                savedCount += 1
            }

            try self.persistence.saveContext(context)
            if skippedCount > 0 {
                print("[MemorySyncManager] Saved \(savedCount) memories, skipped \(skippedCount) soft-deleted")
            } else {
                print("[MemorySyncManager] Saved \(savedCount) memories to Core Data")
            }
        }
    }

    /// Soft-delete a memory from Core Data (prevents resurrection during sync)
    func deleteMemoryFromCoreData(id: String) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            let fetchRequest: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)

            if let entity = try context.fetch(fetchRequest).first {
                // Use soft-delete (tombstone) instead of hard delete
                entity.syncStatus = "deleted"
                entity.updatedAt = Date()
                try self.persistence.saveContext(context)
                print("[MemorySyncManager] Soft-deleted memory \(id) (tombstone)")
            }
        }
    }

    /// Hard-delete a memory after server confirms deletion
    func hardDeleteMemoryFromCoreData(id: String) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            let fetchRequest: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)

            if let entity = try context.fetch(fetchRequest).first {
                context.delete(entity)
                try self.persistence.saveContext(context)
                print("[MemorySyncManager] Hard-deleted memory \(id) after server confirmation")
            }
        }
    }

    /// Clean up old soft-deleted memories (call periodically)
    func cleanupOldTombstones(olderThan days: Int = 7) async throws {
        let context = persistence.newBackgroundContext()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        try await context.perform {
            let fetchRequest: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "syncStatus == %@", "deleted"),
                NSPredicate(format: "updatedAt < %@", cutoffDate as NSDate)
            ])

            let entities = try context.fetch(fetchRequest)
            for entity in entities {
                context.delete(entity)
            }

            if !entities.isEmpty {
                try self.persistence.saveContext(context)
                print("[MemorySyncManager] Cleaned up \(entities.count) old memory tombstones")
            }
        }
    }
}

// MARK: - MemoryEntity Extension

extension MemoryEntity {
    func toMemory() -> Memory? {
        guard let id = self.id,
              let userId = self.userId,
              let content = self.content,
              let typeString = self.type,
              let type = MemoryType(rawValue: typeString),
              let createdAt = self.createdAt,
              let updatedAt = self.updatedAt else {
            return nil
        }

        // Convert metadata from NSDictionary to [String: AnyCodable]
        var metadataDict: [String: AnyCodable] = [:]
        if let metadata = self.metadata as? [String: Any] {
            // Try to round-trip via JSON to produce [String: AnyCodable]
            if JSONSerialization.isValidJSONObject(metadata),
               let data = try? JSONSerialization.data(withJSONObject: metadata, options: []) {
                if let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
                    metadataDict = decoded
                } else {
                    // Fallback: stringify values, then decode as AnyCodable
                    let stringified = metadata.mapValues { String(describing: $0) }
                    if let fallbackData = try? JSONEncoder().encode(stringified),
                       let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: fallbackData) {
                        metadataDict = decoded
                    }
                }
            } else {
                // Not a valid JSON object: fallback to stringifying
                let stringified = metadata.mapValues { String(describing: $0) }
                if let fallbackData = try? JSONEncoder().encode(stringified),
                   let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: fallbackData) {
                    metadataDict = decoded
                }
            }
        }

        // Build source if available
        var source: MemorySource? = nil
        if let sourceConvId = self.sourceConversationId,
           let sourceTs = self.sourceTimestamp {
            source = MemorySource(
                conversationId: sourceConvId,
                messageId: self.sourceMessageId,
                timestamp: sourceTs
            )
        }
        
            // Note: 'context' field requires Core Data model update
            // let context = self.context

            return Memory(
                id: id,
                userId: userId,
                content: content,
                type: type,
                confidence: self.confidence,
                tags: self.tags as? [String] ?? [],
                // context: nil, // Placeholder until Core Data model is updated
                metadata: metadataDict,
            source: source,
            relatedMemories: self.relatedMemoryIds as? [String],
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastAccessedAt: self.lastAccessedAt,
            accessCount: Int(self.accessCount)
        )
    }
}

