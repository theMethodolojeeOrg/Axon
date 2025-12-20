//
//  WorkspaceService.swift
//  Axon
//
//  Service for managing workspaces - CRUD operations and persistence.
//

import Foundation
import Combine

@MainActor
class WorkspaceService: ObservableObject {
    static let shared = WorkspaceService()

    @Published var workspaces: [Workspace] = []
    @Published var currentWorkspace: Workspace?
    @Published var isLoading = false
    @Published var error: String?

    private let storageKey = "axon_workspaces_data"

    init() {
        loadWorkspaces()
    }

    // MARK: - CRUD Operations

    func createWorkspace(
        name: String,
        description: String?,
        associatedTags: [String],
        iconName: String? = "folder.fill",
        colorHex: String? = nil
    ) -> Workspace {
        let workspace = Workspace(
            name: name,
            description: description,
            associatedTags: associatedTags,
            iconName: iconName,
            colorHex: colorHex
        )

        workspaces.append(workspace)
        saveWorkspaces()

        print("[WorkspaceService] Created workspace: \(workspace.name) with \(associatedTags.count) tags")
        return workspace
    }

    func updateWorkspace(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            var updated = workspace
            updated.updatedAt = Date()
            workspaces[index] = updated

            // Update current workspace reference if it's the same
            if currentWorkspace?.id == workspace.id {
                currentWorkspace = updated
            }

            saveWorkspaces()
            print("[WorkspaceService] Updated workspace: \(workspace.name)")
        }
    }

    func deleteWorkspace(id: String) {
        workspaces.removeAll { $0.id == id }

        if currentWorkspace?.id == id {
            currentWorkspace = nil
        }

        saveWorkspaces()
        print("[WorkspaceService] Deleted workspace: \(id)")
    }

    func getWorkspace(id: String) -> Workspace? {
        return workspaces.first { $0.id == id }
    }

    // MARK: - Conversation Association

    func addConversation(_ conversationId: String, to workspaceId: String) {
        guard var workspace = getWorkspace(id: workspaceId) else { return }
        workspace.addConversation(conversationId)
        updateWorkspace(workspace)
    }

    func removeConversation(_ conversationId: String, from workspaceId: String) {
        guard var workspace = getWorkspace(id: workspaceId) else { return }
        workspace.removeConversation(conversationId)
        updateWorkspace(workspace)
    }

    func workspaceFor(conversationId: String) -> Workspace? {
        return workspaces.first { $0.conversationIds.contains(conversationId) }
    }

    // MARK: - Tag Association

    func addTag(_ tag: String, to workspaceId: String) {
        guard var workspace = getWorkspace(id: workspaceId) else { return }
        workspace.addTag(tag)
        updateWorkspace(workspace)
    }

    func removeTag(_ tag: String, from workspaceId: String) {
        guard var workspace = getWorkspace(id: workspaceId) else { return }
        workspace.removeTag(tag)
        updateWorkspace(workspace)
    }

    // MARK: - Filtering Helpers

    func conversations(for workspace: Workspace) -> [Conversation] {
        let conversationService = ConversationService.shared
        return conversationService.conversations.filter { conversation in
            workspace.conversationIds.contains(conversation.id)
        }
    }

    func memories(for workspace: Workspace) -> [Memory] {
        let memoryViewModel = MemoryViewModel.shared
        let workspaceTags = Set(workspace.associatedTags)

        // Return memories that have at least one tag matching the workspace's associated tags
        return memoryViewModel.memories.filter { memory in
            !Set(memory.tags).isDisjoint(with: workspaceTags)
        }
    }

    // MARK: - Persistence

    private func loadWorkspaces() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            workspaces = []
            print("[WorkspaceService] No saved workspaces found")
            return
        }

        do {
            let decoded = try JSONDecoder().decode([Workspace].self, from: data)
            workspaces = decoded
            print("[WorkspaceService] Loaded \(decoded.count) workspaces")
        } catch {
            print("[WorkspaceService] Failed to decode workspaces: \(error)")
            workspaces = []
        }
    }

    private func saveWorkspaces() {
        do {
            let data = try JSONEncoder().encode(workspaces)
            UserDefaults.standard.set(data, forKey: storageKey)
            print("[WorkspaceService] Saved \(workspaces.count) workspaces")
        } catch {
            print("[WorkspaceService] Failed to save workspaces: \(error)")
            self.error = "Failed to save workspaces: \(error.localizedDescription)"
        }
    }

    // MARK: - Selection

    func selectWorkspace(_ workspace: Workspace?) {
        currentWorkspace = workspace
    }
}
