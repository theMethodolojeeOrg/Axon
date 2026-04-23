//
//  ConversationTitleSubAgentService.swift
//  Axon
//
//  Executes internal namer sub-agent jobs and applies generated conversation titles.
//

import Foundation

@MainActor
final class ConversationTitleSubAgentService {
    static let shared = ConversationTitleSubAgentService()

    private let orchestrator = AgentOrchestratorService.shared
    private let settingsStorage = SettingsStorage.shared

    private var inFlightConversationIds: Set<String> = []

    private init() {}

    // MARK: - Post-Reply Entry Point

    func schedulePostReplyTitling(
        conversationId: String,
        userMessage: Message,
        assistantMessage: Message
    ) {
        Task { @MainActor in
            await self.titleConversationAfterReply(
                conversationId: conversationId,
                userMessage: userMessage,
                assistantMessage: assistantMessage
            )
        }
    }

    private func titleConversationAfterReply(
        conversationId: String,
        userMessage: Message,
        assistantMessage: Message
    ) async {
        guard let conversation = ConversationService.shared.conversations.first(where: { $0.id == conversationId }) else {
            return
        }

        let localMessages = ConversationService.shared.messages.filter { $0.conversationId == conversationId }
        let messagesForEligibility = localMessages.isEmpty ? [userMessage, assistantMessage] : localMessages

        _ = await titleConversationIfEligible(
            conversation: conversation,
            messages: messagesForEligibility,
            preferredAssistantMessage: assistantMessage
        )
    }

    // MARK: - Catch-up Entry Point

    @discardableResult
    func titleConversationIfEligible(
        conversation: Conversation,
        messages: [Message],
        preferredAssistantMessage: Message? = nil
    ) async -> Bool {
        let hasManualTitle = settingsStorage.hasManualDisplayName(for: conversation.id)
        let hasGeneratedTitle = settingsStorage.generatedTitle(for: conversation.id) != nil

        let eligibility = ConversationTitleEligibility.evaluate(
            conversation: conversation,
            messages: messages,
            hasManualTitle: hasManualTitle,
            hasGeneratedTitle: hasGeneratedTitle
        )

        guard case .eligible(let firstUserMessage) = eligibility else {
            return false
        }

        guard !inFlightConversationIds.contains(conversation.id) else {
            return false
        }

        let assistantMessage = preferredAssistantMessage
            ?? firstAssistantMessage(after: firstUserMessage, in: messages)

        guard let assistantMessage,
              !assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        inFlightConversationIds.insert(conversation.id)
        defer { inFlightConversationIds.remove(conversation.id) }

        do {
            let generatedTitle = try await runNamerJob(
                conversationId: conversation.id,
                userMessage: firstUserMessage,
                assistantMessage: assistantMessage
            )

            applyGeneratedTitle(generatedTitle, conversationId: conversation.id)

            do {
                _ = try await ConversationService.shared.updateConversation(id: conversation.id, title: generatedTitle)
            } catch {
                print("[ConversationTitleSubAgentService] Failed to persist generated title for \(conversation.id): \(error.localizedDescription)")
            }

            print("[ConversationTitleSubAgentService] Generated title for \(conversation.id): '\(generatedTitle)'")
            return true
        } catch {
            print("[ConversationTitleSubAgentService] Namer failed for \(conversation.id): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Internal Namer Job

    private func runNamerJob(
        conversationId: String,
        userMessage: Message,
        assistantMessage: Message
    ) async throws -> String {
        let task = buildNamerTask(
            conversationId: conversationId,
            userMessage: userMessage,
            assistantMessage: assistantMessage
        )

        let proposed = orchestrator.proposeJob(
            role: .namer,
            task: task,
            contextTags: ["conversation_title", "internal_namer"]
        )

        let approved = try await orchestrator.approveJob(
            proposed.id,
            reasoning: "Internal read-only namer job for conversation titling.",
            modelId: "internal-conversation-namer"
        )

        let executed = try await orchestrator.executeJob(approved.id)

        guard let result = executed.result else {
            throw ConversationTitleError.missingJobResult
        }

        guard let parsed = ConversationTitleNamerOutputParser.parseTitle(from: result.fullResponse) else {
            throw ConversationTitleError.invalidNamerOutput(result.fullResponse)
        }

        _ = try await orchestrator.acceptJobResult(
            executed.id,
            reasoning: "Namer output validated and applied.",
            modelId: executed.executedModel ?? "internal-conversation-namer",
            qualityScore: 1.0
        )

        return parsed
    }

    private func buildNamerTask(
        conversationId: String,
        userMessage: Message,
        assistantMessage: Message
    ) -> String {
        let user = userMessage.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(800)
        let assistant = assistantMessage.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(800)

        return """
        Generate a concise conversation title.

        Requirements:
        - Output exactly one line.
        - Format must be: TITLE: <3-6 word title>
        - Do not include markdown, bullets, numbering, quotes, or extra lines.
        - Avoid greetings and generic filler.

        Conversation ID: \(conversationId)
        User message: \(user)
        Assistant message: \(assistant)
        """
    }

    private func firstAssistantMessage(after firstUser: Message, in messages: [Message]) -> Message? {
        guard let firstUserIndex = messages.firstIndex(where: { $0.id == firstUser.id }) else {
            return messages.first(where: { $0.role == .assistant })
        }

        guard firstUserIndex + 1 < messages.count else { return nil }

        return messages[(firstUserIndex + 1)...].first(where: {
            $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
    }

    private func applyGeneratedTitle(_ title: String, conversationId: String) {
        settingsStorage.setGeneratedTitle(title, for: conversationId)
    }
}

enum ConversationTitleError: LocalizedError {
    case missingJobResult
    case invalidNamerOutput(String)

    var errorDescription: String? {
        switch self {
        case .missingJobResult:
            return "Sub-agent namer did not return a job result."
        case .invalidNamerOutput(let output):
            return "Invalid namer output: \(String(output.prefix(140)))"
        }
    }
}
