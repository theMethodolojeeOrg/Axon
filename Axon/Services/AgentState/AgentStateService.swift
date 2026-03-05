//
//  AgentStateService.swift
//  Axon
//
//  Manages persistent internal thread (agent state) entries.
//

import Foundation
import Combine
import CoreData

@MainActor
final class AgentStateService: ObservableObject {
    static let shared = AgentStateService()

    private let persistence = PersistenceController.shared
    private let deviceIdentity = DeviceIdentity.shared
    private var sovereigntyService: SovereigntyService { SovereigntyService.shared }
    private var aiConsentService: AIConsentService { AIConsentService.shared }

    @Published private(set) var entries: [InternalThreadEntry] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {
        loadLocalEntries()
    }

    // MARK: - Load

    func loadLocalEntries(includeAIOnly: Bool = true) {
        let context = persistence.container.viewContext
        let fetchRequest: NSFetchRequest<InternalThreadEntryEntity> = InternalThreadEntryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        if !includeAIOnly {
            fetchRequest.predicate = NSPredicate(format: "visibility != %@", InternalThreadVisibility.aiOnly.rawValue)
        }

        do {
            let entities = try context.fetch(fetchRequest)
            entries = entities.compactMap { $0.toEntry() }
        } catch {
            self.error = error.localizedDescription
            entries = []
        }
    }

    func latestEntry(includeAIOnly: Bool = false) -> InternalThreadEntry? {
        entries.first(where: { includeAIOnly || $0.visibility != .aiOnly })
    }

    func queryEntries(
        limit: Int? = nil,
        kind: InternalThreadEntryKind? = nil,
        tags: [String] = [],
        searchText: String? = nil,
        includeAIOnly: Bool = false
    ) -> [InternalThreadEntry] {
        var result = entries

        if !includeAIOnly {
            result = result.filter { $0.visibility != .aiOnly }
        }

        if let kind = kind {
            result = result.filter { $0.kind == kind }
        }

        if !tags.isEmpty {
            result = result.filter { entry in
                tags.allSatisfy { tag in entry.tags.contains(tag) }
            }
        }

        if let searchText, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            result = result.filter { entry in
                entry.content.lowercased().contains(query) ||
                entry.tags.contains { $0.lowercased().contains(query) }
            }
        }

        if let limit, limit > 0, result.count > limit {
            result = Array(result.prefix(limit))
        }

        return result
    }

    // MARK: - Create

    func appendEntry(
        kind: InternalThreadEntryKind,
        content: String,
        tags: [String] = [],
        visibility: InternalThreadVisibility = .userVisible,
        origin: InternalThreadOrigin = .ai,
        skipConsent: Bool = false
    ) async throws -> InternalThreadEntry {
        let entry = InternalThreadEntry(
            kind: kind,
            content: content,
            tags: tags,
            visibility: visibility,
            origin: origin,
            covenantId: sovereigntyService.activeCovenant?.id,
            deviceId: deviceIdentity.deviceId ?? "unknown"
        )

        if !skipConsent && requiresAIConsent(for: .agentStateWrite) {
            _ = try await requestAIConsent(additions: [entry], deletions: nil)
        }

        try await saveEntry(entry)
        return entry
    }

    private func saveEntry(_ entry: InternalThreadEntry) async throws {
        let context = persistence.newBackgroundContext()
        try await context.perform {
            let entity = InternalThreadEntryEntity(context: context)
            entity.id = entry.id
            entity.timestamp = entry.timestamp
            entity.kind = entry.kind.rawValue
            entity.content = entry.content
            entity.tags = entry.tags as NSArray
            entity.visibility = entry.visibility.rawValue
            entity.origin = entry.origin.rawValue
            entity.covenantId = entry.covenantId
            entity.deviceId = entry.deviceId
            entity.encryptionContext = entry.encryptionContext

            try self.persistence.saveContext(context)
        }

        entries.insert(entry, at: 0)
    }

    // MARK: - Delete

    func deleteEntries(ids: [String], skipConsent: Bool = false) async throws {
        guard !ids.isEmpty else { return }

        if !skipConsent && requiresAIConsent(for: .agentStateDelete) {
            _ = try await requestAIConsent(additions: nil, deletions: ids)
        }

        let context = persistence.newBackgroundContext()
        try await context.perform {
            let fetchRequest: NSFetchRequest<InternalThreadEntryEntity> = InternalThreadEntryEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)
            let entities = try context.fetch(fetchRequest)
            for entity in entities {
                context.delete(entity)
            }
            try self.persistence.saveContext(context)
        }

        entries.removeAll { ids.contains($0.id) }
    }

    func clearAllEntries(skipConsent: Bool = false) async throws {
        let ids = entries.map { $0.id }
        try await deleteEntries(ids: ids, skipConsent: skipConsent)
    }

    // MARK: - Consent

    private func requiresAIConsent(for category: ActionCategory) -> Bool {
        let action = SovereignAction.category(category)
        let permission = sovereigntyService.checkActionPermission(action)
        switch permission {
        case .preApproved:
            return false
        case .requiresAIConsent, .requiresApproval, .blocked:
            return true
        }
    }

    private func requestAIConsent(
        additions: [InternalThreadEntry]?,
        deletions: [String]?
    ) async throws -> AIAttestation {
        let additionsPayload = additions?.map { entry in
            AgentStateAddition(
                kind: entry.kind.rawValue,
                content: entry.content,
                tags: entry.tags,
                visibility: entry.visibility.rawValue,
                origin: entry.origin.rawValue
            )
        }

        let changes = AgentStateChanges(additions: additionsPayload, deletions: deletions)
        let proposal = CovenantProposal.create(
            type: .modifyAgentState,
            changes: .agentState(changes),
            proposedBy: .ai,
            rationale: "Update internal thread entries."
        )

        let attestation = try await aiConsentService.generateAttestation(
            for: proposal,
            memories: MemoryService.shared.memories
        )

        if attestation.didDecline {
            throw SovereigntyError.aiDeclined(attestation.reasoning)
        }

        return attestation
    }
}

// MARK: - Core Data Mapping

extension InternalThreadEntryEntity {
    func toEntry() -> InternalThreadEntry? {
        guard let id = id,
              let timestamp = timestamp,
              let kindRaw = kind,
              let content = content,
              let visibilityRaw = visibility,
              let originRaw = origin,
              let deviceId = deviceId,
              let kind = InternalThreadEntryKind(rawValue: kindRaw),
              let visibility = InternalThreadVisibility(rawValue: visibilityRaw),
              let origin = InternalThreadOrigin(rawValue: originRaw) else {
            return nil
        }

        return InternalThreadEntry(
            id: id,
            timestamp: timestamp,
            kind: kind,
            content: content,
            tags: tags as? [String] ?? [],
            visibility: visibility,
            origin: origin,
            covenantId: covenantId,
            deviceId: deviceId,
            encryptionContext: encryptionContext
        )
    }
}
