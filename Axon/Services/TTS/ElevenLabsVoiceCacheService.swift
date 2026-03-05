//
//  ElevenLabsVoiceCacheService.swift
//  Axon
//
//  Core Data-backed cache for the ElevenLabs voice catalog.
//  Syncable via CloudKit (per model settings).
//

import Foundation
import CoreData

@MainActor
final class ElevenLabsVoiceCacheService {
    static let shared = ElevenLabsVoiceCacheService()

    private let persistence = PersistenceController.shared

    private init() {}

    // MARK: - Public API

    /// Loads cached voices from Core Data.
    func loadCachedVoices() async -> [ElevenLabsService.ELVoice] {
        let context = persistence.container.viewContext

        let request = NSFetchRequest<NSManagedObject>(entityName: "ElevenLabsVoiceEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let results = try context.fetch(request)
            return results.compactMap { obj in
                guard let voiceId = obj.value(forKey: "voiceId") as? String,
                      let name = obj.value(forKey: "name") as? String else {
                    return nil
                }

                let category = obj.value(forKey: "category") as? String
                let language = obj.value(forKey: "language") as? String

                return ElevenLabsService.ELVoice(
                    id: voiceId,
                    name: name,
                    category: category,
                    language: language
                )
            }
        } catch {
            print("[ElevenLabsVoiceCacheService] Failed to load cached voices: \(error)")
            return []
        }
    }

    /// Upserts voices into Core Data and records `lastFetchedAt`.
    func upsertVoices(_ voices: [ElevenLabsService.ELVoice]) async {
        let context = persistence.newBackgroundContext()

        await context.perform {
            do {
                // Build existing map by voiceId
                let fetch = NSFetchRequest<NSManagedObject>(entityName: "ElevenLabsVoiceEntity")
                let existing = try context.fetch(fetch)
                var existingById: [String: NSManagedObject] = [:]
                for obj in existing {
                    if let vid = obj.value(forKey: "voiceId") as? String {
                        existingById[vid] = obj
                    }
                }

                // Upsert
                for voice in voices {
                    let obj = existingById[voice.id] ?? NSEntityDescription.insertNewObject(forEntityName: "ElevenLabsVoiceEntity", into: context)
                    obj.setValue(voice.id, forKey: "voiceId")
                    obj.setValue(voice.name, forKey: "name")
                    obj.setValue(voice.category, forKey: "category")
                    obj.setValue(voice.language, forKey: "language")
                }

                // Optionally remove voices that no longer exist upstream.
                // (Conservative: keep them to avoid surprising disappearance; you can change this later.)

                // Update meta
                let meta = try self.fetchOrCreateMeta(in: context)
                meta.setValue(Date(), forKey: "lastFetchedAt")

                try self.persistence.saveContext(context)
                print("[ElevenLabsVoiceCacheService] Saved \(voices.count) voices to Core Data")
            } catch {
                print("[ElevenLabsVoiceCacheService] Failed to upsert voices: \(error)")
            }
        }
    }

    func getLastFetchedAt() async -> Date? {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "ElevenLabsVoiceCacheMetaEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", "singleton")

        do {
            let result = try context.fetch(request).first
            return result?.value(forKey: "lastFetchedAt") as? Date
        } catch {
            print("[ElevenLabsVoiceCacheService] Failed to fetch lastFetchedAt: \(error)")
            return nil
        }
    }

    func clearCache() async {
        let context = persistence.newBackgroundContext()

        await context.perform {
            do {
                let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: "ElevenLabsVoiceEntity")
                let delete = NSBatchDeleteRequest(fetchRequest: fetch)
                delete.resultType = .resultTypeObjectIDs

                if let result = try context.execute(delete) as? NSBatchDeleteResult,
                   let objectIDs = result.result as? [NSManagedObjectID],
                   !objectIDs.isEmpty {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [self.persistence.container.viewContext]
                    )
                }

                let metaFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "ElevenLabsVoiceCacheMetaEntity")
                let metaDelete = NSBatchDeleteRequest(fetchRequest: metaFetch)
                _ = try context.execute(metaDelete)

                print("[ElevenLabsVoiceCacheService] Cleared voice cache")
            } catch {
                print("[ElevenLabsVoiceCacheService] Failed to clear cache: \(error)")
            }
        }
    }

    // MARK: - Helpers

    nonisolated private func fetchOrCreateMeta(in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ElevenLabsVoiceCacheMetaEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", "singleton")

        if let existing = try context.fetch(request).first {
            return existing
        }

        let meta = NSEntityDescription.insertNewObject(forEntityName: "ElevenLabsVoiceCacheMetaEntity", into: context)
        meta.setValue("singleton", forKey: "id")
        return meta
    }
}
