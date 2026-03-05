import XCTest
@testable import Axon

final class ChatExportPayloadTests: XCTestCase {

    func testChatExportPayloadJSONEncodeDecodeRoundTrip() throws {
        let conversation = Conversation(
            id: "conv1",
            userId: "user1",
            title: "Test Conversation",
            projectId: "default",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            messageCount: 2,
            lastMessageAt: Date(timeIntervalSince1970: 2),
            archived: false,
            summary: "summary",
            lastMessage: "last",
            tags: ["tag1"],
            isPinned: false,
            isPrivate: false
        )

        let message = Message(
            id: "m1",
            conversationId: "conv1",
            role: .assistant,
            content: "hello",
            hiddenReason: "hidden",
            timestamp: Date(timeIntervalSince1970: 2),
            tokens: TokenUsage(input: 1, output: 2, total: 3),
            artifacts: ["a"],
            toolCalls: [ToolCall(id: "t1", name: "webSearch", arguments: ["q": .string("test")], result: "ok")],
            isStreaming: false,
            modelName: "Model",
            providerName: "Provider",
            attachments: [MessageAttachment(id: "att1", type: .document, url: "https://example.com/file.pdf", base64: nil, name: "file.pdf", mimeType: "application/pdf")],
            groundingSources: [MessageGroundingSource(id: "g1", title: "Example", url: "https://example.com", sourceType: .web)],
            memoryOperations: [MessageMemoryOperation(id: "op1", operationType: .create, success: true, memoryType: "egoic", content: "c", tags: [], confidence: 0.9, errorMessage: nil)],
            reasoning: "thinking",
            editHistory: [MessageEdit(id: "e1", content: "v2", timestamp: Date(timeIntervalSince1970: 3), version: 1)],
            currentVersion: 1,
            contextDebugInfo: nil,
            liveToolCalls: nil
        )

        let payload = ChatExportPayload(
            exportedAt: Date(timeIntervalSince1970: 4),
            appBundleId: "com.example.axon",
            appVersion: "1.0",
            appBuild: "1",
            conversation: conversation,
            messages: [message],
            conversationOverrides: nil,
            attachments: [ChatExportAttachmentReference(messageId: message.id, attachment: message.attachments!.first!)]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatExportPayload.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, payload.schemaVersion)
        XCTAssertEqual(decoded.conversation.id, payload.conversation.id)
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.messages.first?.toolCalls?.first?.name, "webSearch")
        XCTAssertEqual(decoded.attachments.first?.url, "https://example.com/file.pdf")
    }
}
