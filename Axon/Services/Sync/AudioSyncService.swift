//
//  AudioSyncService.swift
//  Axon
//
//  Cross-device sync service for TTS-generated audio.
//  Stores audio files as CKAssets in CloudKit for efficient binary transfer.
//

import Foundation
import CloudKit
import CoreData
import AVFoundation
import Combine

@MainActor
final class AudioSyncService: ObservableObject {
    static let shared = AudioSyncService()

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let persistence = PersistenceController.shared
    private let cloudKit = CloudKitSyncService.shared

    // CloudKit record type
    private let audioRecordType = "GeneratedAudio"

    // Zone for private data (same as CloudKitSyncService)
    private let zoneID = CKRecordZone.ID(zoneName: "AxonData", ownerName: CKCurrentUserDefaultName)

    // Status
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var syncError: String?
    @Published private(set) var pendingUploadCount: Int = 0

    private init() {
        self.container = CKContainer(identifier: "iCloud.NeurXAxon")
        self.privateDatabase = container.privateCloudDatabase
    }

    // MARK: - Public API

    /// Save audio metadata to Core Data after generation.
    /// Call this from TTSPlaybackService after caching audio locally.
    func saveAudioMetadata(
        messageId: String,
        conversationId: String,
        provider: String,
        voiceId: String?,
        voiceName: String?,
        format: String,
        cacheKey: String,
        audioData: Data,
        duration: TimeInterval?
    ) async throws {
        let context = persistence.newBackgroundContext()

        try await context.perform {
            // Check if already exists
            let fetchRequest: NSFetchRequest<GeneratedAudioEntity> = GeneratedAudioEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "cacheKey == %@", cacheKey)

            let existing = try context.fetch(fetchRequest)
            if !existing.isEmpty {
                print("[AudioSyncService] Audio metadata already exists for cacheKey: \(cacheKey)")
                return
            }

            // Create new entity
            let entity = GeneratedAudioEntity(context: context)
            entity.id = UUID().uuidString
            entity.messageId = messageId
            entity.conversationId = conversationId
            entity.provider = provider
            entity.voiceId = voiceId
            entity.voiceName = voiceName
            entity.format = format
            entity.fileSizeBytes = Int64(audioData.count)
            entity.durationSeconds = duration ?? 0
            entity.cacheKey = cacheKey
            entity.createdAt = Date()
            entity.syncStatus = "pending"
            entity.cloudRecordName = nil

            try context.save()
            print("[AudioSyncService] Saved audio metadata for cacheKey: \(cacheKey)")
        }

        // Update pending count
        await updatePendingCount()
    }

    /// Check if audio exists remotely (in Core Data with synced status).
    func hasRemoteAudio(for cacheKey: String) async -> Bool {
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<GeneratedAudioEntity> = GeneratedAudioEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cacheKey == %@ AND syncStatus == %@", cacheKey, "synced")
        fetchRequest.fetchLimit = 1

        do {
            let results = try context.fetch(fetchRequest)
            return !results.isEmpty
        } catch {
            print("[AudioSyncService] Error checking remote audio: \(error)")
            return false
        }
    }

    /// Fetch remote audio from CloudKit and cache locally.
    func fetchRemoteAudio(for cacheKey: String) async throws -> Data? {
        guard cloudKit.isCloudKitAvailable else {
            throw AudioSyncError.cloudKitUnavailable
        }

        // Get the cloud record name from Core Data
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<GeneratedAudioEntity> = GeneratedAudioEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cacheKey == %@", cacheKey)
        fetchRequest.fetchLimit = 1

        guard let entity = try context.fetch(fetchRequest).first,
              let recordName = entity.cloudRecordName else {
            return nil
        }

        // Fetch from CloudKit
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = try await privateDatabase.record(for: recordID)

        guard let asset = record["audioAsset"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw AudioSyncError.assetNotFound
        }

        // Read the audio data
        let audioData = try Data(contentsOf: fileURL)
        print("[AudioSyncService] Fetched remote audio for cacheKey: \(cacheKey) (\(audioData.count) bytes)")

        return audioData
    }

    /// Upload pending audio to CloudKit.
    func syncPendingAudio() async throws {
        guard cloudKit.isCloudKitAvailable else {
            throw AudioSyncError.cloudKitUnavailable
        }

        let settings = SettingsViewModel.shared.settings
        guard settings.audioSyncSettings.syncEnabled else {
            print("[AudioSyncService] Audio sync disabled")
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        let context = persistence.newBackgroundContext()
        let pendingEntities: [GeneratedAudioEntity] = try await context.perform {
            let fetchRequest: NSFetchRequest<GeneratedAudioEntity> = GeneratedAudioEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "syncStatus == %@", "pending")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            fetchRequest.fetchLimit = 10 // Batch size
            return try context.fetch(fetchRequest)
        }

        guard !pendingEntities.isEmpty else {
            print("[AudioSyncService] No pending audio to sync")
            await updatePendingCount()
            return
        }

        print("[AudioSyncService] Syncing \(pendingEntities.count) pending audio files...")

        for entity in pendingEntities {
            do {
                try await uploadAudioToCloudKit(entity: entity, context: context, settings: settings)
            } catch {
                print("[AudioSyncService] Failed to upload audio \(entity.cacheKey ?? "?"): \(error)")
                // Mark as failed but continue with others
                await context.perform {
                    entity.syncStatus = "failed"
                    try? context.save()
                }
            }
        }

        lastSyncTime = Date()
        await updatePendingCount()
        print("[AudioSyncService] Audio sync completed")
    }

    /// Perform a full bidirectional audio sync.
    func performFullAudioSync() async throws {
        guard cloudKit.isCloudKitAvailable else {
            throw AudioSyncError.cloudKitUnavailable
        }

        let settings = SettingsViewModel.shared.settings
        guard settings.audioSyncSettings.syncEnabled else {
            return
        }

        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        // 1. Push pending local audio
        try await syncPendingAudio()

        // 2. Pull remote audio metadata (the actual audio is fetched on-demand)
        try await pullRemoteAudioMetadata()

        lastSyncTime = Date()
    }

    // MARK: - Private Helpers

    private func uploadAudioToCloudKit(
        entity: GeneratedAudioEntity,
        context: NSManagedObjectContext,
        settings: AppSettings
    ) async throws {
        guard let cacheKey = entity.cacheKey,
              let format = entity.format else {
            throw AudioSyncError.invalidEntity
        }

        // Get the audio file URL
        let audioURL = getAudioFileURL(for: cacheKey, format: format)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AudioSyncError.audioFileNotFound
        }

        // Optionally compress WAV to AAC
        var uploadURL = audioURL
        var uploadFormat = format
        if format == "wav" && settings.audioSyncSettings.syncQuality == .compressed {
            if let compressedURL = try await compressWAVToAAC(sourceURL: audioURL) {
                uploadURL = compressedURL
                uploadFormat = "m4a"
            }
        }

        // Create CloudKit record
        let recordID = CKRecord.ID(recordName: "audio_\(entity.id ?? UUID().uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: audioRecordType, recordID: recordID)

        record["id"] = entity.id
        record["messageId"] = entity.messageId
        record["conversationId"] = entity.conversationId
        record["provider"] = entity.provider
        record["voiceId"] = entity.voiceId
        record["voiceName"] = entity.voiceName
        record["format"] = uploadFormat
        record["cacheKey"] = cacheKey
        record["createdAt"] = entity.createdAt

        // Create CKAsset from file
        let asset = CKAsset(fileURL: uploadURL)
        record["audioAsset"] = asset

        // Upload to CloudKit
        let savedRecord = try await privateDatabase.save(record)

        // Update entity with cloud record name
        await context.perform {
            entity.syncStatus = "synced"
            entity.cloudRecordName = savedRecord.recordID.recordName
            // Update format if we compressed
            if uploadFormat != format {
                entity.format = uploadFormat
            }
            try? context.save()
        }

        // Clean up temporary compressed file
        if uploadURL != audioURL {
            try? FileManager.default.removeItem(at: uploadURL)
        }

        print("[AudioSyncService] Uploaded audio to CloudKit: \(cacheKey)")
    }

    private func pullRemoteAudioMetadata() async throws {
        let query = CKQuery(recordType: audioRecordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let results = try await privateDatabase.records(matching: query, inZoneWith: zoneID)

        let context = persistence.newBackgroundContext()

        for (_, result) in results.matchResults {
            if case .success(let record) = result {
                await context.perform {
                    self.importRemoteAudioMetadata(record: record, context: context)
                }
            }
        }

        try await context.perform {
            try context.save()
        }

        print("[AudioSyncService] Pulled remote audio metadata")
    }

    private func importRemoteAudioMetadata(record: CKRecord, context: NSManagedObjectContext) {
        guard let cacheKey = record["cacheKey"] as? String else { return }

        // Check if already exists
        let fetchRequest: NSFetchRequest<GeneratedAudioEntity> = GeneratedAudioEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "cacheKey == %@", cacheKey)

        do {
            let existing = try context.fetch(fetchRequest)
            if !existing.isEmpty {
                // Already have this audio metadata
                return
            }

            // Create new entity from remote record
            let entity = GeneratedAudioEntity(context: context)
            entity.id = record["id"] as? String ?? UUID().uuidString
            entity.messageId = record["messageId"] as? String ?? ""
            entity.conversationId = record["conversationId"] as? String ?? ""
            entity.provider = record["provider"] as? String ?? ""
            entity.voiceId = record["voiceId"] as? String
            entity.voiceName = record["voiceName"] as? String
            entity.format = record["format"] as? String ?? "mp3"
            entity.cacheKey = cacheKey
            entity.createdAt = record["createdAt"] as? Date ?? Date()
            entity.syncStatus = "synced"
            entity.cloudRecordName = record.recordID.recordName

            print("[AudioSyncService] Imported remote audio metadata: \(cacheKey)")
        } catch {
            print("[AudioSyncService] Error importing remote audio: \(error)")
        }
    }

    private func updatePendingCount() async {
        let context = persistence.container.viewContext

        let fetchRequest: NSFetchRequest<GeneratedAudioEntity> = GeneratedAudioEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "syncStatus == %@", "pending")

        do {
            pendingUploadCount = try context.count(for: fetchRequest)
        } catch {
            pendingUploadCount = 0
        }
    }

    private func getAudioFileURL(for cacheKey: String, format: String) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioDirectory = documentsDirectory.appendingPathComponent("AudioCache")
        return audioDirectory.appendingPathComponent("\(cacheKey).\(format)")
    }

    private func compressWAVToAAC(sourceURL: URL) async throws -> URL? {
        let asset = AVAsset(url: sourceURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            print("[AudioSyncService] Compressed WAV to AAC: \(sourceURL.lastPathComponent)")
            return outputURL
        case .failed:
            if let error = exportSession.error {
                print("[AudioSyncService] Compression failed: \(error)")
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Errors

enum AudioSyncError: LocalizedError {
    case cloudKitUnavailable
    case invalidEntity
    case audioFileNotFound
    case assetNotFound

    var errorDescription: String? {
        switch self {
        case .cloudKitUnavailable:
            return "iCloud is not available. Please sign in to iCloud."
        case .invalidEntity:
            return "Invalid audio entity data."
        case .audioFileNotFound:
            return "Audio file not found on disk."
        case .assetNotFound:
            return "Audio asset not found in CloudKit."
        }
    }
}
