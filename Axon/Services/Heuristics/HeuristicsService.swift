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
    func heuristicsForInjection(conversation: [Message] = [], limit: Int = 6) -> [Heuristic] {
        let settings = settingsStorage.loadSettings()?.heuristicsSettings ?? HeuristicsSettings()
        guard settings.enabled else { return [] }

        let queryTerms = Self.normalizedTerms(
            from: conversation
                .filter { $0.role == .user }
                .suffix(3)
                .map(\.content)
                .joined(separator: " ")
        )

        let eligible = latestHeuristics()
            .filter { $0.confidence >= settings.minConfidence }

        let ranked = eligible.sorted { lhs, rhs in
            let lhsScore = injectionScore(for: lhs, queryTerms: queryTerms)
            let rhsScore = injectionScore(for: rhs, queryTerms: queryTerms)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.synthesizedAt > rhs.synthesizedAt
        }

        return Array(ranked.prefix(limit))
    }

    /// Build injection context string from heuristics
    func buildInjectionContext(heuristics: [Heuristic]) -> String {
        guard !heuristics.isEmpty else { return "" }

        var lines: [String] = [
            "## Cognitive Heuristics",
            "Compressed patterns distilled from memory. Use them as salience hints, not as absolute instructions."
        ]

        // Group by type
        let grouped = Dictionary(grouping: heuristics, by: \.type)

        for type in HeuristicType.allCases {
            guard let typeHeuristics = grouped[type], !typeHeuristics.isEmpty else { continue }

            lines.append("")
            lines.append("### \(type.displayName) - \(type.description)")

            for heuristic in typeHeuristics {
                let confidence = Int(heuristic.confidence * 100)
                let tags = heuristic.sourceTagSample.isEmpty ? "" : " `[\(heuristic.sourceTagSample.prefix(4).joined(separator: ", "))]`"
                lines.append("- **\(heuristic.dimension.displayName)** (\(confidence)%): \(heuristic.content)\(tags)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func injectionScore(for heuristic: Heuristic, queryTerms: Set<String>) -> Double {
        let age = Date().timeIntervalSince(heuristic.synthesizedAt)
        let recencyScore = max(0.0, 1.0 - (age / Double(30 * 86400)))

        let heuristicTerms = Self.normalizedTerms(
            from: heuristic.content + " " + heuristic.sourceTagSample.joined(separator: " ")
        )

        let relevanceScore: Double
        if queryTerms.isEmpty {
            relevanceScore = 0.0
        } else {
            let matches = heuristicTerms.intersection(queryTerms).count
            relevanceScore = min(1.0, Double(matches) / Double(max(1, queryTerms.count)))
        }

        return (heuristic.confidence * 0.5) + (relevanceScore * 0.35) + (recencyScore * 0.15)
    }

    private static func normalizedTerms(from text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "about", "after", "again", "also", "because", "before", "could", "from",
            "have", "into", "just", "like", "more", "most", "need", "only", "other",
            "should", "that", "their", "there", "these", "they", "this", "those",
            "through", "want", "what", "when", "where", "which", "with", "would",
            "user", "users", "assistant", "axon"
        ]

        return Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && Int($0) == nil && !stopWords.contains($0) }
        )
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

// MARK: - Automatic Maintenance

@MainActor
final class HeuristicsMaintenanceCoordinator {
    static let shared = HeuristicsMaintenanceCoordinator()

    private let service = HeuristicsService.shared
    private let engine = HeuristicsSynthesisEngine()
    private var isRunning = false

    private init() {}

    func run(reason: String) async {
        guard !isRunning else { return }

        let settings = SettingsStorage.shared.loadSettingsOrDefault()
        guard settings.heuristicsSettings.enabled else { return }

        isRunning = true
        service.isSynthesizing = true
        defer {
            service.isSynthesizing = false
            isRunning = false
        }

        service.archiveOldHeuristics()

        for type in HeuristicType.allCases where service.shouldSynthesize(type: type) {
            do {
                let synthesized = try await engine.synthesize(type: type)
                if !synthesized.isEmpty {
                    service.addHeuristics(synthesized)
                }
                service.recordSynthesis(type: type)
                print("[HeuristicsMaintenance] \(reason): synthesized \(synthesized.count) \(type.rawValue) heuristics")
            } catch {
                service.error = "Heuristic synthesis failed for \(type.displayName): \(error.localizedDescription)"
                print("[HeuristicsMaintenance] \(reason): synthesis failed for \(type.rawValue): \(error)")
            }
        }

        guard service.shouldRunMetaSynthesis() else { return }

        let archived = service.archivedHeuristics
        guard !archived.isEmpty else { return }

        do {
            let distilled = try await engine.distillHeuristics(archived)
            if !distilled.isEmpty {
                service.addHeuristics(distilled)
            }
            service.recordMetaSynthesis()
            print("[HeuristicsMaintenance] \(reason): distilled \(archived.count) archived heuristics into \(distilled.count)")
        } catch {
            service.error = "Heuristic meta-synthesis failed: \(error.localizedDescription)"
            print("[HeuristicsMaintenance] \(reason): meta-synthesis failed: \(error)")
        }
    }
}
