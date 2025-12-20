//
//  Heuristic.swift
//  Axon
//
//  Cognitive compression layer - distills memories into heuristics for
//  efficient context injection and temporal awareness.
//

import Foundation

// MARK: - Heuristic Type

enum HeuristicType: String, Codable, CaseIterable, Identifiable, Sendable {
    case frequency   // Non-temporal tag frequency analysis
    case recency     // Temporal tag patterns (today, this_week)
    case curiosity   // AI-detected intriguing patterns
    case interest    // Long-term engagement trends

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frequency: return "Frequency"
        case .recency: return "Recency"
        case .curiosity: return "Curiosity"
        case .interest: return "Interest"
        }
    }

    var icon: String {
        switch self {
        case .frequency: return "chart.bar.fill"
        case .recency: return "clock.fill"
        case .curiosity: return "sparkles"
        case .interest: return "heart.fill"
        }
    }

    var description: String {
        switch self {
        case .frequency: return "What I keep coming back to"
        case .recency: return "What's been on my mind"
        case .curiosity: return "What draws my attention"
        case .interest: return "What captivates me over time"
        }
    }

    /// Default synthesis intervals in seconds
    var defaultInterval: Int {
        switch self {
        case .frequency: return 86400      // Daily
        case .recency: return 14400        // Every 4 hours
        case .curiosity: return 86400      // Daily
        case .interest: return 604800      // Weekly
        }
    }
}

// MARK: - Heuristic Dimension

enum HeuristicDimension: String, Codable, CaseIterable, Identifiable, Sendable {
    case narrative    // Core story/themes
    case embodiment   // Actionable takeaways
    case emotion      // Feeling states

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .narrative: return "Narrative"
        case .embodiment: return "Embodiment"
        case .emotion: return "Emotion"
        }
    }

    var icon: String {
        switch self {
        case .narrative: return "text.book.closed.fill"
        case .embodiment: return "figure.walk"
        case .emotion: return "heart.text.square.fill"
        }
    }

    var description: String {
        switch self {
        case .narrative: return "Core story and themes"
        case .embodiment: return "Actionable takeaways"
        case .emotion: return "Feeling states and resonance"
        }
    }
}

// MARK: - Heuristic

struct Heuristic: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let type: HeuristicType
    let dimension: HeuristicDimension
    let content: String              // The synthesized insight
    let synthesizedAt: Date
    let sourceTagSample: [String]    // Tags used in synthesis
    let memoryCount: Int             // How many memories were sampled
    let confidence: Double           // Model's confidence (0-1)
    let synthesisRunId: String       // Group heuristics from same run
    var archived: Bool               // Meta-loop: distilled/archived
    let distilledFrom: [String]?     // IDs of heuristics this distilled
    let metadata: [String: String]?  // Extensibility

    init(
        id: String = UUID().uuidString,
        type: HeuristicType,
        dimension: HeuristicDimension,
        content: String,
        synthesizedAt: Date = Date(),
        sourceTagSample: [String] = [],
        memoryCount: Int = 0,
        confidence: Double = 0.8,
        synthesisRunId: String = UUID().uuidString,
        archived: Bool = false,
        distilledFrom: [String]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.dimension = dimension
        self.content = content
        self.synthesizedAt = synthesizedAt
        self.sourceTagSample = sourceTagSample
        self.memoryCount = memoryCount
        self.confidence = confidence
        self.synthesisRunId = synthesisRunId
        self.archived = archived
        self.distilledFrom = distilledFrom
        self.metadata = metadata
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Heuristic, rhs: Heuristic) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.dimension == rhs.dimension &&
        lhs.content == rhs.content &&
        lhs.archived == rhs.archived
    }
}

// MARK: - Synthesis Run

/// Groups heuristics from a single synthesis run
struct HeuristicSynthesisRun: Codable, Identifiable, Sendable {
    let id: String
    let type: HeuristicType
    let startedAt: Date
    let completedAt: Date?
    let heuristicIds: [String]
    let status: SynthesisStatus
    let errorMessage: String?

    enum SynthesisStatus: String, Codable {
        case running
        case completed
        case failed
    }

    init(
        id: String = UUID().uuidString,
        type: HeuristicType,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        heuristicIds: [String] = [],
        status: SynthesisStatus = .running,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.type = type
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.heuristicIds = heuristicIds
        self.status = status
        self.errorMessage = errorMessage
    }
}
