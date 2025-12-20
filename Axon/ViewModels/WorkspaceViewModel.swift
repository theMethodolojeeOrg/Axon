//
//  WorkspaceViewModel.swift
//  Axon
//
//  ViewModel for workspace management UI.
//

import Foundation
import Combine

@MainActor
class WorkspaceViewModel: ObservableObject {
    static let shared = WorkspaceViewModel()

    @Published var selectedWorkspace: Workspace?
    @Published var showCreateSheet = false
    @Published var showEditSheet = false
    @Published var editingWorkspace: Workspace?
    @Published var searchText = ""
    @Published var error: String?
    @Published var successMessage: String?

    private let workspaceService = WorkspaceService.shared
    private let memoryViewModel = MemoryViewModel.shared
    private var cancellables = Set<AnyCancellable>()

    var workspaces: [Workspace] {
        workspaceService.workspaces
    }

    var filteredWorkspaces: [Workspace] {
        if searchText.isEmpty {
            return workspaces.sorted { $0.updatedAt > $1.updatedAt }
        }

        let searchLower = searchText.lowercased()
        return workspaces.filter { workspace in
            workspace.name.lowercased().contains(searchLower) ||
            (workspace.description?.lowercased().contains(searchLower) ?? false) ||
            workspace.associatedTags.contains { $0.lowercased().contains(searchLower) }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// All available tags from the memory system for tag picker
    var availableTags: [TagInfo] {
        memoryViewModel.tagInfos
    }

    init() {
        // Listen to workspace service changes
        workspaceService.$workspaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    func createWorkspace(
        name: String,
        description: String?,
        tags: [String],
        iconName: String?,
        colorHex: String?
    ) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Workspace name cannot be empty"
            return
        }

        let workspace = workspaceService.createWorkspace(
            name: name.trimmingCharacters(in: .whitespaces),
            description: description?.trimmingCharacters(in: .whitespaces),
            associatedTags: tags,
            iconName: iconName,
            colorHex: colorHex
        )

        successMessage = "Created workspace '\(workspace.name)'"
        showCreateSheet = false

        // Auto-dismiss success message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.successMessage = nil
        }
    }

    func updateWorkspace(
        _ workspace: Workspace,
        name: String,
        description: String?,
        tags: [String],
        iconName: String?,
        colorHex: String?
    ) {
        var updated = workspace
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.description = description?.trimmingCharacters(in: .whitespaces)
        updated.associatedTags = tags
        updated.iconName = iconName
        updated.colorHex = colorHex

        workspaceService.updateWorkspace(updated)
        successMessage = "Updated workspace '\(updated.name)'"
        showEditSheet = false
        editingWorkspace = nil

        // Auto-dismiss success message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.successMessage = nil
        }
    }

    func deleteWorkspace(_ workspace: Workspace) {
        workspaceService.deleteWorkspace(id: workspace.id)

        if selectedWorkspace?.id == workspace.id {
            selectedWorkspace = nil
        }

        successMessage = "Deleted workspace '\(workspace.name)'"

        // Auto-dismiss success message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.successMessage = nil
        }
    }

    func selectWorkspace(_ workspace: Workspace) {
        selectedWorkspace = workspace
    }

    func deselectWorkspace() {
        selectedWorkspace = nil
    }

    func startEditing(_ workspace: Workspace) {
        editingWorkspace = workspace
        showEditSheet = true
    }

    // MARK: - Workspace Content Helpers

    func conversationCount(for workspace: Workspace) -> Int {
        workspace.conversationIds.count
    }

    func memoryCount(for workspace: Workspace) -> Int {
        workspaceService.memories(for: workspace).count
    }

    func tagCount(for workspace: Workspace) -> Int {
        workspace.associatedTags.count
    }
}
