//
//  VideoGenerationService.swift
//  Axon
//
//  Central service for managing video generation jobs.
//  Handles background processing with Live Activity integration.
//

import Foundation
import Combine
#if os(iOS)
import ActivityKit
#endif

/// Central service for managing video generation jobs
/// Handles background processing and Live Activity updates
@MainActor
final class VideoGenerationService: ObservableObject {
    static let shared = VideoGenerationService()
    
    // MARK: - Published Properties
    
    @Published private(set) var activeJobs: [VideoGenerationJob] = []
    @Published private(set) var completedJobs: [VideoGenerationJob] = []
    @Published private(set) var isProcessing = false
    
    // MARK: - Private Properties
    
    private let liveActivityService = LiveActivityService.shared
    private let geminiService = GeminiVideoService.shared
    private let openaiService = OpenAIVideoService.shared
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    
    private init() {
        // Load any persisted jobs on init
        loadPersistedJobs()
    }
    
    // MARK: - Public API
    
    /// Check if Gemini API key is configured
    var hasGeminiKey: Bool {
        (try? APIKeysStorage.shared.getAPIKey(for: .gemini))?.isEmpty == false
    }
    
    /// Check if OpenAI API key is configured
    var hasOpenAIKey: Bool {
        (try? APIKeysStorage.shared.getAPIKey(for: .openai))?.isEmpty == false
    }
    
    /// Start a new video generation job
    /// - Parameters:
    ///   - provider: Video generation provider (Gemini Veo or OpenAI Sora)
    ///   - prompt: Text prompt describing the video
    ///   - size: Video size
    ///   - duration: Video duration
    /// - Returns: The created job
    func startJob(
        provider: VideoGenerationProvider,
        prompt: String,
        size: VideoSize = .landscape720,
        duration: VideoDuration = .standard8
    ) async throws -> VideoGenerationJob {
        // Validate API key
        let apiKey: String
        switch provider {
        case .geminiVeo:
            guard let key = try? APIKeysStorage.shared.getAPIKey(for: .gemini), !key.isEmpty else {
                throw VideoGenerationError.apiKeyMissing(.gemini)
            }
            apiKey = key
        case .openaiSora:
            guard let key = try? APIKeysStorage.shared.getAPIKey(for: .openai), !key.isEmpty else {
                throw VideoGenerationError.apiKeyMissing(.openai)
            }
            apiKey = key
        }
        
        // Create job
        var job = VideoGenerationJob(
            provider: provider,
            prompt: prompt,
            size: size,
            duration: duration
        )
        
        // Add to active jobs
        activeJobs.append(job)
        isProcessing = true
        persistJobs()
        
        // Start Live Activity
        #if os(iOS)
        try? await liveActivityService.startVideoGenerationActivity(for: job)
        #endif
        
        // Start the generation in background
        let jobId = job.id
        pollingTasks[jobId] = Task { [weak self] in
            await self?.processJob(jobId: jobId, apiKey: apiKey)
        }
        
        return job
    }
    
    /// Cancel an in-progress job
    /// - Parameter jobId: Job ID to cancel
    func cancelJob(jobId: String) async {
        // Cancel polling task
        pollingTasks[jobId]?.cancel()
        pollingTasks[jobId] = nil
        
        // Update job state
        if let index = activeJobs.firstIndex(where: { $0.id == jobId }) {
            var job = activeJobs[index]
            job.updateState(.cancelled)
            activeJobs.remove(at: index)
            completedJobs.insert(job, at: 0)
            persistJobs()
            
            // End Live Activity
            #if os(iOS)
            await liveActivityService.endVideoGenerationActivity(jobId: jobId)
            #endif
        }
        
        updateProcessingState()
    }
    
    /// Get a completed job's video URL
    /// - Parameter jobId: Job ID
    /// - Returns: Video URL if available
    func getVideoUrl(jobId: String) -> String? {
        completedJobs.first(where: { $0.id == jobId })?.videoUrl
    }
    
    /// Clear completed jobs
    func clearCompletedJobs() {
        completedJobs.removeAll()
        persistJobs()
    }
    
    // MARK: - Private Methods
    
    private func processJob(jobId: String, apiKey: String) async {
        guard let index = activeJobs.firstIndex(where: { $0.id == jobId }) else { return }
        var job = activeJobs[index]
        
        do {
            // Update to generating state
            job.updateState(.generating)
            updateJob(job)
            
            // Start generation based on provider
            switch job.provider {
            case .geminiVeo:
                try await processGeminiJob(job: &job, apiKey: apiKey)
            case .openaiSora:
                try await processOpenAIJob(job: &job, apiKey: apiKey)
            }
            
            // Update to completed state
            job.updateState(.completed)
            
            // Move to completed
            moveToCompleted(job)
            
            // Record cost
            CostService.shared.recordVideoGeneration(
                provider: job.provider,
                durationSeconds: job.duration.rawValue,
                resolution: job.size.resolution
            )
            
            // Save video to gallery
            if let videoUrl = job.videoUrl {
                await saveToGallery(job: job, videoUrl: videoUrl)
            }
            
        } catch {
            // Handle error
            job.updateState(.failed)
            job.errorMessage = error.localizedDescription
            moveToCompleted(job)
        }
        
        // End Live Activity
        #if os(iOS)
        await liveActivityService.endVideoGenerationActivity(jobId: jobId)
        #endif
        
        // Clean up
        pollingTasks[jobId] = nil
        updateProcessingState()
    }
    
    private func processGeminiJob(job: inout VideoGenerationJob, apiKey: String) async throws {
        // Start generation
        let operationName = try await geminiService.startGeneration(
            apiKey: apiKey,
            prompt: job.prompt,
            model: job.provider.modelName,
            aspectRatio: job.size.aspectRatio,
            durationSeconds: job.duration.rawValue,
            resolution: job.size.resolution
        )
        
        job.operationName = operationName
        updateJob(job)
        
        // Poll for completion
        var status: VeoOperationStatus
        var estimatedProgress = 0
        repeat {
            try await Task.sleep(nanoseconds: 10 * 1_000_000_000)  // 10 seconds
            
            // Check for cancellation
            try Task.checkCancellation()
            
            status = try await geminiService.pollOperation(apiKey: apiKey, operationName: operationName)
            
            // Estimate progress (Gemini doesn't provide it)
            if !status.done {
                estimatedProgress = min(estimatedProgress + 5, 90)
                job.progress = estimatedProgress
                updateJob(job)
                
                // Update Live Activity
                #if os(iOS)
                await liveActivityService.updateVideoGenerationActivity(
                    jobId: job.id,
                    state: .generating,
                    progress: estimatedProgress,
                    statusMessage: "Generating video..."
                )
                #endif
            }
        } while !status.done
        
        // Check for error
        if let error = status.error {
            throw VideoGenerationError.generationFailed(error)
        }
        
        // Download video
        guard let videoUri = status.videoUri else {
            throw VideoGenerationError.generationFailed("No video URI returned")
        }
        
        job.updateState(.downloading)
        job.progress = 95
        updateJob(job)
        
        #if os(iOS)
        await liveActivityService.updateVideoGenerationActivity(
            jobId: job.id,
            state: .downloading,
            progress: 95,
            statusMessage: "Downloading video..."
        )
        #endif
        
        let videoData = try await geminiService.downloadVideo(apiKey: apiKey, videoUri: videoUri)
        
        // Save to local storage and get URL
        let savedUrl = try saveVideoData(videoData, for: job)
        job.videoUrl = savedUrl
        job.progress = 100
    }
    
    private func processOpenAIJob(job: inout VideoGenerationJob, apiKey: String) async throws {
        // Start generation
        let videoId = try await openaiService.startGeneration(
            apiKey: apiKey,
            prompt: job.prompt,
            model: job.provider.modelName,
            size: job.size.rawValue,
            seconds: job.duration.rawValue
        )
        
        job.externalJobId = videoId
        updateJob(job)
        
        // Poll for completion
        var status: SoraJobStatus
        repeat {
            try await Task.sleep(nanoseconds: 5 * 1_000_000_000)  // 5 seconds
            
            // Check for cancellation
            try Task.checkCancellation()
            
            status = try await openaiService.pollJobStatus(apiKey: apiKey, videoId: videoId)
            
            if !status.status.isTerminal {
                job.progress = status.progress
                updateJob(job)
                
                // Update Live Activity
                #if os(iOS)
                await liveActivityService.updateVideoGenerationActivity(
                    jobId: job.id,
                    state: .generating,
                    progress: status.progress,
                    statusMessage: "Generating video..."
                )
                #endif
            }
        } while !status.status.isTerminal
        
        // Check for error
        if let error = status.error {
            throw VideoGenerationError.generationFailed(error)
        }
        
        guard status.status == .completed else {
            throw VideoGenerationError.generationFailed("Video generation did not complete successfully")
        }
        
        // Download video
        job.updateState(.downloading)
        job.progress = 95
        updateJob(job)
        
        #if os(iOS)
        await liveActivityService.updateVideoGenerationActivity(
            jobId: job.id,
            state: .downloading,
            progress: 95,
            statusMessage: "Downloading video..."
        )
        #endif
        
        let videoData = try await openaiService.downloadVideo(apiKey: apiKey, videoId: videoId)
        
        // Save to local storage and get URL
        let savedUrl = try saveVideoData(videoData, for: job)
        job.videoUrl = savedUrl
        job.progress = 100
    }
    
    private func updateJob(_ job: VideoGenerationJob) {
        if let index = activeJobs.firstIndex(where: { $0.id == job.id }) {
            activeJobs[index] = job
            persistJobs()
        }
    }
    
    private func moveToCompleted(_ job: VideoGenerationJob) {
        if let index = activeJobs.firstIndex(where: { $0.id == job.id }) {
            activeJobs.remove(at: index)
        }
        completedJobs.insert(job, at: 0)
        persistJobs()
    }
    
    private func updateProcessingState() {
        isProcessing = !activeJobs.isEmpty
    }
    
    private func saveVideoData(_ data: Data, for job: VideoGenerationJob) throws -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videosPath = documentsPath.appendingPathComponent("GeneratedVideos", isDirectory: true)
        
        // Create directory if needed
        try FileManager.default.createDirectory(at: videosPath, withIntermediateDirectories: true)
        
        let fileName = "\(job.id).mp4"
        let fileUrl = videosPath.appendingPathComponent(fileName)
        
        try data.write(to: fileUrl)
        
        return fileUrl.absoluteString
    }
    
    private func saveToGallery(job: VideoGenerationJob, videoUrl: String) async {
        let itemId = UUID().uuidString
        let item = CreativeItem(
            id: itemId,
            type: .video,
            conversationId: "direct_creation",  // Special marker for directly created items
            messageId: "direct_\(itemId)",
            createdAt: Date(),
            contentURL: videoUrl,
            mimeType: "video/mp4",
            title: "Generated Video (\(job.provider.displayName))",
            prompt: job.prompt
        )
        
        await MainActor.run {
            CreativeGalleryService.shared.addItem(item)
        }
    }
    
    // MARK: - Persistence
    
    private let jobsKey = "video_generation_jobs"
    private let completedJobsKey = "video_generation_completed_jobs"
    
    private func persistJobs() {
        if let activeData = try? JSONEncoder().encode(activeJobs) {
            UserDefaults.standard.set(activeData, forKey: jobsKey)
        }
        if let completedData = try? JSONEncoder().encode(Array(completedJobs.prefix(10))) {
            UserDefaults.standard.set(completedData, forKey: completedJobsKey)
        }
    }
    
    private func loadPersistedJobs() {
        if let activeData = UserDefaults.standard.data(forKey: jobsKey),
           let jobs = try? JSONDecoder().decode([VideoGenerationJob].self, from: activeData) {
            // Filter out any that were in progress (they're stale now)
            activeJobs = jobs.filter { $0.state == .queued }
        }
        if let completedData = UserDefaults.standard.data(forKey: completedJobsKey),
           let jobs = try? JSONDecoder().decode([VideoGenerationJob].self, from: completedData) {
            completedJobs = jobs
        }
    }
}

// MARK: - Errors

enum VideoGenerationError: LocalizedError {
    case apiKeyMissing(APIProvider)
    case generationFailed(String)
    case noVideoGenerated
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing(let provider):
            return "\(provider.displayName) API key not configured. Add it in Settings → API Keys."
        case .generationFailed(let reason):
            return "Video generation failed: \(reason)"
        case .noVideoGenerated:
            return "No video was generated"
        }
    }
}

// MARK: - CostService Extension

extension CostService {
    /// Record a video generation cost
    func recordVideoGeneration(provider: VideoGenerationProvider, durationSeconds: Int, resolution: String) {
        let cost = MediaCostEstimator.estimateVideoCost(
            provider: provider,
            durationSeconds: durationSeconds,
            resolution: resolution
        )
        
        // Use existing mechanism for recording costs
        // This will need to be extended in CostService if not already available
        recordGenericCost(cost, category: "video_generation")
    }
    
    /// Record a generic cost (placeholder - implement if not already available)
    func recordGenericCost(_ cost: Double, category: String) {
        // This would integrate with existing cost tracking
        // For now, just log it
        print("[CostService] Recording \(category) cost: $\(String(format: "%.4f", cost))")
    }
}
