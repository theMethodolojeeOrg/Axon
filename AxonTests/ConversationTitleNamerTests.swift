//
//  ConversationTitleNamerTests.swift
//  AxonTests
//
//  Tests for sub-agent conversation title parsing and catch-up eligibility.
//

import Testing
import Foundation
@testable import Axon

struct ConversationTitleNamerTests {

    @Test func parsesStrictTitleLine() {
        let title = ConversationTitleNamerOutputParser.parseTitle(from: "TITLE: VS Code Bridge Debugging")
        #expect(title == "VS Code Bridge Debugging")
    }

    @Test func rejectsGreetingOnlyTitle() {
        let title = ConversationTitleNamerOutputParser.parseTitle(from: "TITLE: Hello")
        #expect(title == nil)
    }

    @Test func firstMessagePrefixTitleIsEligible() {
        let first = Message(
            conversationId: "c1",
            role: .user,
            content: "Hello! Can you help me make sure the VS Code bridge is working?"
        )
        let conversation = Conversation(
            id: "c1",
            title: String(first.content.prefix(50)),
            projectId: "default",
            messageCount: 2
        )

        let decision = ConversationTitleEligibility.evaluate(
            conversation: conversation,
            messages: [first],
            hasManualTitle: false,
            hasGeneratedTitle: false
        )

        #expect(decision == .eligible(firstUserMessage: first))
    }

    @Test func manualTitleBlocksEligibility() {
        let first = Message(conversationId: "c1", role: .user, content: "Hello! Please test the bridge")
        let conversation = Conversation(
            id: "c1",
            title: String(first.content.prefix(50)),
            projectId: "default",
            messageCount: 2
        )

        let decision = ConversationTitleEligibility.evaluate(
            conversation: conversation,
            messages: [first],
            hasManualTitle: true,
            hasGeneratedTitle: false
        )

        #expect(decision == .skipped(.manualTitleExists))
    }

    @Test func generatedTitleBlocksEligibility() {
        let first = Message(conversationId: "c1", role: .user, content: "Hello! Please test the bridge")
        let conversation = Conversation(
            id: "c1",
            title: String(first.content.prefix(50)),
            projectId: "default",
            messageCount: 2
        )

        let decision = ConversationTitleEligibility.evaluate(
            conversation: conversation,
            messages: [first],
            hasManualTitle: false,
            hasGeneratedTitle: true
        )

        #expect(decision == .skipped(.generatedTitleExists))
    }

    @Test func privateArchivedAndEmptyChatsAreSkipped() {
        let first = Message(conversationId: "c1", role: .user, content: "Hello! Please test the bridge")

        let privateConversation = Conversation(
            id: "c1",
            title: "New Chat",
            projectId: "default",
            messageCount: 1,
            isPrivate: true
        )
        #expect(ConversationTitleEligibility.evaluate(
            conversation: privateConversation,
            messages: [first],
            hasManualTitle: false,
            hasGeneratedTitle: false
        ) == .skipped(.privateThread))

        let archivedConversation = Conversation(
            id: "c2",
            title: "New Chat",
            projectId: "default",
            messageCount: 1,
            archived: true
        )
        #expect(ConversationTitleEligibility.evaluate(
            conversation: archivedConversation,
            messages: [first],
            hasManualTitle: false,
            hasGeneratedTitle: false
        ) == .skipped(.archived))

        let emptyConversation = Conversation(
            id: "c3",
            title: "New Chat",
            projectId: "default",
            messageCount: 0
        )
        #expect(ConversationTitleEligibility.evaluate(
            conversation: emptyConversation,
            messages: [],
            hasManualTitle: false,
            hasGeneratedTitle: false
        ) == .skipped(.noUserMessage))
    }

    @Test func catchUpQueueDedupesJobs() {
        var registry = ConversationTitleCatchUpRegistry()

        #expect(registry.enqueue("c1"))
        #expect(!registry.enqueue("c1"))
        #expect(registry.enqueue("c2"))

        #expect(registry.dequeue() == "c1")
        #expect(registry.dequeue() == "c2")
        #expect(registry.dequeue() == nil)
    }

    @Test func failedAttemptsUseCooldownAndAvoidRetryLoops() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        var registry = ConversationTitleCatchUpRegistry(failureCooldown: 3_600)

        registry.record("c1", outcome: .failed, error: "bad output", now: baseline)
        #expect(registry.attempts["c1"]?.attempts == 1)
        #expect(registry.attempts["c1"]?.lastOutcome == .failed)
        #expect(registry.canAttempt("c1", now: baseline.addingTimeInterval(120)) == false)
        #expect(registry.canAttempt("c1", now: baseline.addingTimeInterval(3_600)) == true)
    }
}
