//
//  HeuristicsService.swift
//  Axon
//
//  Service for managing heuristics - cognitive compression of memories into
//  distilled insights for efficient context injection.
//

import Foundation
import Combine

@MainActor
class HeuristicsService: ObservableObject {
    static let shared = HeuristicsService()

    // MARK: - Published State

    @Published var heuristics: [Heuristic] = []
    @Published var isLoading = false
    @Published var isSynthesizing = false
    @Published var lastSynthesisTimes: [HeuristicType: Date] = [:]
    @Published var lastMetaSynthesisAt: Date?
    @Published var error: String?

    // MARK: - Dependencies

    private let memoryService = MemoryService.shared
    private let settingsStorage = SettingsStorage.shared

    // MARK: - Storage

    private let storageKey = "heuristics_data"
    private let synthesisTimesKey = "heuristics_synthesis_times"
    private let metaSynthesisTimeKey = "heuristics_meta_synthesis_time"

    // MARK: - Initialization

    private init() {
        loadHeuristics()
        loadSynthesisTimes()
    }

    // MARK: - CRUD Operations

    func loadHeuristics() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            heuristics = []
            return
        }

        do {
            heuristics = try JSONDecoder().decode([Heuristic].self, from: data)
            print("[HeuristicsService] Loaded \(heuristics.count) heuristics")
        } catch {
            print("[HeuristicsService] Failed to decode heuristics: \(error)")
            heuristics = []
        }
    }

    func saveHeuristics() {
        do {
            let data = try JSONEncoder().encode(heuristics)
            UserDefaults.standard.set(data, forKey: storageKey)
            print("[HeuristicsService] Saved \(heuristics.count) heuristics")
        } catch {
            print("[HeuristicsService] Failed to encode heuristics: \(error)")
        }
    }

    private func loadSynthesisTimes() {
        if let data = UserDefaults.standard.data(forKey: synthesisTimesKey),
           let times = try? JSONDecoder().decode([String: Date].self, from: data) {
            lastSynthesisTimes = Dictionary(uniqueKeysWithValues: times.compactMap { key, value in
                guard let type = HeuristicType(rawValue: key) else { return nil }
                return (type, value)
            })
        }

        if let metaTime = UserDefaults.standard.object(forKey: metaSynthesisTimeKey) as? Date {
            lastMetaSynthesisAt = metaTime
        }
    }

    private func saveSynthesisTimes() {
        let times = Dictionary(uniqueKeysWithValues: lastSynthesisTimes.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(times) {
            UserDefaults.standard.set(data, forKey: synthesisTimesKey)
        }

        if let metaTime = lastMetaSynthesisAt {
            UserDefaults.standard.set(metaTime, forKey: metaSynthesisTimeKey)
        }
    }

    func addHeuristic(_ heuristic: Heuristic) {
        heuristics.append(heuristic)
        saveHeuristics()
    }

    func addHeuristics(_ newHeuristics: [Heuristic]) {
        heuristics.append(contentsOf: newHeuristics)
        saveHeuristics()
    }

    func updateHeuristic(_ heuristic: Heuristic) {
        if let index = heuristics.firstIndex(where: { $0.id == heuristic.id }) {
            heuristics[index] = heuristic
            saveHeuristics()
        }
    }

    func archiveHeuristic(id: String) {
        if let index = heuristics.firstIndex(where: { $0.id == id }) {
            heuristics[index].archived = true
            saveHeuristics()
        }
    }

    func unarchiveHeuristic(id: String) {
        if let index = heuristics.firstIndex(where: { $0.id == id }) {
            heuristics[index].archived = false
            saveHeuristics()
        }
    }

    func deleteHeuristic(id: String) {
        heuristics.removeAll { $0.id == id }
        saveHeuristics()
    }

    func deleteHeuristics(ids: Set<String>) {
        heuristics.removeAll { ids.contains($0.id) }
        saveHeuristics()
    }

    // MARK: - Queries

    /// Get all active (non-archived) heuristics
    var activeHeuristics: [Heuristic] {
        heuristics.filter { !$0.archived }
    }

    /// Get archived heuristics
    var archivedHeuristics: [Heuristic] {
        heuristics.filter { $0.archived }
    }

    /// Get heuristics by type
    func heuristics(for type: HeuristicType) -> [Heuristic] {
        activeHeuristics.filter { $0.type == type }
    }

    /// Get heuristics by dimension
    func heuristics(for dimension: HeuristicDimension) -> [Heuristic] {
        activeHeuristics.filter { $0.dimension == dimension }
    }

    /// Get heuristics for a specific type and dimension
    func heuristics(type: HeuristicType, dimension: HeuristicDimension) -> [Heuristic] {
        activeHeuristics.filter { $0.type == type && $0.dimension == dimension }
    }

    /// Get the most recent heuristic for each type/dimension combination
    func latestHeuristics() -> [Heuristic] {
        var latest: [String: Heuristic] = [:]

        for heuristic in activeHeuristics {
            let key = "\(heuristic.type.rawValue)-\(heuristic.dimension.rawValue)"
            if let existing = latest[key] {
                if heuristic.synthesizedAt > existing.synthesizedAt {
                    latest[key] = heuristic
                }
            } else {
                latest[key] = heuristic
            }
        }

        return Array(latest.values).sorted { $0.synthesizedAt > $1.synthesizedAt }
    }

    // MARK: - Injection Helpers

    /// Get heuristics suitable for injection into prompts
    /// Returns the most relevant heuristics based on type and recency
    func heuristicsForInjection(limit: Int = 6) -> [Heuristic] {
        let settings = settingsStorage.loadSettings()?.heuristicsSettings ?? HeuristicsSettings()

        // Get latest heuristics above confidence threshold
        let eligible = latestHeuristics()
            .filter { $0.confidence >= settings.minConfidence }

        return Array(eligible.prefix(limit))
    }

    /// Build injection context string from heuristics
    func buildInjectionContext(heuristics: [Heuristic]) -> String {
        guard !heuristics.isEmpty else { return "" }

        var lines: [String] = ["<heuristics>"]

        // Group by type
        let grouped = Dictionary(grouping: heuristics, by: \.type)

        for type in HeuristicType.allCases {
            guard let typeHeuristics = grouped[type], !typeHeuristics.isEmpty else { continue }

            lines.append("  <\(type.rawValue) description=\"\(type.description)\">")

            for heuristic in typeHeuristics {
                lines.append("    <\(heuristic.dimension.rawValue)>")
                lines.append("      \(heuristic.content)")
                lines.append("    </\(heuristic.dimension.rawValue)>")
            }

            lines.append("  </\(type.rawValue)>")
        }

        lines.append("</heuristics>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Scheduling

    /// Check if synthesis should run for a given type
    func shouldSynthesize(type: HeuristicType) -> Bool {
        let settings = settingsStorage.loadSettings()?.heuristicsSettings ?? HeuristicsSettings()
        guard settings.enabled else { return false }

        let interval = settings.interval(for: type)
        guard let lastSynthesis = lastSynthesisTimes[type] else {
            return true // Never synthesized
        }

        return Date().timeIntervalSince(lastSynthesis) >= Double(interval)
    }

    /// Check if meta-synthesis should run
    func shouldRunMetaSynthesis() -> Bool {
        let settings = settingsStorage.loadSettings()?.heuristicsSettings ?? HeuristicsSettings()
        guard settings.enabled else { return false }

        guard let lastMeta = lastMetaSynthesisAt else {
            // Only run meta-synthesis if we have archived heuristics
            return !archivedHeuristics.isEmpty
        }

        return Date().timeIntervalSince(lastMeta) >= Double(settings.metaSynthesisIntervalSeconds)
    }

    /// Record that synthesis was performed for a type
    func recordSynthesis(type: HeuristicType) {
        lastSynthesisTimes[type] = Date()
        saveSynthesisTimes()
    }

    /// Record that meta-synthesis was performed
    func recordMetaSynthesis() {
        lastMetaSynthesisAt = Date()
        saveSynthesisTimes()
    }

    // MARK: - Auto-Archive

    /// Archive heuristics older than the configured threshold
    func archiveOldHeuristics() {
        let settings = settingsStorage.loadSettings()?.heuristicsSettings ?? HeuristicsSettings()
        let threshold = Date().addingTimeInterval(-Double(settings.archiveAfterDays * 86400))

        var modified = false
        for index in heuristics.indices {
            if !heuristics[index].archived && heuristics[index].synthesizedAt < threshold {
                heuristics[index].archived = true
                modified = true
            }
        }

        if modified {
            saveHeuristics()
            print("[HeuristicsService] Archived old heuristics")
        }
    }

    // MARK: - Stats

    struct HeuristicsStats {
        let total: Int
        let active: Int
        let archived: Int
        let byType: [HeuristicType: Int]
        let byDimension: [HeuristicDimension: Int]
        let averageConfidence: Double
        let lastSynthesis: Date?
    }

    func getStats() -> HeuristicsStats {
        let active = activeHeuristics
        let byType = Dictionary(grouping: active, by: \.type).mapValues { $0.count }
        let byDimension = Dictionary(grouping: active, by: \.dimension).mapValues { $0.count }
        let avgConfidence = active.isEmpty ? 0 : active.map(\.confidence).reduce(0, +) / Double(active.count)
        let lastSynthesis = active.map(\.synthesizedAt).max()

        return HeuristicsStats(
            total: heuristics.count,
            active: active.count,
            archived: archivedHeuristics.count,
            byType: byType,
            byDimension: byDimension,
            averageConfidence: avgConfidence,
            lastSynthesis: lastSynthesis
        )
    }
}
