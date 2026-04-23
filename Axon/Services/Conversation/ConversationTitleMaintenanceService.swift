//
//  ConversationTitleMaintenanceService.swift
//  Axon
//
//  Startup catch-up and deferred naming queue for existing conversations.
//

import Foundation

@MainActor
final class ConversationTitleMaintenanceService {
    static let shared = ConversationTitleMaintenanceService()

    private struct CatchUpJob {
        let conversationId: String
        let conversationSnapshot: Conversation?
        let messagesSnapshot: [Message]?
    }

    private let attemptsKey = "conversation.titleCatchUpAttempts"
    private let localStore = LocalConversationStore.shared
    private let settingsStorage = SettingsStorage.shared

    private var registry: ConversationTitleCatchUpRegistry
    private var pendingJobs: [CatchUpJob] = []
    private var pendingConversationIds: Set<String> = []
    private var isProcessingQueue = false
    private var didScheduleStartupPass = false

    private init() {
        let attempts = Self.loadAttempts(key: attemptsKey)
        self.registry = ConversationTitleCatchUpRegistry(attempts: attempts)
    }

    // MARK: - Public Entry Points

    func scheduleStartupCatchUp(conversations: [Conversation]) {
        guard !didScheduleStartupPass else { return }
        didScheduleStartupPass = true

        for conversation in conversations {
            _ = enqueue(
                conversationId: conversation.id,
                conversationSnapshot: conversation,
                messagesSnapshot: nil
            )
        }

        processQueueIfNeeded()
    }

    func scheduleCatchUpAfterMessagesLoad(
        conversation: Conversation,
        messages: [Message]
    ) {
        _ = enqueue(
            conversationId: conversation.id,
            conversationSnapshot: conversation,
            messagesSnapshot: messages
        )

        processQueueIfNeeded()
    }

    // MARK: - Queue

    @discardableResult
    private func enqueue(
        conversationId: String,
        conversationSnapshot: Conversation?,
        messagesSnapshot: [Message]?
    ) -> Bool {
        guard !pendingConversationIds.contains(conversationId) else { return false }

        pendingConversationIds.insert(conversationId)
        pendingJobs.append(CatchUpJob(
            conversationId: conversationId,
            conversationSnapshot: conversationSnapshot,
            messagesSnapshot: messagesSnapshot
        ))
        return true
    }

    private func processQueueIfNeeded() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true

        Task { @MainActor in
            defer { self.isProcessingQueue = false }

            while !self.pendingJobs.isEmpty {
                let job = self.pendingJobs.removeFirst()
                self.pendingConversationIds.remove(job.conversationId)

                await self.process(job)
            }
        }
    }

    private func process(_ job: CatchUpJob) async {
        guard registry.canAttempt(job.conversationId) else {
            return
        }

        do {
            guard let conversation = try resolveConversation(for: job) else {
                registry.record(job.conversationId, outcome: .skipped)
                persistAttempts()
                return
            }

            let messages = try resolveMessages(for: job, conversationId: conversation.id)

            let hasManualTitle = settingsStorage.hasManualDisplayName(for: conversation.id)
            let hasGeneratedTitle = settingsStorage.generatedTitle(for: conversation.id) != nil
            let eligibility = ConversationTitleEligibility.evaluate(
                conversation: conversation,
                messages: messages,
                hasManualTitle: hasManualTitle,
                hasGeneratedTitle: hasGeneratedTitle
            )

            guard case .eligible(let firstUserMessage) = eligibility else {
                registry.record(job.conversationId, outcome: .skipped)
                persistAttempts()
                return
            }

            guard let assistant = firstAssistantMessage(after: firstUserMessage, in: messages) else {
                registry.record(job.conversationId, outcome: .skipped)
                persistAttempts()
                return
            }

            let applied = await ConversationTitleSubAgentService.shared.titleConversationIfEligible(
                conversation: conversation,
                messages: messages,
                preferredAssistantMessage: assistant
            )

            if applied {
                registry.record(job.conversationId, outcome: .success)
            } else {
                registry.record(
                    job.conversationId,
                    outcome: .failed,
                    error: "Namer returned no title"
                )
            }
            persistAttempts()
        } catch {
            registry.record(
                job.conversationId,
                outcome: .failed,
                error: error.localizedDescription
            )
            persistAttempts()
            print("[ConversationTitleMaintenanceService] Catch-up failed for \(job.conversationId): \(error.localizedDescription)")
        }
    }

    private func resolveConversation(for job: CatchUpJob) throws -> Conversation? {
        if let snapshot = job.conversationSnapshot {
            return snapshot
        }

        if let inMemory = ConversationService.shared.conversations.first(where: { $0.id == job.conversationId }) {
            return inMemory
        }

        return try localStore.loadConversation(id: job.conversationId)
    }

    private func resolveMessages(for job: CatchUpJob, conversationId: String) throws -> [Message] {
        if let snapshot = job.messagesSnapshot, !snapshot.isEmpty {
            return snapshot
        }

        return try localStore.loadMessages(for: conversationId)
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

    // MARK: - Persistence

    private func persistAttempts() {
        Self.persistAttempts(registry.attempts, key: attemptsKey)
    }

    private static func loadAttempts(key: String) -> [String: ConversationTitleCatchUpAttempt] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ConversationTitleCatchUpAttempt].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func persistAttempts(_ attempts: [String: ConversationTitleCatchUpAttempt], key: String) {
        guard let data = try? JSONEncoder().encode(attempts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
