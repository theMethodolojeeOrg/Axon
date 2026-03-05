//
//  CreateVideoSheet.swift
//  Axon
//
//  Studio-style sheet for generating videos via Gemini Veo or OpenAI Sora.
//

import SwiftUI

struct CreateVideoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var videoService = VideoGenerationService.shared

    @State private var prompt = ""
    @State private var selectedProvider: VideoGenerationProvider = .geminiVeo
    @State private var selectedSize: VideoSize = .landscape720
    @State private var selectedDuration: VideoDuration = .standard8
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showConfirmation = false

    private var estimatedCost: Double {
        MediaCostEstimator.estimateVideoCost(
            provider: selectedProvider,
            durationSeconds: selectedDuration.rawValue,
            resolution: selectedSize.resolution
        )
    }

    private var availableProviders: [VideoGenerationProvider] {
        var providers: [VideoGenerationProvider] = []
        if videoService.hasGeminiKey { providers.append(.geminiVeo) }
        if videoService.hasOpenAIKey { providers.append(.openaiSora) }
        return providers
    }

    var body: some View {
        #if os(macOS)
        sheetContent
            .frame(minWidth: 520, idealWidth: 580, minHeight: 580, idealHeight: 720)
            .alert("Start Video Generation?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Generate") { startGeneration() }
            } message: {
                Text("This will generate a \(selectedDuration.displayName) video using \(selectedProvider.displayName).\n\nEstimated cost: \(MediaCostEstimator.formattedCost(estimatedCost))")
            }
            .onAppear {
                if let first = availableProviders.first { selectedProvider = first }
            }
        #else
        sheetContent
            .navigationTitle("Video Studio")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Start Video Generation?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Generate") { startGeneration() }
            } message: {
                Text("This will generate a \(selectedDuration.displayName) video using \(selectedProvider.displayName).\n\nEstimated cost: \(MediaCostEstimator.formattedCost(estimatedCost))")
            }
            .onAppear {
                if let first = availableProviders.first { selectedProvider = first }
            }
        #endif
    }

    private var sheetContent: some View {
        ZStack(alignment: .top) {
            AppColors.substratePrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroBanner

                    VStack(spacing: 20) {
                        #if os(macOS)
                        HStack {
                            Spacer()
                            Button("Cancel") { dismiss() }
                                .foregroundColor(AppColors.textSecondary)
                                .font(AppTypography.bodySmall())
                        }
                        .padding(.top, 4)
                        #endif

                        // Provider selector
                        if availableProviders.count > 1 {
                            providerSection
                        }

                        // Prompt
                        promptSection

                        // Format (aspect ratio + duration in one card)
                        formatSection

                        // Active jobs
                        if !videoService.activeJobs.isEmpty {
                            activeJobsSection
                        }

                        // Cost + Generate
                        bottomSection

                        if let error = errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [AppColors.signalCopper.opacity(0.8), AppColors.signalCopperDark.opacity(0.95)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 120)

            // Decorative film frame shapes
            Group {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.12), lineWidth: 2)
                    .frame(width: 70, height: 46)
                    .offset(x: 260, y: -8)

                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.07), lineWidth: 2)
                    .frame(width: 56, height: 36)
                    .offset(x: 220, y: 14)
            }

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 140, height: 140)
                .offset(x: -40, y: -30)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("Video Studio")
                            .font(AppTypography.titleMedium(.semibold))
                            .foregroundColor(.white)
                    }
                    Text("Powered by \(selectedProvider.displayName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                        .animation(.none, value: selectedProvider)
                }
                Spacer()

                // Cinematic frame badge
                HStack(spacing: 4) {
                    Image(systemName: "film")
                        .font(.system(size: 11))
                    Text(selectedSize.resolution)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: selectedProvider)
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Provider", systemImage: "cpu")
                .font(AppTypography.labelMedium(.semibold))
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 8) {
                ForEach(availableProviders, id: \.self) { provider in
                    VideoProviderChip(
                        label: provider.displayName,
                        icon: provider.icon,
                        isSelected: selectedProvider == provider
                    ) { selectedProvider = provider }
                }
                Spacer()
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scene Description", systemImage: "text.cursor")
                .font(AppTypography.labelMedium(.semibold))
                .foregroundColor(AppColors.textSecondary)

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe your scene… e.g. A golden eagle soaring over misty mountain peaks at sunrise, slow motion, cinematic")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $prompt)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(12)
            }
            .background(AppColors.substrateSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        prompt.isEmpty ? AppColors.glassBorder : AppColors.signalCopper.opacity(0.4),
                        lineWidth: 1.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: prompt.isEmpty)

            // Prompt tips
            promptTips
        }
    }

    private var promptTips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(promptTipChips, id: \.self) { tip in
                    Button {
                        if prompt.isEmpty {
                            prompt = tip
                        } else if !prompt.hasSuffix(tip) {
                            prompt += ", \(tip.lowercased())"
                        }
                    } label: {
                        Text(tip)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.signalCopper)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.signalCopper.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(AppColors.signalCopper.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private let promptTipChips = [
        "Cinematic", "Slow motion", "Aerial shot", "Close-up",
        "Golden hour", "Dramatic lighting", "Handheld camera"
    ]

    // MARK: - Format Section

    private var formatSection: some View {
        VStack(spacing: 16) {
            // Aspect ratio
            VStack(alignment: .leading, spacing: 10) {
                Label("Aspect Ratio", systemImage: "aspectratio")
                    .font(AppTypography.labelMedium(.semibold))
                    .foregroundColor(AppColors.textSecondary)

                HStack(spacing: 10) {
                    VideoFormatTile(
                        label: "720p Landscape",
                        detail: "16:9",
                        isSelected: selectedSize == .landscape720,
                        aspectW: 3, aspectH: 2
                    ) { selectedSize = .landscape720 }

                    VideoFormatTile(
                        label: "720p Portrait",
                        detail: "9:16",
                        isSelected: selectedSize == .portrait720,
                        aspectW: 2, aspectH: 3
                    ) { selectedSize = .portrait720 }

                    VideoFormatTile(
                        label: "1080p",
                        detail: "16:9 ★",
                        isSelected: selectedSize == .landscape1080,
                        aspectW: 3, aspectH: 2
                    ) { selectedSize = .landscape1080 }

                    VideoFormatTile(
                        label: "1080p ↕",
                        detail: "9:16 ★",
                        isSelected: selectedSize == .portrait1080,
                        aspectW: 2, aspectH: 3
                    ) { selectedSize = .portrait1080 }
                }
            }

            Divider().background(AppColors.divider)

            // Duration
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Duration", systemImage: "timer")
                        .font(AppTypography.labelMedium(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                    Text("⏱ ~1–6 min to generate")
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }

                HStack(spacing: 0) {
                    ForEach(VideoDuration.allCases, id: \.self) { duration in
                        DurationSegment(
                            label: duration.displayName,
                            isSelected: selectedDuration == duration
                        ) { selectedDuration = duration }
                    }
                }
                .background(AppColors.substrateSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
            }
        }
        .padding(16)
        .background(AppColors.substrateSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Active Jobs Section

    private var activeJobsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("In Progress", systemImage: "clock.arrow.2.circlepath")
                    .font(AppTypography.labelMedium(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text("\(videoService.activeJobs.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.signalCopper)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(AppColors.signalCopper.opacity(0.12))
                    .clipShape(Capsule())
            }

            ForEach(videoService.activeJobs) { job in
                ActiveVideoJobRow(job: job) {
                    Task { await videoService.cancelJob(jobId: job.id) }
                }
            }
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 14) {
            // Cost row
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textTertiary)
                Text("Est. \(MediaCostEstimator.formattedCost(estimatedCost))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                Text("Runs in background")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 2)

            // Generate button
            Button { showConfirmation = true } label: {
                HStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isGenerating ? "Starting…" : "Generate Video")
                        .font(AppTypography.bodyMedium(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Group {
                        if prompt.isEmpty || isGenerating {
                            AnyView(AppColors.substrateTertiary)
                        } else {
                            AnyView(
                                LinearGradient(
                                    colors: [AppColors.signalCopper, AppColors.signalCopperDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
                )
                .foregroundColor(prompt.isEmpty || isGenerating ? AppColors.textTertiary : .white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(
                    color: prompt.isEmpty ? .clear : AppColors.signalCopper.opacity(0.35),
                    radius: 10, x: 0, y: 5
                )
            }
            .disabled(prompt.isEmpty || isGenerating)
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: prompt.isEmpty)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)
                .font(.system(size: 14))
            Text(error)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.accentError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentError.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accentError.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func startGeneration() {
        errorMessage = nil
        isGenerating = true

        Task {
            do {
                _ = try await videoService.startJob(
                    provider: selectedProvider,
                    prompt: prompt,
                    size: selectedSize,
                    duration: selectedDuration
                )
                await MainActor.run {
                    isGenerating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Video Provider Chip

private struct VideoProviderChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? AppColors.signalCopper : AppColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? AppColors.signalCopper.opacity(0.12) : AppColors.substrateSecondary)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? AppColors.signalCopper.opacity(0.4) : AppColors.glassBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Video Format Tile

private struct VideoFormatTile: View {
    let label: String
    let detail: String
    let isSelected: Bool
    let aspectW: CGFloat
    let aspectH: CGFloat
    let action: () -> Void

    private var tileW: CGFloat {
        let max = Swift.max(aspectW, aspectH)
        return (aspectW / max) * 28
    }
    private var tileH: CGFloat {
        let max = Swift.max(aspectW, aspectH)
        return (aspectH / max) * 28
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? AppColors.signalCopper.opacity(0.15) : AppColors.substrateTertiary)
                        .frame(width: tileW + 8, height: tileH + 8)
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isSelected ? AppColors.signalCopper : AppColors.textTertiary,
                            lineWidth: isSelected ? 1.5 : 1
                        )
                        .frame(width: tileW, height: tileH)
                }
                .frame(width: 44, height: 44)

                VStack(spacing: 1) {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? AppColors.signalCopper : AppColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundColor(isSelected ? AppColors.signalCopper.opacity(0.75) : AppColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? AppColors.signalCopper.opacity(0.08) : AppColors.substrateSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? AppColors.signalCopper.opacity(0.5) : AppColors.glassBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Duration Segment

private struct DurationSegment: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AppColors.signalCopper : Color.clear)
                        .padding(3)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Active Video Job Row

private struct ActiveVideoJobRow: View {
    let job: VideoGenerationJob
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Animated progress ring
            ZStack {
                Circle()
                    .stroke(AppColors.signalCopper.opacity(0.2), lineWidth: 2.5)
                    .frame(width: 32, height: 32)
                if let progress = job.progress {
                    Circle()
                        .trim(from: 0, to: CGFloat(progress) / 100)
                        .stroke(AppColors.signalCopper, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalCopper))
                        .scaleEffect(0.6)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.promptPreview)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(job.state.displayName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                    if let progress = job.progress {
                        Text("· \(progress)%")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalCopper)
                    }
                }
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
    }
}

#Preview {
    CreateVideoSheet()
}
