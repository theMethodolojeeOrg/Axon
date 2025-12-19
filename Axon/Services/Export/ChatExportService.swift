//
//  ChatExportService.swift
//  Axon
//
//  Builds export payloads and file outputs (JSON/MD/ZIP).
//

import Foundation

@MainActor
final class ChatExportService {
    static let shared = ChatExportService()

    private init() {}

    enum ExportFormat {
        case json
        case markdown
        case zip

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .markdown: return "md"
            case .zip: return "zip"
            }
        }

        var defaultFilenameStem: String {
            switch self {
            case .json: return "thread"
            case .markdown: return "thread"
            case .zip: return "chat-export"
            }
        }
    }

    struct ExportedFile {
        let url: URL
        let suggestedFilename: String
    }

    func exportFile(for conversation: Conversation, format: ExportFormat) async throws -> ExportedFile {
        let messages = try await ConversationService.shared.getMessages(conversationId: conversation.id, limit: 10_000)
        let payload = buildPayload(conversation: conversation, messages: messages)

        switch format {
        case .json:
            let data = try ChatJSONExporter().encode(payload)
            let url = try writeTempFile(data: data, filename: suggestedFilename(conversation: conversation, format: .json))
            return ExportedFile(url: url, suggestedFilename: url.lastPathComponent)

        case .markdown:
            let text = ChatMarkdownExporter().render(payload)
            let data = Data(text.utf8)
            let url = try writeTempFile(data: data, filename: suggestedFilename(conversation: conversation, format: .markdown))
            return ExportedFile(url: url, suggestedFilename: url.lastPathComponent)

        case .zip:
            let url = try ChatZipExporter().buildZip(payload)
            return ExportedFile(url: url, suggestedFilename: url.lastPathComponent)
        }
    }

    private func suggestedFilename(conversation: Conversation, format: ExportFormat) -> String {
        let safeTitle = sanitizeFilename(conversation.title)
        let dateStamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")

        let stem: String
        switch format {
        case .zip:
            stem = "chat-export_\(safeTitle)_\(dateStamp)"
        default:
            stem = "\(format.defaultFilenameStem)_\(safeTitle)_\(dateStamp)"
        }

        return "\(stem).\(format.fileExtension)"
    }

    private func buildPayload(conversation: Conversation, messages: [Message]) -> ChatExportPayload {
        let overridesKey = "conversation_overrides_\(conversation.id)"
        let overrides: ConversationOverrides?
        if let data = UserDefaults.standard.data(forKey: overridesKey),
           let decoded = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
            overrides = decoded
        } else {
            overrides = nil
        }

        let attachmentRefs: [ChatExportAttachmentReference] = messages.flatMap { message in
            (message.attachments ?? []).map { ChatExportAttachmentReference(messageId: message.id, attachment: $0) }
        }

        return ChatExportPayload(
            conversation: conversation,
            messages: messages,
            conversationOverrides: overrides,
            attachments: attachmentRefs
        )
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private func writeTempFile(data: Data, filename: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AxonExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
