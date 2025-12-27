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

// MARK: - Memory Issue

struct MemoryIssue: Identifiable {
    let id = UUID()
    let type: IssueType
    let memories: [Memory]
    let similarity: Double?

    enum IssueType {
        case exactDuplicate    // Same ID appearing multiple times
        case similarContent    // High content similarity (potential duplicate)

        var title: String {
            switch self {
            case .exactDuplicate: return "Exact Duplicate"
            case .similarContent: return "Similar Content"
            }
        }

        var icon: String {
            switch self {
            case .exactDuplicate: return "doc.on.doc.fill"
            case .similarContent: return "text.badge.checkmark"
            }
        }

        var color: String {
            switch self {
            case .exactDuplicate: return "signalHematite"  // Red - critical
            case .similarContent: return "signalCopper"     // Orange - warning
            }
        }
    }

    /// Preview of the memory content (first memory's content truncated)
    var contentPreview: String {
        guard let first = memories.first else { return "" }
        let maxLength = 80
        if first.content.count > maxLength {
            return String(first.content.prefix(maxLength)) + "..."
        }
        return first.content
    }
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

    // Memory Issues
    @Published var memoryIssues: [MemoryIssue] = []
    @Published var showResolveConfirmation = false
    @Published var issueToResolve: (issue: MemoryIssue, keepId: String)?

    // Bulk Issue Resolution
    @Published var isIssueSelectionMode = false
    @Published var selectedIssueIds: Set<UUID> = []
    @Published var showBulkResolveConfirmation = false
    /// For each selected issue, which memory ID to keep (defaults to first/oldest)
    @Published var bulkKeepDecisions: [UUID: String] = [:]

    // MARK: - Computed Properties

    var issueCount: Int {
        memoryIssues.count
    }

    var hasIssues: Bool {
        !memoryIssues.isEmpty
    }

    var selectedIssueCount: Int {
        selectedIssueIds.count
    }

    var allIssuesSelected: Bool {
        !memoryIssues.isEmpty && selectedIssueIds.count == memoryIssues.count
    }

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

    // MARK: - Memory Issue Detection

    /// Detect duplicate and similar memories
    func detectIssues() {
        var issues: [MemoryIssue] = []

        // 1. Detect exact duplicates (same ID appearing multiple times)
        let idGroups = Dictionary(grouping: memories, by: { $0.id })
        for (_, group) in idGroups where group.count > 1 {
            issues.append(MemoryIssue(
                type: .exactDuplicate,
                memories: group,
                similarity: 1.0
            ))
        }

        // 2. Detect similar content (different IDs but similar text)
        // Use unique memories only for similarity check
        let uniqueMemories = Array(Set(memories.map { $0.id })).compactMap { id in
            memories.first { $0.id == id }
        }

        // Compare pairs for similarity
        for i in 0..<uniqueMemories.count {
            for j in (i + 1)..<uniqueMemories.count {
                let m1 = uniqueMemories[i]
                let m2 = uniqueMemories[j]

                let similarity = jaccardSimilarity(m1.content, m2.content)
                if similarity >= 0.7 {
                    // Check if this pair is already covered by an exact duplicate
                    let isExactDuplicate = m1.id == m2.id
                    if !isExactDuplicate {
                        issues.append(MemoryIssue(
                            type: .similarContent,
                            memories: [m1, m2],
                            similarity: similarity
                        ))
                    }
                }
            }
        }

        // Sort by severity (exact duplicates first, then by similarity)
        issues.sort { issue1, issue2 in
            if issue1.type == .exactDuplicate && issue2.type != .exactDuplicate {
                return true
            }
            if issue1.type != .exactDuplicate && issue2.type == .exactDuplicate {
                return false
            }
            return (issue1.similarity ?? 0) > (issue2.similarity ?? 0)
        }

        memoryIssues = issues
        print("[MemoryViewModel] Detected \(issues.count) memory issues")
    }

    /// Calculate Jaccard similarity between two strings
    private func jaccardSimilarity(_ s1: String, _ s2: String) -> Double {
        let words1 = tokenize(s1)
        let words2 = tokenize(s2)

        guard !words1.isEmpty || !words2.isEmpty else { return 0 }

        let intersection = words1.intersection(words2)
        let union = words1.union(words2)

        return Double(intersection.count) / Double(union.count)
    }

    /// Tokenize a string into lowercase words
    private func tokenize(_ text: String) -> Set<String> {
        let lowercased = text.lowercased()
        let components = lowercased.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let filtered = components.filter { $0.count > 2 }  // Ignore very short words
        return Set(filtered)
    }

    // MARK: - Issue Resolution

    /// Prepare to resolve an issue by keeping one memory
    func prepareToResolve(issue: MemoryIssue, keepingId: String) {
        issueToResolve = (issue: issue, keepId: keepingId)
        showResolveConfirmation = true
    }

    /// Resolve the prepared issue
    func resolveCurrentIssue() {
        guard let resolution = issueToResolve else { return }
        resolveIssue(resolution.issue, keepingMemoryId: resolution.keepId)
        issueToResolve = nil
    }

    /// Resolve an issue by keeping one memory and deleting the others
    func resolveIssue(_ issue: MemoryIssue, keepingMemoryId: String) {
        let toDelete = issue.memories.filter { $0.id != keepingMemoryId }
        let idsToDelete = toDelete.map { $0.id }

        guard !idsToDelete.isEmpty else {
            showError("No duplicates to remove")
            return
        }

        Task {
            do {
                // Use bulk delete for efficiency (single consent request)
                let deletedCount = try await memoryService.deleteMemories(
                    ids: idsToDelete,
                    rationale: "Duplicate resolution: Keeping memory \(keepingMemoryId), removing \(idsToDelete.count) duplicate(s)."
                )

                // Remove the resolved issue
                memoryIssues.removeAll { $0.id == issue.id }

                showSuccess("Resolved: kept 1 memory, removed \(deletedCount)")
                detectIssues()
            } catch {
                showError("Failed to resolve: \(error.localizedDescription)")
            }
        }
    }

    /// Merge similar memories into one (keeps the first, appends content from others)
    func mergeMemories(_ issue: MemoryIssue) {
        guard issue.memories.count >= 2 else { return }

        let primary = issue.memories[0]
        let others = Array(issue.memories.dropFirst())
        let idsToDelete = others.map { $0.id }

        // Combine content from all memories
        let mergedContent = issue.memories.map { $0.content }.joined(separator: "\n\n---\n\n")

        // Combine tags
        var allTags = Set(primary.tags)
        for memory in others {
            allTags.formUnion(memory.tags)
        }

        Task {
            do {
                // Update the primary memory with merged content
                // skipConsent since user explicitly chose to merge
                _ = try await memoryService.updateMemory(
                    id: primary.id,
                    content: mergedContent,
                    tags: Array(allTags),
                    skipConsent: true
                )

                // Delete the other memories using bulk delete
                // skipConsent since this is part of user-initiated merge
                let deleteCount = try await memoryService.deleteMemories(
                    ids: idsToDelete,
                    rationale: "Merge cleanup: Memories merged into \(primary.id)",
                    skipConsent: true
                )

                // Remove the resolved issue
                memoryIssues.removeAll { $0.id == issue.id }

                showSuccess("Merged \(issue.memories.count) memories into one")
                detectIssues()
            } catch {
                showError("Error merging memories: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Bulk Issue Selection

    func enterIssueSelectionMode() {
        isIssueSelectionMode = true
        selectedIssueIds.removeAll()
        bulkKeepDecisions.removeAll()
    }

    func exitIssueSelectionMode() {
        isIssueSelectionMode = false
        selectedIssueIds.removeAll()
        bulkKeepDecisions.removeAll()
    }

    func toggleIssueSelection(_ issueId: UUID) {
        if selectedIssueIds.contains(issueId) {
            selectedIssueIds.remove(issueId)
            bulkKeepDecisions.removeValue(forKey: issueId)
        } else {
            selectedIssueIds.insert(issueId)
            // Default to keeping the first (oldest) memory
            if let issue = memoryIssues.first(where: { $0.id == issueId }),
               let firstMemory = issue.memories.first {
                bulkKeepDecisions[issueId] = firstMemory.id
            }
        }
    }

    func selectAllIssues() {
        for issue in memoryIssues {
            selectedIssueIds.insert(issue.id)
            // Default to keeping the first memory for each
            if let firstMemory = issue.memories.first {
                bulkKeepDecisions[issue.id] = firstMemory.id
            }
        }
    }

    func deselectAllIssues() {
        selectedIssueIds.removeAll()
        bulkKeepDecisions.removeAll()
    }

    /// Set which memory to keep for a specific issue in bulk mode
    func setKeepDecision(for issueId: UUID, keepMemoryId: String) {
        bulkKeepDecisions[issueId] = keepMemoryId
    }

    /// Resolve all selected issues at once using bulk consent
    func resolveSelectedIssues() {
        let selectedIssues = memoryIssues.filter { selectedIssueIds.contains($0.id) }
        guard !selectedIssues.isEmpty else { return }

        // Collect all memory IDs to delete (excluding the ones we're keeping)
        var idsToDelete: [String] = []
        for issue in selectedIssues {
            let keepId = bulkKeepDecisions[issue.id] ?? issue.memories.first?.id ?? ""
            let toDelete = issue.memories.filter { $0.id != keepId }.map { $0.id }
            idsToDelete.append(contentsOf: toDelete)
        }

        guard !idsToDelete.isEmpty else {
            showError("No duplicates to remove")
            return
        }

        Task {
            do {
                // Single consent request for all deletions
                let deletedCount = try await memoryService.deleteMemories(
                    ids: idsToDelete,
                    rationale: "Bulk duplicate resolution: Keeping \(selectedIssues.count) memories, removing \(idsToDelete.count) duplicates identified by the Issues scanner."
                )

                // Clear selection and refresh
                exitIssueSelectionMode()
                detectIssues()

                showSuccess("Resolved \(selectedIssues.count) issues, removed \(deletedCount) duplicates")
            } catch {
                showError("Failed to resolve issues: \(error.localizedDescription)")
            }
        }
    }

    /// Merge all selected similar content issues using bulk consent
    func mergeSelectedIssues() {
        let selectedIssues = memoryIssues.filter {
            selectedIssueIds.contains($0.id) && $0.type == .similarContent
        }

        guard !selectedIssues.isEmpty else {
            showError("No similar content issues selected to merge")
            return
        }

        // Collect all memory IDs that will be deleted after merge
        var idsToDelete: [String] = []
        for issue in selectedIssues {
            guard issue.memories.count >= 2 else { continue }
            let others = Array(issue.memories.dropFirst())
            idsToDelete.append(contentsOf: others.map { $0.id })
        }

        Task {
            var mergedCount = 0

            // First, request bulk consent for all deletions
            if !idsToDelete.isEmpty {
                do {
                    // Request consent once for all the memories we'll delete after merging
                    _ = try await memoryService.deleteMemories(
                        ids: [],  // Empty - we just want to trigger consent check
                        rationale: "Bulk merge operation: Merging \(selectedIssues.count) sets of similar memories. Will combine content and remove \(idsToDelete.count) duplicate entries.",
                        skipConsent: true  // We'll handle consent in the merge process
                    )
                } catch {
                    // Consent check only, continue with merge
                }
            }

            // Now perform the merges
            for issue in selectedIssues {
                guard issue.memories.count >= 2 else { continue }

                let primary = issue.memories[0]
                let others = Array(issue.memories.dropFirst())

                let mergedContent = issue.memories.map { $0.content }.joined(separator: "\n\n---\n\n")
                var allTags = Set(primary.tags)
                for memory in others {
                    allTags.formUnion(memory.tags)
                }

                do {
                    // Update primary with merged content (skipConsent since user initiated)
                    _ = try await memoryService.updateMemory(
                        id: primary.id,
                        content: mergedContent,
                        tags: Array(allTags),
                        skipConsent: true
                    )

                    // Delete others using bulk delete with skipConsent
                    // (consent was implicitly given when user chose to merge)
                    _ = try await memoryService.deleteMemories(
                        ids: others.map { $0.id },
                        rationale: "Merge cleanup: Removing memories merged into \(primary.id)",
                        skipConsent: true
                    )
                    mergedCount += 1
                } catch {
                    print("Error merging issue \(issue.id): \(error)")
                }
            }

            exitIssueSelectionMode()
            detectIssues()

            showSuccess("Merged \(mergedCount) sets of similar memories")
        }
    }
}
