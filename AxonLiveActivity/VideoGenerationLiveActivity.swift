//
//  VideoGenerationLiveActivity.swift
//  AxonLiveActivity
//
//  Live Activity UI for video generation progress.
//  Shows video generation status in Dynamic Island and Lock Screen.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct VideoGenerationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VideoGenerationActivityAttributes.self) { context in
            // Lock Screen / Notification Center view
            VideoGenerationLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    VideoExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VideoExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    VideoExpandedCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VideoExpandedBottomView(context: context)
                }
            } compactLeading: {
                // Compact leading (left side of pill) - Video icon with pulse
                VideoCompactLeadingView(context: context)
            } compactTrailing: {
                // Compact trailing (right side of pill) - Progress or timer
                VideoCompactTrailingView(context: context)
            } minimal: {
                // Minimal view (when sharing space with other activities)
                VideoMinimalView(context: context)
            }
        }
    }
}

// MARK: - Lock Screen View

struct VideoGenerationLockScreenView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    private var providerColor: Color {
        switch context.attributes.provider {
        case .geminiVeo: return .cyan
        case .openaiSora: return .purple
        }
    }
    
    private var stateColor: Color {
        switch context.state.state {
        case .queued: return .gray
        case .generating: return providerColor
        case .downloading: return .blue
        case .completed: return .green
        case .failed, .cancelled: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with provider and state
            HStack(spacing: 10) {
                // Video icon with pulse
                ZStack {
                    if context.state.state.isPulsing {
                        Circle()
                            .stroke(providerColor.opacity(0.3), lineWidth: 2)
                            .frame(width: 36, height: 36)
                            .scaleEffect(1.2)
                        
                        Circle()
                            .stroke(providerColor.opacity(0.2), lineWidth: 1)
                            .frame(width: 44, height: 44)
                            .scaleEffect(1.4)
                    }
                    
                    Image(systemName: "video.badge.waveform")
                        .font(.title2)
                        .foregroundStyle(providerColor)
                        .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
                }
                .frame(width: 44, height: 44)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(context.attributes.provider.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        // State badge
                        Text(context.state.state.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(stateColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stateColor.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    
                    // Status message or default verb
                    Text(context.state.statusMessage ?? "\(context.attributes.provider.verb)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Timer and progress
                VStack(alignment: .trailing, spacing: 2) {
                    if let startedAt = context.state.startedAt {
                        Text(startedAt, style: .timer)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }
                    
                    if let progress = context.state.progress {
                        Text("\(progress)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Prompt preview
            Text(context.attributes.promptPreview)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            // Progress bar (if available)
            if let progress = context.state.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(providerColor)
                            .frame(width: geo.size.width * CGFloat(progress) / 100, height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            // Footer: Cost and resolution
            HStack {
                Text("\(context.attributes.resolution) • \(context.attributes.durationSeconds)s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("~$\(String(format: "%.2f", context.attributes.estimatedCostUSD))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.85))
    }
}

// MARK: - Dynamic Island Compact Views

struct VideoCompactLeadingView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    private var providerColor: Color {
        switch context.attributes.provider {
        case .geminiVeo: return .cyan
        case .openaiSora: return .purple
        }
    }
    
    var body: some View {
        Image(systemName: "video.badge.waveform")
            .font(.system(size: 14))
            .foregroundStyle(providerColor)
            .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
    }
}

struct VideoCompactTrailingView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    var body: some View {
        if context.state.state == .generating || context.state.state == .downloading {
            if let progress = context.state.progress {
                Text("\(progress)%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let startedAt = context.state.startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else if context.state.state.isTerminal {
            Image(systemName: context.state.state.icon)
                .font(.system(size: 12))
                .foregroundStyle(context.state.state == .completed ? .green : .red)
        }
    }
}

struct VideoMinimalView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    private var providerColor: Color {
        switch context.attributes.provider {
        case .geminiVeo: return .cyan
        case .openaiSora: return .purple
        }
    }
    
    var body: some View {
        Image(systemName: "video.badge.waveform")
            .font(.system(size: 12))
            .foregroundStyle(providerColor)
            .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
    }
}

// MARK: - Dynamic Island Expanded Views

struct VideoExpandedLeadingView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    private var providerColor: Color {
        switch context.attributes.provider {
        case .geminiVeo: return .cyan
        case .openaiSora: return .purple
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if context.state.state.isPulsing {
                    Circle()
                        .stroke(providerColor.opacity(0.3), lineWidth: 1)
                        .frame(width: 28, height: 28)
                }
                
                Image(systemName: "video.badge.waveform")
                    .font(.title2)
                    .foregroundStyle(providerColor)
                    .symbolEffect(.pulse, isActive: context.state.state.isPulsing)
            }
            
            Text(context.attributes.provider.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct VideoExpandedTrailingView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    private var stateColor: Color {
        switch context.state.state {
        case .queued: return .gray
        case .generating: return .cyan
        case .downloading: return .blue
        case .completed: return .green
        case .failed, .cancelled: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(context.state.state.displayName)
                .font(.caption)
                .foregroundStyle(stateColor)
            
            if let startedAt = context.state.startedAt {
                Text(startedAt, style: .timer)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
        }
    }
}

struct VideoExpandedCenterView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    var body: some View {
        VStack(spacing: 2) {
            Text("Video Generation")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text("\(context.attributes.resolution) • \(context.attributes.durationSeconds)s")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct VideoExpandedBottomView: View {
    let context: ActivityViewContext<VideoGenerationActivityAttributes>
    
    private var providerColor: Color {
        switch context.attributes.provider {
        case .geminiVeo: return .cyan
        case .openaiSora: return .purple
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Prompt preview
            Text(context.attributes.promptPreview)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            
            // Progress bar
            if let progress = context.state.progress {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 3)
                            
                            Capsule()
                                .fill(providerColor)
                                .frame(width: geo.size.width * CGFloat(progress) / 100, height: 3)
                        }
                    }
                    .frame(height: 3)
                    
                    Text("\(progress)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if context.state.state == .generating || context.state.state == .downloading {
                HStack(spacing: 4) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                    Text(context.state.statusMessage ?? "\(context.attributes.provider.verb)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Cost estimate
            Text("Estimated cost: ~$\(String(format: "%.2f", context.attributes.estimatedCostUSD))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Previews

#Preview("Lock Screen - Generating", as: .content, using: VideoGenerationActivityAttributes(
    jobId: "video-123",
    provider: .geminiVeo,
    promptPreview: "A serene mountain landscape at sunrise with mist rolling through the valleys",
    estimatedCostUSD: 2.80,
    durationSeconds: 8,
    resolution: "720p"
)) {
    VideoGenerationLiveActivity()
} contentStates: {
    VideoGenerationActivityAttributes.ContentState(
        state: .generating,
        startedAt: Date().addingTimeInterval(-45),
        elapsedSeconds: 45,
        progress: 35,
        statusMessage: "Generating video..."
    )
}

#Preview("Lock Screen - Downloading", as: .content, using: VideoGenerationActivityAttributes(
    jobId: "video-456",
    provider: .openaiSora,
    promptPreview: "A futuristic city with flying cars and neon lights at night",
    estimatedCostUSD: 1.60,
    durationSeconds: 8,
    resolution: "1080p"
)) {
    VideoGenerationLiveActivity()
} contentStates: {
    VideoGenerationActivityAttributes.ContentState(
        state: .downloading,
        startedAt: Date().addingTimeInterval(-180),
        elapsedSeconds: 180,
        progress: 95,
        statusMessage: "Downloading video..."
    )
}

#Preview("Lock Screen - Completed", as: .content, using: VideoGenerationActivityAttributes(
    jobId: "video-789",
    provider: .geminiVeo,
    promptPreview: "A cat playing piano in a jazz club",
    estimatedCostUSD: 1.40,
    durationSeconds: 4,
    resolution: "720p"
)) {
    VideoGenerationLiveActivity()
} contentStates: {
    VideoGenerationActivityAttributes.ContentState(
        state: .completed,
        startedAt: Date().addingTimeInterval(-90),
        elapsedSeconds: 90,
        progress: 100,
        statusMessage: "Video ready!"
    )
}
