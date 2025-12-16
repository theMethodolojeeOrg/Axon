//
//  MemoryViewModel.swift
//  Axon
//
//  ViewModel for Memory view state management
//

import SwiftUI
import Combine

// MARK: - Sort Options

enum MemorySortOption: String, CaseIterable {
    case dateNewest = "Newest"
    case dateOldest = "Oldest"
    case confidenceHigh = "Confidence ↓"
    case confidenceLow = "Confidence ↑"
    case mostAccessed = "Most Accessed"

    var icon: String {
        switch self {
        case .dateNewest: return "arrow.down.circle"
        case .dateOldest: return "arrow.up.circle"
        case .confidenceHigh: return "chart.bar.fill"
        case .confidenceLow: return "chart.bar"
        case .mostAccessed: return "eye.fill"
        }
    }
}

// MARK: - Tag Info

struct TagInfo: Identifiable, Hashable {
    let tag: String
    let count: Int

    var id: String { tag }
}

// MARK: - Memory ViewModel

@MainActor
class MemoryViewModel: ObservableObject {
    static let shared = MemoryViewModel()

    // MARK: - Services
    private let memoryService = MemoryService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published State

    // Filtering
    @Published var selectedType: MemoryType?
    @Published var searchText = ""
    @Published var showArchived = false
    @Published var selectedTag: String?
    @Published var sortOption: MemorySortOption = .dateNewest

    // Multi-selection
    @Published var isSelectionMode = false
    @Published var selectedIds: Set<String> = []

    // Sheets
    @Published var showNewMemory = false
    @Published var selectedMemory: Memory?
    @Published var showAllTags = false

    // Confirmation dialogs
    @Published var showDeleteConfirmation = false
    @Published var showArchiveConfirmation = false

    // Toast messages
    @Published var successMessage: String?
    @Published var error: String?

    // MARK: - Computed Properties

    var memories: [Memory] {
        memoryService.memories
    }

    var isLoading: Bool {
        memoryService.isLoading
    }

    /// All unique tags with counts
    var tagInfos: [TagInfo] {
        var tagCounts: [String: Int] = [:]
        for memory in memories {
            // Filter by archive status when counting
            if showArchived != memory.isArchived { continue }
            for tag in memory.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts.map { TagInfo(tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Top tags for quick access (max 8)
    var topTags: [TagInfo] {
        Array(tagInfos.prefix(8))
    }

    var filteredMemories: [Memory] {
        var result = memories

        // Archive filter
        result = result.filter { $0.isArchived == showArchived }

        // Type filter
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }

        // Tag filter
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }

        // Search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.content.localizedCaseInsensitiveContains(searchText) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }

        // Sorting
        switch sortOption {
        case .dateNewest:
            result.sort { $0.createdAt > $1.createdAt }
        case .dateOldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .confidenceHigh:
            result.sort { $0.confidence > $1.confidence }
        case .confidenceLow:
            result.sort { $0.confidence < $1.confidence }
        case .mostAccessed:
            result.sort { $0.accessCount > $1.accessCount }
        }

        return result
    }

    var selectedCount: Int {
        selectedIds.count
    }

    // MARK: - Empty State

    var emptyStateTitle: String {
        if showArchived {
            return "No Archived Memories"
        } else if selectedTag != nil {
            return "No Memories with Tag"
        } else if selectedType != nil {
            return "No \(selectedType!.displayName) Memories"
        } else if !searchText.isEmpty {
            return "No Matches Found"
        } else {
            return "No Memories Yet"
        }
    }

    var emptyStateMessage: String {
        if showArchived {
            return "Archived memories will appear here"
        } else if let tag = selectedTag {
            return "No memories tagged with #\(tag)"
        } else if selectedType != nil || !searchText.isEmpty {
            return "Try adjusting your filters"
        } else {
            return "Memories will be created automatically as you chat"
        }
    }

    // MARK: - Initialization

    private init() {
        // Subscribe to memory service changes
        memoryService.$memories
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        memoryService.$isLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Selection Mode

    func enterSelectionMode(with id: String? = nil) {
        isSelectionMode = true
        selectedIds.removeAll()
        if let id = id {
            selectedIds.insert(id)
        }
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedIds.removeAll()
    }

    func toggleSelection(_ id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    func selectAll() {
        selectedIds = Set(filteredMemories.map { $0.id })
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    // MARK: - Actions

    func loadMemories() async {
        do {
            try await memoryService.getMemories(limit: 100, type: selectedType)
        } catch {
            showError("Error loading memories: \(error.localizedDescription)")
        }
    }

    func deleteMemory(_ memory: Memory) {
        Task {
            do {
                try await memoryService.deleteMemory(id: memory.id)
                showSuccess("Memory deleted")
            } catch {
                showError("Error deleting memory: \(error.localizedDescription)")
            }
        }
    }

    func deleteSelected() {
        let count = selectedIds.count
        Task {
            var successCount = 0
            for id in selectedIds {
                do {
                    try await memoryService.deleteMemory(id: id)
                    successCount += 1
                } catch {
                    print("Error deleting memory \(id): \(error.localizedDescription)")
                }
            }
            exitSelectionMode()
            if successCount == count {
                showSuccess("\(count) memories deleted")
            } else {
                showError("Deleted \(successCount) of \(count) memories")
            }
        }
    }

    func toggleArchive(_ memory: Memory) {
        Task {
            do {
                var newMetadata = memory.metadata
                newMetadata["isArchived"] = .bool(!memory.isArchived)

                _ = try await memoryService.updateMemory(
                    id: memory.id,
                    metadata: newMetadata
                )
                showSuccess(memory.isArchived ? "Memory restored" : "Memory archived")
            } catch {
                showError("Error toggling archive: \(error.localizedDescription)")
            }
        }
    }

    func archiveSelected() {
        let newArchiveState = !showArchived // If viewing archived, we're restoring
        let count = selectedIds.count
        let action = newArchiveState ? "archived" : "restored"

        Task {
            var successCount = 0
            for id in selectedIds {
                if let memory = memories.first(where: { $0.id == id }) {
                    do {
                        var newMetadata = memory.metadata
                        newMetadata["isArchived"] = .bool(newArchiveState)

                        _ = try await memoryService.updateMemory(
                            id: id,
                            metadata: newMetadata
                        )
                        successCount += 1
                    } catch {
                        print("Error archiving memory \(id): \(error.localizedDescription)")
                    }
                }
            }
            exitSelectionMode()
            if successCount == count {
                showSuccess("\(count) memories \(action)")
            } else {
                showError("\(action.capitalized) \(successCount) of \(count) memories")
            }
        }
    }

    func togglePin(_ memory: Memory) {
        Task {
            do {
                var newMetadata = memory.metadata
                newMetadata["isPinned"] = .bool(!memory.isPinned)

                _ = try await memoryService.updateMemory(
                    id: memory.id,
                    metadata: newMetadata
                )
                showSuccess(memory.isPinned ? "Memory unpinned" : "Memory pinned")
            } catch {
                showError("Error toggling pin: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Toast Messages

    private func showSuccess(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.successMessage == message {
                self?.successMessage = nil
            }
        }
    }

    private func showError(_ message: String) {
        error = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.error == message {
                self?.error = nil
            }
        }
    }
}
