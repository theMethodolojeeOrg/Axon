import XCTest
@testable import Axon

@MainActor
final class AssistantRegenerationContextTests: XCTestCase {
    func testLastAssistantRegeneratesFromImmediatelyPrecedingUserMessage() throws {
        let conversationId = "conversation-1"
        let user = Message(id: "user-1", conversationId: conversationId, role: .user, content: "Draft this")
        let assistant = Message(id: "assistant-1", conversationId: conversationId, role: .assistant, content: "Draft")

        let context = try ConversationService.assistantRegenerationContext(
            in: [user, assistant],
            conversationId: conversationId,
            assistantMessageId: assistant.id
        )

        XCTAssertEqual(context.assistantIndex, 1)
        XCTAssertEqual(context.userIndex, 0)
        XCTAssertEqual(context.userMessage, user)
    }

    func testMiddleAssistantRegeneratesFromEarlierUserTurn() throws {
        let conversationId = "conversation-1"
        let firstUser = Message(id: "user-1", conversationId: conversationId, role: .user, content: "First")
        let firstAssistant = Message(id: "assistant-1", conversationId: conversationId, role: .assistant, content: "First answer")
        let secondUser = Message(id: "user-2", conversationId: conversationId, role: .user, content: "Second")
        let secondAssistant = Message(id: "assistant-2", conversationId: conversationId, role: .assistant, content: "Second answer")

        let context = try ConversationService.assistantRegenerationContext(
            in: [firstUser, firstAssistant, secondUser, secondAssistant],
            conversationId: conversationId,
            assistantMessageId: firstAssistant.id
        )

        XCTAssertEqual(context.assistantIndex, 1)
        XCTAssertEqual(context.userIndex, 0)
        XCTAssertEqual(context.userMessage, firstUser)
    }

    func testAssistantClusterUsesNearestPrecedingUserMessage() throws {
        let conversationId = "conversation-1"
        let user = Message(id: "user-1", conversationId: conversationId, role: .user, content: "Explain")
        let firstAssistant = Message(id: "assistant-1", conversationId: conversationId, role: .assistant, content: "Part one")
        let secondAssistant = Message(id: "assistant-2", conversationId: conversationId, role: .assistant, content: "Part two")

        let context = try ConversationService.assistantRegenerationContext(
            in: [user, firstAssistant, secondAssistant],
            conversationId: conversationId,
            assistantMessageId: secondAssistant.id
        )

        XCTAssertEqual(context.assistantIndex, 2)
        XCTAssertEqual(context.userIndex, 0)
        XCTAssertEqual(context.userMessage, user)
    }

    func testMissingAssistantIdFailsAsNotFound() {
        XCTAssertThrowsError(
            try ConversationService.assistantRegenerationContext(
                in: [Message(id: "user-1", conversationId: "conversation-1", role: .user, content: "Hello")],
                conversationId: "conversation-1",
                assistantMessageId: "missing"
            )
        ) { error in
            XCTAssertEqual(error as? ConversationError, .notFound)
        }
    }

    func testUserMessageTargetFailsAsInvalidData() {
        let user = Message(id: "user-1", conversationId: "conversation-1", role: .user, content: "Hello")

        XCTAssertThrowsError(
            try ConversationService.assistantRegenerationContext(
                in: [user],
                conversationId: "conversation-1",
                assistantMessageId: user.id
            )
        ) { error in
            XCTAssertEqual(error as? ConversationError, .invalidData)
        }
    }

    func testAssistantWithoutPrecedingUserFailsAsInvalidData() {
        let assistant = Message(id: "assistant-1", conversationId: "conversation-1", role: .assistant, content: "Hello")

        XCTAssertThrowsError(
            try ConversationService.assistantRegenerationContext(
                in: [assistant],
                conversationId: "conversation-1",
                assistantMessageId: assistant.id
            )
        ) { error in
            XCTAssertEqual(error as? ConversationError, .invalidData)
        }
    }

    func testDeletedPrecedingUserIsSkippedAndFailsWhenNoActiveUserExists() {
        let deletedUser = Message(
            id: "user-1",
            conversationId: "conversation-1",
            role: .user,
            content: "Deleted",
            isDeleted: true
        )
        let assistant = Message(id: "assistant-1", conversationId: "conversation-1", role: .assistant, content: "Hello")

        XCTAssertThrowsError(
            try ConversationService.assistantRegenerationContext(
                in: [deletedUser, assistant],
                conversationId: "conversation-1",
                assistantMessageId: assistant.id
            )
        ) { error in
            XCTAssertEqual(error as? ConversationError, .invalidData)
        }
    }
}
