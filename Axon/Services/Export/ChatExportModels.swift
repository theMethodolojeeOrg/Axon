//
//  ChatExportModels.swift
//  Axon
//
//  Export payload models for chat/thread sharing.
//

import Foundation

/// Stable export container for a conversation and its message thread.
///
/// Notes:
/// - We intentionally keep this format additive (new optional fields) so future formats
///   like PDF can reuse the same payload without breaking existing exports.
struct ChatExportPayload: Codable, Equatable {
    let schemaVersion: Int
    let exportedAt: Date

    // App metadata (best-effort)
    let appBundleId: String?
    let appVersion: String?
    let appBuild: String?

    // Thread data
    let conversation: Conversation
    let messages: [Message]

    // Per-conversation overrides (provider/model/tools)
    let conversationOverrides: ConversationOverrides?

    // Attachment index (references only; binary payloads are handled by ZIP exporter)
    let attachments: [ChatExportAttachmentReference]

    init(
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        appBundleId: String? = Bundle.main.bundleIdentifier,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        appBuild: String? = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
        conversation: Conversation,
        messages: [Message],
        conversationOverrides: ConversationOverrides?,
        attachments: [ChatExportAttachmentReference]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appBundleId = appBundleId
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.conversation = conversation
        self.messages = messages
        self.conversationOverrides = conversationOverrides
        self.attachments = attachments
    }
}

struct ChatExportAttachmentReference: Codable, Identifiable, Equatable {
    let id: String
    let messageId: String
    let type: MessageAttachment.AttachmentType
    let url: String?
    let name: String?
    let mimeType: String?

    init(id: String = UUID().uuidString, messageId: String, attachment: MessageAttachment) {
        self.id = id
        self.messageId = messageId
        self.type = attachment.type
        self.url = attachment.url
        self.name = attachment.name
        self.mimeType = attachment.mimeType
    }
}
