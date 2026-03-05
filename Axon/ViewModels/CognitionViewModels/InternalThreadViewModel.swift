//
//  InternalThreadViewModel.swift
//  Axon
//
//  ViewModel for internal thread browsing and filtering.
//

import SwiftUI
import Combine

@MainActor
final class InternalThreadViewModel: ObservableObject {
    static let shared = InternalThreadViewModel()

    private let agentStateService = AgentStateService.shared
    private var cancellables = Set<AnyCancellable>()

    @Published var searchText: String = ""
    @Published var selectedKind: InternalThreadEntryKind?
    @Published var includeAIOnly: Bool = false

    @Published var error: String?

    var entries: [InternalThreadEntry] {
        agentStateService.entries
    }

    var filteredEntries: [InternalThreadEntry] {
        var result = entries

        if !includeAIOnly {
            result = result.filter { $0.visibility != .aiOnly }
        }

        if let selectedKind {
            result = result.filter { $0.kind == selectedKind }
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let query = searchText.lowercased()
            result = result.filter { entry in
                entry.content.lowercased().contains(query) ||
                entry.tags.contains { $0.lowercased().contains(query) }
            }
        }

        return result
    }

    private init() {
        agentStateService.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func reload() {
        agentStateService.loadLocalEntries(includeAIOnly: true)
    }
}
