//
//  CreateVideoSheet.swift
//  Axon
//
//  Sheet for generating videos via Gemini Veo or OpenAI Sora.
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
    
    private var hasGeminiKey: Bool {
        videoService.hasGeminiKey
    }
    
    private var hasOpenAIKey: Bool {
        videoService.hasOpenAIKey
    }
    
    private var availableProviders: [VideoGenerationProvider] {
        var providers: [VideoGenerationProvider] = []
        if hasGeminiKey { providers.append(.geminiVeo) }
        if hasOpenAIKey { providers.append(.openaiSora) }
        return providers
    }
    
    var body: some View {
        #if os(macOS)
        // macOS: Direct content without NavigationStack to avoid sidebar-like behavior
        sheetContent
            .frame(minWidth: 500, idealWidth: 600, minHeight: 550, idealHeight: 700)
            .alert("Start Video Generation?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Generate") {
                    startGeneration()
                }
            } message: {
                Text("This will generate a \(selectedDuration.displayName) video using \(selectedProvider.displayName).\n\nEstimated cost: \(MediaCostEstimator.formattedCost(estimatedCost))")
            }
            .onAppear {
                if let first = availableProviders.first {
                    selectedProvider = first
                }
            }
        #else
        // iOS: Keep NavigationStack for proper navigation
        NavigationStack {
            sheetContent
                .navigationTitle("Generate Video")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(AppColors.textSecondary)
                    }
                }
                .alert("Start Video Generation?", isPresented: $showConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Generate") {
                        startGeneration()
                    }
                } message: {
                    Text("This will generate a \(selectedDuration.displayName) video using \(selectedProvider.displayName).\n\nEstimated cost: \(MediaCostEstimator.formattedCost(estimatedCost))")
                }
        }
        .onAppear {
            if let first = availableProviders.first {
                selectedProvider = first
            }
        }
        #endif
    }

    private var sheetContent: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    #if os(macOS)
                    // macOS header with title and cancel button
                    HStack {
                        Text("Generate Video")
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(AppColors.textSecondary)
                    }
                    #endif

                    // Header
                    headerSection

                    // Provider selector
                    if availableProviders.count > 1 {
                        providerSection
                    }

                    // Prompt input
                    promptSection

                    // Options
                    optionsSection

                    // Generate button
                    generateButton

                    // Active jobs section
                    if !videoService.activeJobs.isEmpty {
                        activeJobsSection
                    }

                    // Error display
                    if let error = errorMessage {
                        errorView(error)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(AppColors.signalMercury)
            
            Text("Create with \(selectedProvider.displayName)")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)
            
            Text("Describe the video you want to create")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.top)
    }
    
    // MARK: - Provider Section
    
    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
            
            HStack(spacing: 12) {
                ForEach(availableProviders, id: \.self) { provider in
                    ProviderButton(
                        provider: provider,
                        isSelected: selectedProvider == provider
                    ) {
                        selectedProvider = provider
                    }
                }
            }
        }
    }
    
    // MARK: - Prompt Section
    
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
            
            TextEditor(text: $prompt)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(12)
                .background(AppColors.substrateSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
            
            // Prompt tips
            VStack(alignment: .leading, spacing: 4) {
                Text("Tips for better results:")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                
                Text("• Describe the shot type, subject, action, and setting")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                
                Text("• Include lighting and mood details")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Options Section
    
    private var optionsSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                // Size picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Size")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textSecondary)
                    
                    VStack(spacing: 8) {
                        OptionRow(
                            title: "720p Landscape",
                            subtitle: "1280 × 720 (16:9)",
                            isSelected: selectedSize == .landscape720
                        ) { selectedSize = .landscape720 }
                        
                        OptionRow(
                            title: "720p Portrait",
                            subtitle: "720 × 1280 (9:16)",
                            isSelected: selectedSize == .portrait720
                        ) { selectedSize = .portrait720 }
                        
                        OptionRow(
                            title: "1080p Landscape",
                            subtitle: "1920 × 1080 (16:9) - Premium",
                            isSelected: selectedSize == .landscape1080
                        ) { selectedSize = .landscape1080 }
                        
                        OptionRow(
                            title: "1080p Portrait",
                            subtitle: "1080 × 1920 (9:16) - Premium",
                            isSelected: selectedSize == .portrait1080
                        ) { selectedSize = .portrait1080 }
                    }
                }
                
                Divider()
                    .background(AppColors.glassBorder)
                
                // Duration picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Duration")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textSecondary)
                    
                    HStack(spacing: 12) {
                        ForEach(VideoDuration.allCases, id: \.self) { duration in
                            DurationButton(
                                duration: duration,
                                isSelected: selectedDuration == duration
                            ) {
                                selectedDuration = duration
                            }
                        }
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(12)
            
            // Cost estimate
            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(AppColors.textTertiary)
                Text("Estimated cost: \(MediaCostEstimator.formattedCost(estimatedCost))")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                
                // Generation time warning
                Image(systemName: "clock")
                    .foregroundColor(AppColors.textTertiary)
                Text("~1-6 min")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button {
            showConfirmation = true
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                }
                
                Text(isGenerating ? "Starting..." : "Generate Video")
                    .font(AppTypography.bodyMedium(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(prompt.isEmpty || isGenerating ? AppColors.textTertiary : AppColors.signalMercury)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(prompt.isEmpty || isGenerating)
    }
    
    // MARK: - Active Jobs Section
    
    private var activeJobsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In Progress")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
            
            ForEach(videoService.activeJobs) { job in
                ActiveJobRow(job: job) {
                    Task {
                        await videoService.cancelJob(jobId: job.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)
            
            Text(error)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.accentError)
        }
        .padding()
        .background(AppColors.accentError.opacity(0.1))
        .cornerRadius(12)
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
                    // Dismiss sheet - video will generate in background with Live Activity
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

// MARK: - Provider Button

private struct ProviderButton: View {
    let provider: VideoGenerationProvider
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: provider.icon)
                Text(provider.displayName)
                    .font(AppTypography.bodySmall(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? AppColors.signalMercury : AppColors.substrateSecondary)
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Duration Button

private struct DurationButton: View {
    let duration: VideoDuration
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(duration.displayName)
                .font(AppTypography.bodySmall(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isSelected ? AppColors.signalMercury : AppColors.substrateTertiary)
                .foregroundColor(isSelected ? .white : AppColors.textSecondary)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Option Row

private struct OptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)
                    
                    Text(subtitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? AppColors.signalMercury.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active Job Row

private struct ActiveJobRow: View {
    let job: VideoGenerationJob
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Provider icon
            Image(systemName: job.provider.icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 32)
            
            // Job info
            VStack(alignment: .leading, spacing: 4) {
                Text(job.promptPreview)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(job.state.displayName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textSecondary)
                    
                    if let progress = job.progress {
                        Text("\(progress)%")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
            }
            
            Spacer()
            
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
}

#Preview {
    CreateVideoSheet()
}
