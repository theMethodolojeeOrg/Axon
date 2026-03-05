//
//  VideoGenerationJob.swift
//  Axon
//
//  Model for tracking video generation jobs.
//  Supports long-running Gemini Veo and OpenAI Sora video generation.
//

import Foundation

// MARK: - Video Generation Provider

/// Video generation provider selection
enum VideoGenerationProvider: String, Codable, Hashable, CaseIterable, Sendable {
    case geminiVeo = "gemini"
    case openaiSora = "openai"
    
    var displayName: String {
        switch self {
        case .geminiVeo: return "Gemini Veo"
        case .openaiSora: return "OpenAI Sora"
        }
    }
    
    var icon: String {
        switch self {
        case .geminiVeo: return "globe"
        case .openaiSora: return "cpu"
        }
    }
    
    var modelName: String {
        switch self {
        case .geminiVeo: return "veo-3.1-generate-preview"
        case .openaiSora: return "sora-2"
        }
    }
    
    var mercuryColorName: String {
        switch self {
        case .geminiVeo: return "mercury"
        case .openaiSora: return "amethyst"
        }
    }
}

// MARK: - Video Generation State

/// State of a video generation job
enum VideoGenerationState: String, Codable, Hashable, Sendable {
    case queued         // Job created, not yet started
    case generating     // Video is being generated
    case downloading    // Video generated, downloading content
    case completed      // Successfully finished
    case failed         // Failed with error
    case cancelled      // User cancelled
    
    var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .generating: return "Generating"
        case .downloading: return "Downloading"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var icon: String {
        switch self {
        case .queued: return "clock"
        case .generating: return "video.badge.waveform"
        case .downloading: return "arrow.down.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
    
    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
    
    var isPulsing: Bool {
        self == .generating || self == .downloading
    }
}

// MARK: - Video Size

/// Video size options for generation
enum VideoSize: String, Codable, CaseIterable, Sendable {
    case landscape720 = "1280x720"
    case portrait720 = "720x1280"
    case landscape1080 = "1920x1080"
    case portrait1080 = "1080x1920"
    
    var displayName: String {
        switch self {
        case .landscape720: return "720p Landscape"
        case .portrait720: return "720p Portrait"
        case .landscape1080: return "1080p Landscape"
        case .portrait1080: return "1080p Portrait"
        }
    }
    
    var aspectRatio: String {
        switch self {
        case .landscape720, .landscape1080: return "16:9"
        case .portrait720, .portrait1080: return "9:16"
        }
    }
    
    var resolution: String {
        switch self {
        case .landscape720, .portrait720: return "720p"
        case .landscape1080, .portrait1080: return "1080p"
        }
    }
    
    var subtitle: String {
        switch self {
        case .landscape720: return "1280 × 720"
        case .portrait720: return "720 × 1280"
        case .landscape1080: return "1920 × 1080"
        case .portrait1080: return "1080 × 1920"
        }
    }
}

// MARK: - Video Duration

/// Video duration options
enum VideoDuration: Int, Codable, CaseIterable, Sendable {
    case short4 = 4
    case medium6 = 6
    case standard8 = 8
    
    var displayName: String {
        "\(rawValue) seconds"
    }
    
    var shortName: String {
        "\(rawValue)s"
    }
}

// MARK: - Video Generation Job

/// A video generation job with all metadata and state
struct VideoGenerationJob: Identifiable, Codable, Sendable {
    let id: String
    let provider: VideoGenerationProvider
    let prompt: String
    let size: VideoSize
    let duration: VideoDuration
    let estimatedCostUSD: Double
    let createdAt: Date
    
    var state: VideoGenerationState
    var startedAt: Date?
    var completedAt: Date?
    var operationName: String?  // For Gemini polling (long-running operation name)
    var externalJobId: String?  // For OpenAI (video job ID)
    var progress: Int?          // 0-100 percentage if available
    var videoUrl: String?       // URL to the final video
    var errorMessage: String?
    
    init(
        id: String = UUID().uuidString,
        provider: VideoGenerationProvider,
        prompt: String,
        size: VideoSize = .landscape720,
        duration: VideoDuration = .standard8
    ) {
        self.id = id
        self.provider = provider
        self.prompt = prompt
        self.size = size
        self.duration = duration
        self.estimatedCostUSD = MediaCostEstimator.estimateVideoCost(
            provider: provider,
            durationSeconds: duration.rawValue,
            resolution: size.resolution
        )
        self.createdAt = Date()
        self.state = .queued
    }
    
    var elapsedSeconds: Int {
        guard let start = startedAt else { return 0 }
        let end = completedAt ?? Date()
        return Int(end.timeIntervalSince(start))
    }
    
    var promptPreview: String {
        if prompt.count <= 80 {
            return prompt
        }
        return String(prompt.prefix(77)) + "..."
    }
    
    /// Mutating helper to update state
    mutating func updateState(_ newState: VideoGenerationState) {
        state = newState
        if newState == .generating && startedAt == nil {
            startedAt = Date()
        }
        if newState.isTerminal && completedAt == nil {
            completedAt = Date()
        }
    }
}

// MARK: - Media Cost Estimator Extension

extension MediaCostEstimator {
    /// Gemini Veo pricing (per second of video)
    static let geminiVideoPricing: [String: Double] = [
        "720p": 0.35,
        "1080p": 0.70
    ]
    
    /// OpenAI Sora pricing (per second of video)
    static let openaiVideoPricing: [String: Double] = [
        "sora-2": 0.20,
        "sora-2-pro": 0.40
    ]
    
    /// Estimate video generation cost
    static func estimateVideoCost(provider: VideoGenerationProvider, durationSeconds: Int, resolution: String) -> Double {
        let perSecond: Double
        switch provider {
        case .geminiVeo:
            perSecond = geminiVideoPricing[resolution] ?? 0.35
        case .openaiSora:
            perSecond = openaiVideoPricing["sora-2"] ?? 0.20
        }
        return perSecond * Double(durationSeconds)
    }
    
    /// Format video cost as friendly string
    static func formattedVideoCost(provider: VideoGenerationProvider, durationSeconds: Int, resolution: String) -> String {
        let cost = estimateVideoCost(provider: provider, durationSeconds: durationSeconds, resolution: resolution)
        return formattedCost(cost)
    }
}
