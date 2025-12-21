//
//  VideoGenerationActivityAttributes.swift
//  Axon
//
//  ActivityAttributes model for video generation Live Activity.
//  This file must be added to the main Axon app target.
//
//  Follows the pattern established by SubAgentActivityAttributes.
//

import Foundation
#if os(iOS)
import ActivityKit

struct VideoGenerationActivityAttributes: ActivityAttributes {
    // Static context (set when activity starts, cannot change)
    let jobId: String
    let provider: VideoGenerationActivityProvider
    let promptPreview: String  // First ~80 chars of prompt
    let estimatedCostUSD: Double
    let durationSeconds: Int
    let resolution: String
    
    // Dynamic state (updated during activity lifecycle)
    struct ContentState: Codable, Hashable {
        let state: VideoGenerationActivityState
        let startedAt: Date?
        let elapsedSeconds: Int
        let progress: Int?  // 0-100 percentage if available (Sora provides this)
        let statusMessage: String?
        
        static var initial: ContentState {
            ContentState(
                state: .queued,
                startedAt: nil,
                elapsedSeconds: 0,
                progress: nil,
                statusMessage: nil
            )
        }
    }
}
#endif

// MARK: - Video Generation Activity Provider

/// Provider representation for Live Activity (separate from main VideoGenerationProvider for widget target)
enum VideoGenerationActivityProvider: String, Codable, Hashable {
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
    
    var verb: String {
        switch self {
        case .geminiVeo: return "Creating with Veo"
        case .openaiSora: return "Creating with Sora"
        }
    }
    
    /// Mercury color name for the provider
    var mercuryColorName: String {
        switch self {
        case .geminiVeo: return "mercury"
        case .openaiSora: return "amethyst"
        }
    }
}

// MARK: - Video Generation Activity State

/// State representation for Live Activity
enum VideoGenerationActivityState: String, Codable, Hashable {
    case queued         // Waiting to start
    case generating     // Video is being generated
    case downloading    // Downloading finished video
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

// MARK: - Conversion Helpers (Main App Only)

#if os(iOS)
extension VideoGenerationActivityProvider {
    /// Convert from main app's VideoGenerationProvider
    init(from provider: VideoGenerationProvider) {
        switch provider {
        case .geminiVeo: self = .geminiVeo
        case .openaiSora: self = .openaiSora
        }
    }
}

extension VideoGenerationActivityState {
    /// Convert from main app's VideoGenerationState
    init(from state: VideoGenerationState) {
        switch state {
        case .queued: self = .queued
        case .generating: self = .generating
        case .downloading: self = .downloading
        case .completed: self = .completed
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        }
    }
}
#endif
