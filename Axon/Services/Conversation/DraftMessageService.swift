//
//  DraftMessageService.swift
//  Axon
//
//  Service for persisting draft messages per conversation with hybrid UserDefaults/iCloud sync
//

import Foundation
import Combine

/// Represents a draft message for a conversation
struct DraftMessage: Codable {
    var text: String
    var attachments: [MessageAttachment]
    var lastModified: Date
    
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}

/// Service for managing draft messages across conversations
@MainActor
final class DraftMessageService: ObservableObject {
    static let shared = DraftMessageService()
    
    /// Published drafts dictionary for UI observation
    @Published private(set) var drafts: [String: DraftMessage] = [:]
    
    /// Special key for "New Chat" drafts (before conversation is created)
    static let newChatDraftKey = "__new_chat__"
    
    private let userDefaultsKey = "axon_message_drafts"
    private let iCloudKey = "message_drafts"
    private let maxDraftAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    
    private var iCloudSync: iCloudKeyValueSync?
    
    private init() {
        loadPersistedDrafts()
        setupiCloudSync()
        cleanupOldDrafts()
    }
    
    // MARK: - Setup
    
    private func setupiCloudSync() {
        // Check if iCloud sync is enabled in settings
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        if settings.deviceModeConfig.cloudSyncProvider == .iCloud {
            iCloudSync = iCloudKeyValueSync.shared
            
            // Listen for iCloud changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleiCloudChange),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default
            )
            
            // Sync from iCloud on startup
            syncFromiCloud()
        }
    }
    
    @objc private func handleiCloudChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let changeReason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else {
            return
        }
        
        // Only sync on external changes (from other devices)
        if changeReason == NSUbiquitousKeyValueStoreServerChange ||
           changeReason == NSUbiquitousKeyValueStoreInitialSyncChange {
            syncFromiCloud()
        }
    }
    
    // MARK: - Public API
    
    /// Save a draft for a conversation
    func saveDraft(conversationId: String, text: String, attachments: [MessageAttachment]) {
        let draft = DraftMessage(
            text: text,
            attachments: attachments,
            lastModified: Date()
        )
        
        // Don't save empty drafts
        if draft.isEmpty {
            clearDraft(conversationId: conversationId)
            return
        }
        
        drafts[conversationId] = draft
        persistDrafts()
        
        print("[DraftMessageService] Saved draft for conversation: \(conversationId)")
    }
    
    /// Load a draft for a conversation
    func loadDraft(conversationId: String) -> DraftMessage? {
        return drafts[conversationId]
    }
    
    /// Check if a draft exists for a conversation
    func hasDraft(conversationId: String) -> Bool {
        guard let draft = drafts[conversationId] else { return false }
        return !draft.isEmpty
    }
    
    /// Clear a draft for a conversation
    func clearDraft(conversationId: String) {
        drafts.removeValue(forKey: conversationId)
        persistDrafts()
        
        print("[DraftMessageService] Cleared draft for conversation: \(conversationId)")
    }
    
    /// Get all conversation IDs that have drafts
    func conversationsWithDrafts() -> Set<String> {
        return Set(drafts.keys.filter { !drafts[$0]!.isEmpty })
    }
    
    /// Transfer "New Chat" draft to actual conversation
    func transferNewChatDraft(to conversationId: String) {
        if let newChatDraft = drafts[Self.newChatDraftKey] {
            drafts[conversationId] = newChatDraft
            drafts.removeValue(forKey: Self.newChatDraftKey)
            persistDrafts()
            
            print("[DraftMessageService] Transferred new chat draft to: \(conversationId)")
        }
    }
    
    // MARK: - Persistence
    
    /// Persist drafts to UserDefaults
    func persistDrafts() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(drafts)
            
            // Save to UserDefaults
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            
            // Sync to iCloud if enabled
            syncToiCloud()
            
        } catch {
            print("[DraftMessageService] Failed to persist drafts: \(error)")
        }
    }
    
    /// Load persisted drafts from UserDefaults
    func loadPersistedDrafts() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            print("[DraftMessageService] No persisted drafts found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            drafts = try decoder.decode([String: DraftMessage].self, from: data)
            
            print("[DraftMessageService] Loaded \(drafts.count) persisted drafts")
        } catch {
            print("[DraftMessageService] Failed to load persisted drafts: \(error)")
        }
    }
    
    // MARK: - iCloud Sync
    
    private func syncToiCloud() {
        guard iCloudSync != nil else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(drafts)
            
            // Convert to base64 string for iCloud storage
            let base64String = data.base64EncodedString()
            NSUbiquitousKeyValueStore.default.set(base64String, forKey: iCloudKey)
            NSUbiquitousKeyValueStore.default.synchronize()
            
            print("[DraftMessageService] Synced drafts to iCloud")
        } catch {
            print("[DraftMessageService] Failed to sync to iCloud: \(error)")
        }
    }
    
    private func syncFromiCloud() {
        guard iCloudSync != nil,
              let base64String = NSUbiquitousKeyValueStore.default.string(forKey: iCloudKey),
              let data = Data(base64Encoded: base64String) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let iCloudDrafts = try decoder.decode([String: DraftMessage].self, from: data)
            
            // Merge with local drafts, preferring newer timestamps
            for (conversationId, iCloudDraft) in iCloudDrafts {
                if let localDraft = drafts[conversationId] {
                    // Keep the newer draft
                    if iCloudDraft.lastModified > localDraft.lastModified {
                        drafts[conversationId] = iCloudDraft
                    }
                } else {
                    // No local draft, use iCloud version
                    drafts[conversationId] = iCloudDraft
                }
            }
            
            // Persist merged drafts locally
            persistDrafts()
            
            print("[DraftMessageService] Synced \(iCloudDrafts.count) drafts from iCloud")
        } catch {
            print("[DraftMessageService] Failed to sync from iCloud: \(error)")
        }
    }
    
    // MARK: - Cleanup
    
    /// Remove drafts older than maxDraftAge
    private func cleanupOldDrafts() {
        let cutoffDate = Date().addingTimeInterval(-maxDraftAge)
        let oldDrafts = drafts.filter { $0.value.lastModified < cutoffDate }
        
        if !oldDrafts.isEmpty {
            for (conversationId, _) in oldDrafts {
                drafts.removeValue(forKey: conversationId)
            }
            persistDrafts()
            
            print("[DraftMessageService] Cleaned up \(oldDrafts.count) old drafts")
        }
    }
    
    /// Get draft age as a human-readable string
    func draftAge(for conversationId: String) -> String? {
        guard let draft = drafts[conversationId] else { return nil }
        
        let interval = Date().timeIntervalSince(draft.lastModified)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
}
