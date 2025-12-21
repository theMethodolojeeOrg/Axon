//
//  CreativeGalleryService.swift
//  Axon
//
//  Service for managing creative items in the Create gallery.
//  Aggregates generated images, audio, video, and artifacts from messages.
//

import Foundation
import CoreData
import Combine

// MARK: - Creative Gallery Service

@MainActor
final class CreativeGalleryService: ObservableObject {
    static let shared = CreativeGalleryService()
    
    // MARK: - Published State
    
    @Published private(set) var items: [CreativeItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefresh: Date?
    
    // MARK: - Dependencies
    
    private let persistence = PersistenceController.shared
    
    // MARK: - Regex Patterns
    
    /// Regex to extract artifact code blocks (explicitly marked with artifact title)
    /// Matches: ```language:title or just ```language with specific artifact markers
    private static let artifactPattern = try! NSRegularExpression(
        pattern: #"```(\w+)?(?::([^\n]+))?\n([\s\S]*?)```"#,
        options: []
    )
    
    /// Pattern to identify generated image URLs in markdown
    private static let imageURLPattern = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#,
        options: []
    )
    
    // MARK: - Initialization
    
    private init() {
        // Load items on init
        Task {
            await loadAllItems()
        }
    }
    
    // MARK: - Public API
    
    /// Load all creative items from Core Data and message parsing
    func loadAllItems() async {
        isLoading = true
        defer { isLoading = false }
        
        var allItems: [CreativeItem] = []
        
        // 1. Load cached items from Core Data (if CreativeItemEntity exists)
        let cachedItems = loadCachedItems()
        allItems.append(contentsOf: cachedItems)
        
        // 2. Scan messages for new items not yet cached
        let scannedItems = await scanMessagesForCreativeItems()
        
        // Merge: Add scanned items that aren't already cached
        let cachedIds = Set(cachedItems.map { $0.id })
        let newItems = scannedItems.filter { !cachedIds.contains($0.id) }
        
        // Cache new items
        for item in newItems {
            saveItemToCache(item)
        }
        
        allItems.append(contentsOf: newItems)
        
        // Sort by creation date (newest first)
        items = allItems
            .filter { !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
        
        lastRefresh = Date()
    }
    
    /// Get items filtered by type
    func items(for filter: GalleryFilter) -> [CreativeItem] {
        switch filter {
        case .all:
            return items
        case .type(let type):
            return items.filter { $0.type == type }
        }
    }
    
    /// Get count for each type
    func count(for type: CreativeItemType) -> Int {
        items.filter { $0.type == type }.count
    }
    
    /// Mark an item as deleted (soft delete for storage management)
    func deleteItem(_ item: CreativeItem) {
        var updatedItem = item
        updatedItem.isDeleted = true
        updatedItem.deletedAt = Date()
        
        // Update in Core Data cache
        updateCachedItem(updatedItem)
        
        // Remove from in-memory list
        items.removeAll { $0.id == item.id }
    }
    
    /// Add a directly created item to the gallery
    func addItem(_ item: CreativeItem) {
        // Save to cache
        saveItemToCache(item)
        
        // Add to in-memory list and maintain sort order
        items.insert(item, at: 0) // Newest first
    }
    
    /// Permanently delete items marked as deleted
    func purgeDeletedItems() {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "CreativeItemEntity")
        fetchRequest.predicate = NSPredicate(format: "markedDeleted == YES")
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            try context.save()
            print("[CreativeGalleryService] Purged deleted items")
        } catch {
            print("[CreativeGalleryService] Failed to purge: \(error)")
        }
    }
    
    // MARK: - Core Data Cache Operations
    
    private func loadCachedItems() -> [CreativeItem] {
        let context = persistence.container.viewContext
        
        // Check if entity exists (graceful fallback if not yet added to model)
        guard let entityDescription = NSEntityDescription.entity(forEntityName: "CreativeItemEntity", in: context) else {
            print("[CreativeGalleryService] CreativeItemEntity not found in Core Data model")
            return []
        }
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CreativeItemEntity")
        fetchRequest.entity = entityDescription
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        fetchRequest.predicate = NSPredicate(format: "markedDeleted == NO OR markedDeleted == nil")
        
        do {
            let entities = try context.fetch(fetchRequest)
            return entities.compactMap { entityToCreativeItem($0) }
        } catch {
            print("[CreativeGalleryService] Failed to load cached items: \(error)")
            return []
        }
    }
    
    private func saveItemToCache(_ item: CreativeItem) {
        let context = persistence.container.viewContext
        
        guard let entityDescription = NSEntityDescription.entity(forEntityName: "CreativeItemEntity", in: context) else {
            print("[CreativeGalleryService] CreativeItemEntity not available for caching")
            return
        }
        
        // Check if already exists
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CreativeItemEntity")
        fetchRequest.predicate = NSPredicate(format: "id == %@", item.id)
        
        do {
            let existing = try context.fetch(fetchRequest)
            if existing.isEmpty {
                let entity = NSManagedObject(entity: entityDescription, insertInto: context)
                creativeItemToEntity(item, entity: entity)
                try context.save()
            }
        } catch {
            print("[CreativeGalleryService] Failed to cache item: \(error)")
        }
    }
    
    private func updateCachedItem(_ item: CreativeItem) {
        let context = persistence.container.viewContext
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "CreativeItemEntity")
        fetchRequest.predicate = NSPredicate(format: "id == %@", item.id)
        
        do {
            if let entity = try context.fetch(fetchRequest).first {
                creativeItemToEntity(item, entity: entity)
                try context.save()
            }
        } catch {
            print("[CreativeGalleryService] Failed to update cached item: \(error)")
        }
    }
    
    // MARK: - Entity Conversion
    
    private func entityToCreativeItem(_ entity: NSManagedObject) -> CreativeItem? {
        guard let id = entity.value(forKey: "id") as? String,
              let typeString = entity.value(forKey: "type") as? String,
              let type = CreativeItemType(rawValue: typeString),
              let conversationId = entity.value(forKey: "conversationId") as? String,
              let messageId = entity.value(forKey: "messageId") as? String,
              let createdAt = entity.value(forKey: "createdAt") as? Date else {
            return nil
        }
        
        return CreativeItem(
            id: id,
            type: type,
            conversationId: conversationId,
            messageId: messageId,
            createdAt: createdAt,
            contentURL: entity.value(forKey: "contentURL") as? String,
            contentBase64: entity.value(forKey: "contentBase64") as? String,
            mimeType: entity.value(forKey: "mimeType") as? String,
            title: entity.value(forKey: "title") as? String,
            prompt: entity.value(forKey: "prompt") as? String,
            language: entity.value(forKey: "language") as? String,
            fileSize: entity.value(forKey: "fileSize") as? Int64,
            thumbnailBase64: entity.value(forKey: "thumbnailBase64") as? String,
            isDeleted: entity.value(forKey: "markedDeleted") as? Bool ?? false,
            deletedAt: entity.value(forKey: "deletedAt") as? Date
        )
    }
    
    private func creativeItemToEntity(_ item: CreativeItem, entity: NSManagedObject) {
        entity.setValue(item.id, forKey: "id")
        entity.setValue(item.type.rawValue, forKey: "type")
        entity.setValue(item.conversationId, forKey: "conversationId")
        entity.setValue(item.messageId, forKey: "messageId")
        entity.setValue(item.createdAt, forKey: "createdAt")
        entity.setValue(item.contentURL, forKey: "contentURL")
        entity.setValue(item.contentBase64, forKey: "contentBase64")
        entity.setValue(item.mimeType, forKey: "mimeType")
        entity.setValue(item.title, forKey: "title")
        entity.setValue(item.prompt, forKey: "prompt")
        entity.setValue(item.language, forKey: "language")
        entity.setValue(item.fileSize, forKey: "fileSize")
        entity.setValue(item.thumbnailBase64, forKey: "thumbnailBase64")
        entity.setValue(item.isDeleted, forKey: "markedDeleted")
        entity.setValue(item.deletedAt, forKey: "deletedAt")
    }
    
    // MARK: - Message Scanning
    
    /// Scan all messages to extract creative items
    private func scanMessagesForCreativeItems() async -> [CreativeItem] {
        let context = persistence.container.viewContext
        
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "role == %@", "assistant")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            let messages = try context.fetch(fetchRequest)
            var items: [CreativeItem] = []
            
            for message in messages {
                // 1. Check attachments
                if let attachmentItems = extractItemsFromAttachments(message) {
                    items.append(contentsOf: attachmentItems)
                }
                
                // 2. Check content for image URLs and artifacts
                if let content = message.content, let conversationId = message.conversationId, let messageId = message.id {
                    // Extract image URLs from markdown
                    let imageItems = extractImageURLsFromContent(
                        content,
                        conversationId: conversationId,
                        messageId: messageId,
                        timestamp: message.timestamp ?? Date()
                    )
                    items.append(contentsOf: imageItems)
                    
                    // Extract explicitly marked artifacts
                    // (For now, we'll look for code blocks with titles or special markers)
                    let artifactItems = extractArtifactsFromContent(
                        content,
                        conversationId: conversationId,
                        messageId: messageId,
                        timestamp: message.timestamp ?? Date()
                    )
                    items.append(contentsOf: artifactItems)
                }
            }
            
            return items
        } catch {
            print("[CreativeGalleryService] Failed to scan messages: \(error)")
            return []
        }
    }
    
    private func extractItemsFromAttachments(_ message: MessageEntity) -> [CreativeItem]? {
        guard let json = message.attachmentsJSON,
              let data = json.data(using: .utf8),
              let attachments = try? JSONDecoder().decode([MessageAttachment].self, from: data),
              let conversationId = message.conversationId,
              let messageId = message.id else {
            return nil
        }
        
        return attachments.compactMap { attachment -> CreativeItem? in
            let type: CreativeItemType
            switch attachment.type {
            case .image:
                type = .photo
            case .audio:
                type = .audio
            case .video:
                type = .video
            case .document:
                return nil  // Documents are not creative items
            }
            
            // Generate deterministic ID from message + attachment
            let itemId = "\(messageId)_\(attachment.id)"
            
            return CreativeItem(
                id: itemId,
                type: type,
                conversationId: conversationId,
                messageId: messageId,
                createdAt: message.timestamp ?? Date(),
                contentURL: attachment.url,
                contentBase64: attachment.base64,
                mimeType: attachment.mimeType,
                title: attachment.name
            )
        }
    }
    
    private func extractImageURLsFromContent(_ content: String, conversationId: String, messageId: String, timestamp: Date) -> [CreativeItem] {
        var items: [CreativeItem] = []
        
        let range = NSRange(content.startIndex..., in: content)
        let matches = Self.imageURLPattern.matches(in: content, options: [], range: range)
        
        for (index, match) in matches.enumerated() {
            guard let urlRange = Range(match.range(at: 2), in: content) else { continue }
            let urlString = String(content[urlRange])
            
            // Skip data: URLs as those are handled via attachments
            guard !urlString.hasPrefix("data:") else { continue }
            
            // Skip local file paths
            guard urlString.hasPrefix("http") else { continue }
            
            // Generate deterministic ID
            let itemId = "\(messageId)_img_\(index)"
            
            // Extract alt text for title
            var title: String? = nil
            if let altRange = Range(match.range(at: 1), in: content) {
                let alt = String(content[altRange])
                if !alt.isEmpty {
                    title = alt
                }
            }
            
            // Check if this might be a generated image (OpenAI/Gemini URLs)
            let isLikelyGenerated = urlString.contains("openai") || 
                                     urlString.contains("gemini") ||
                                     urlString.contains("dall-e") ||
                                     urlString.contains("generated")
            
            if isLikelyGenerated {
                items.append(CreativeItem(
                    id: itemId,
                    type: .photo,
                    conversationId: conversationId,
                    messageId: messageId,
                    createdAt: timestamp,
                    contentURL: urlString,
                    title: title ?? "Generated Image"
                ))
            }
        }
        
        return items
    }
    
    private func extractArtifactsFromContent(_ content: String, conversationId: String, messageId: String, timestamp: Date) -> [CreativeItem] {
        var items: [CreativeItem] = []
        
        // Look for explicitly marked artifacts
        // Pattern: code blocks with titles (```language:Title) or special artifact markers
        let range = NSRange(content.startIndex..., in: content)
        let matches = Self.artifactPattern.matches(in: content, options: [], range: range)
        
        for (index, match) in matches.enumerated() {
            // Extract language
            var language: String? = nil
            if let langRange = Range(match.range(at: 1), in: content) {
                language = String(content[langRange])
            }
            
            // Extract title (only if explicitly marked with :title syntax)
            var title: String? = nil
            if let titleRange = Range(match.range(at: 2), in: content) {
                title = String(content[titleRange])
            }
            
            // Only include if it has an explicit title (marking it as an artifact)
            // This filters out regular code examples from explicitly marked artifacts
            guard title != nil else { continue }
            
            // Extract code content
            guard let codeRange = Range(match.range(at: 3), in: content) else { continue }
            let code = String(content[codeRange])
            
            // Skip very short code blocks (likely inline examples)
            guard code.count > 50 else { continue }
            
            let itemId = "\(messageId)_artifact_\(index)"
            
            items.append(CreativeItem(
                id: itemId,
                type: .artifact,
                conversationId: conversationId,
                messageId: messageId,
                createdAt: timestamp,
                contentBase64: code.data(using: .utf8)?.base64EncodedString(),
                mimeType: "text/\(language ?? "plain")",
                title: title,
                language: language
            ))
        }
        
        return items
    }
}
