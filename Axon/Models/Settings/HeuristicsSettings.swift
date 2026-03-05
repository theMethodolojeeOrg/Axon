//
//  HeuristicsSettings.swift
//  Axon
//
//  Heuristics (cognitive compression layer) settings
//

import Foundation

// MARK: - Small Model Optimization

/// Configuration for optimizing context injection for small/quantized models
/// These models benefit from heuristics (compressed insights) rather than raw memories
struct SmallModelOptimization: Codable, Equatable, Sendable {
    /// Enable automatic detection and optimization for small models
    var enabled: Bool = true

    /// Use heuristics-only mode (no raw memories) for detected small models
    var useHeuristicsOnly: Bool = true

    /// Maximum memories to inject for small models (when not using heuristics-only)
    var maxMemoriesForSmallModels: Int = 3

    /// Token budget for context injection in small models
    var smallModelTokenBudget: Int = 500

    /// Skip conversation summary injection for small models
    var skipConversationSummary: Bool = true

    /// Skip conversation history search for small models
    var skipConversationSearch: Bool = true

    /// Model identifiers that should use small model optimization
    /// Matched by substring (e.g., "2B" matches "Qwen3-VL-2B-Instruct-4bit")
    var smallModelPatterns: [String] = [
        "1B", "1.7B", "2B", "3B",           // Parameter counts
        "4bit", "3bit",                      // Heavy quantization
        "SmolLM", "Phi-4-mini",              // Known small models
        "gemma-3-270m", "Qwen3-VL-2B", "Llama-3.2-1B"        // Specific small models
    ]

    /// Check if a model identifier matches small model patterns
    func isSmallModel(_ modelId: String) -> Bool {
        guard enabled else { return false }
        let modelIdLower = modelId.lowercased()
        return smallModelPatterns.contains { pattern in
            modelIdLower.contains(pattern.lowercased())
        }
    }
}

// MARK: - Heuristics Settings

/// Settings for the cognitive compression layer (Heuristics)
struct HeuristicsSettings: Codable, Equatable, Sendable {
    var enabled: Bool = true

    // Per-type synthesis intervals (seconds)
    var frequencyIntervalSeconds: Int = 86400     // Daily
    var recencyIntervalSeconds: Int = 14400       // Every 4 hours
    var curiosityIntervalSeconds: Int = 86400     // Daily
    var interestIntervalSeconds: Int = 604800     // Weekly

    // Meta-synthesis (distillation of old heuristics)
    var metaSynthesisIntervalSeconds: Int = 604800  // Weekly
    var archiveAfterDays: Int = 30                   // Archive heuristics older than this

    // On-device model settings
    var useOnDeviceModels: Bool = true
    var onDeviceModelId: String = "mlx-community/SmolLM2-1.7B-Instruct-4bit"

    // Injection settings
    var contextWindowThreshold: Int = 8000   // Token threshold for injection
    var heuristicsMemoryRatio: Double = 0.3  // 30% heuristics, 70% memories when injecting

    // Small model optimization - use heuristics instead of raw memories for context-constrained models
    var smallModelOptimization: SmallModelOptimization = SmallModelOptimization()

    // Quality thresholds
    var minConfidence: Double = 0.6
    var minTagFrequency: Int = 3  // Ignore rare tags

    /// Get the synthesis interval for a specific heuristic type
    func interval(for type: HeuristicType) -> Int {
        switch type {
        case .frequency: return frequencyIntervalSeconds
        case .recency: return recencyIntervalSeconds
        case .curiosity: return curiosityIntervalSeconds
        case .interest: return interestIntervalSeconds
        }
    }

    /// Set the synthesis interval for a specific heuristic type
    mutating func setInterval(_ seconds: Int, for type: HeuristicType) {
        switch type {
        case .frequency: frequencyIntervalSeconds = seconds
        case .recency: recencyIntervalSeconds = seconds
        case .curiosity: curiosityIntervalSeconds = seconds
        case .interest: interestIntervalSeconds = seconds
        }
    }
}
