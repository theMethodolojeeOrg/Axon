//
//  HeuristicsViewModel.swift
//  Axon
//
//  ViewModel for the Heuristics tab in CognitionView.
//  Handles filtering, selection, and synthesis actions.
//

import Foundation
import Combine

@MainActor
class HeuristicsViewModel: ObservableObject {
    static let shared = HeuristicsViewModel()

    // MARK: - Dependencies

    private let heuristicsService = HeuristicsService.shared
    private let synthesisEngine = HeuristicsSynthesisEngine()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Filter State

    @Published var selectedType: HeuristicType?
    @Published var selectedDimension: HeuristicDimension?
    @Published var showArchived = false
    @Published var searchText = ""

    // MARK: - Selection State

    @Published var isSelectionMode = false
    @Published var selectedIds: Set<String> = []
    @Published var selectedHeuristic: Heuristic?

    // MARK: - UI State

    @Published var isLoading = false
    @Published var isSynthesizing = false
    @Published var error: String?
    @Published var successMessage: String?
    @Published var showDeleteConfirmation = false
    @Published var showArchiveConfirmation = false

    // MARK: - Initialization

    private init() {
        setupBindings()
    }

    private func setupBindings() {
        // Forward service state
        heuristicsService.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        heuristicsService.$isSynthesizing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSynthesizing)

        heuristicsService.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    // MARK: - Computed Properties

    var heuristics: [Heuristic] {
        heuristicsService.heuristics
    }

    var filteredHeuristics: [Heuristic] {
        heuristics.filter { heuristic in
            // Archive filter
            guard heuristic.archived == showArchived else { return false }

            // Type filter
            if let type = selectedType, heuristic.type != type {
                return false
            }

            // Dimension filter
            if let dimension = selectedDimension, heuristic.dimension != dimension {
                return false
            }

            // Search filter
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let contentMatch = heuristic.content.lowercased().contains(query)
                let tagMatch = heuristic.sourceTagSample.contains { $0.lowercased().contains(query) }
                if !contentMatch && !tagMatch {
                    return false
                }
            }

            return true
        }
        .sorted { $0.synthesizedAt > $1.synthesizedAt }
    }

    var heuristicsByType: [HeuristicType: [Heuristic]] {
        Dictionary(grouping: filteredHeuristics, by: \.type)
    }

    var selectedCount: Int {
        selectedIds.count
    }

    // MARK: - Tag Info (like MemoryViewModel)

    struct TagInfo: Identifiable, Hashable {
        let tag: String
        let count: Int
        var id: String { tag }
    }

    var tagInfos: [TagInfo] {
        var tagCounts: [String: Int] = [:]

        for heuristic in filteredHeuristics {
            for tag in heuristic.sourceTagSample {
                tagCounts[tag, default: 0] += 1
            }
        }

        return tagCounts
            .map { TagInfo(tag: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    var topTags: [TagInfo] {
        Array(tagInfos.prefix(8))
    }

    // MARK: - Empty State

    var emptyStateTitle: String {
        if showArchived {
            return "No Archived Heuristics"
        }
        if selectedType != nil || selectedDimension != nil {
            return "No Matching Heuristics"
        }
        if !searchText.isEmpty {
            return "No Results"
        }
        return "No Heuristics Yet"
    }

    var emptyStateMessage: String {
        if showArchived {
            return "Archived heuristics from meta-synthesis will appear here."
        }
        if selectedType != nil || selectedDimension != nil {
            return "Try adjusting your filters to see more heuristics."
        }
        if !searchText.isEmpty {
            return "No heuristics match your search query."
        }
        return "Heuristics are synthesized from Axon's memories to capture recurring themes, recent focus, and areas of interest. Tap the synthesize button to generate cognitive shortcuts."
    }

    // MARK: - Selection Actions

    func enterSelectionMode(with id: String? = nil) {
        isSelectionMode = true
        if let id = id {
            selectedIds = [id]
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

        if selectedIds.isEmpty {
            exitSelectionMode()
        }
    }

    func selectAll() {
        selectedIds = Set(filteredHeuristics.map(\.id))
    }

    func deselectAll() {
        selectedIds.removeAll()
    }

    // MARK: - CRUD Actions

    func archive(_ heuristic: Heuristic) {
        if heuristic.archived {
            heuristicsService.unarchiveHeuristic(id: heuristic.id)
            successMessage = "Heuristic unarchived"
        } else {
            heuristicsService.archiveHeuristic(id: heuristic.id)
            successMessage = "Heuristic archived"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
        }
    }

    func delete(_ heuristic: Heuristic) {
        heuristicsService.deleteHeuristic(id: heuristic.id)
        successMessage = "Heuristic deleted"

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
        }
    }

    func archiveSelected() {
        for id in selectedIds {
            if showArchived {
                heuristicsService.unarchiveHeuristic(id: id)
            } else {
                heuristicsService.archiveHeuristic(id: id)
            }
        }

        let action = showArchived ? "unarchived" : "archived"
        successMessage = "\(selectedIds.count) heuristic(s) \(action)"
        exitSelectionMode()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
        }
    }

    func deleteSelected() {
        heuristicsService.deleteHeuristics(ids: selectedIds)
        successMessage = "\(selectedIds.count) heuristic(s) deleted"
        exitSelectionMode()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
        }
    }

    // MARK: - Synthesis Actions

    func synthesize(type: HeuristicType) async {
        isSynthesizing = true
        defer { isSynthesizing = false }

        do {
            let newHeuristics = try await synthesisEngine.synthesize(type: type)
            heuristicsService.addHeuristics(newHeuristics)
            heuristicsService.recordSynthesis(type: type)
            successMessage = "Synthesized \(newHeuristics.count) \(type.displayName) heuristics"
        } catch {
            self.error = error.localizedDescription
            print("[HeuristicsViewModel] Synthesis failed for \(type.rawValue): \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
            self.error = nil
        }
    }

    func synthesizeAll() async {
        isSynthesizing = true
        defer { isSynthesizing = false }

        do {
            let allHeuristics = try await synthesisEngine.synthesizeAll()
            heuristicsService.addHeuristics(allHeuristics)
            for type in HeuristicType.allCases {
                heuristicsService.recordSynthesis(type: type)
            }
            successMessage = "Synthesized \(allHeuristics.count) heuristics across all types"
        } catch {
            self.error = error.localizedDescription
            print("[HeuristicsViewModel] Full synthesis failed: \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
            self.error = nil
        }
    }

    func runMetaSynthesis() async {
        isSynthesizing = true
        defer { isSynthesizing = false }

        let archivedHeuristics = heuristicsService.archivedHeuristics
        guard !archivedHeuristics.isEmpty else {
            successMessage = "No archived heuristics to distill"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.successMessage = nil
            }
            return
        }

        do {
            let distilled = try await synthesisEngine.distillHeuristics(archivedHeuristics)
            heuristicsService.addHeuristics(distilled)
            heuristicsService.recordMetaSynthesis()
            successMessage = "Distilled \(archivedHeuristics.count) heuristics into \(distilled.count) core insights"
        } catch {
            self.error = error.localizedDescription
            print("[HeuristicsViewModel] Meta-synthesis failed: \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
            self.error = nil
        }
    }

    // MARK: - Stats

    func getStats() -> HeuristicsService.HeuristicsStats {
        heuristicsService.getStats()
    }
}
