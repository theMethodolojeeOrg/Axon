//
//  OpenAIVideoService.swift
//  Axon
//
//  Service for OpenAI Sora video generation.
//  Uses async job model with polling.
//

import Foundation

/// Service for OpenAI Sora video generation
/// Uses async job model with polling
actor OpenAIVideoService {
    static let shared = OpenAIVideoService()
    
    private let baseURL = "https://api.openai.com/v1"
    private let pollingIntervalSeconds: UInt64 = 5
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start video generation, returns job ID for polling
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - prompt: Text prompt describing the video
    ///   - model: Sora model to use (sora-2 or sora-2-pro)
    ///   - size: Video size (e.g., "1280x720")
    ///   - seconds: Duration in seconds (5, 10, 15, 20)
    /// - Returns: Video job ID for polling status
    func startGeneration(
        apiKey: String,
        prompt: String,
        model: String = "sora-2",
        size: String = "1280x720",
        seconds: Int = 8
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/videos")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Build request body following Sora API spec
        let requestBody: [String: Any] = [
            "model": model,
            "input": [
                [
                    "type": "text",
                    "text": prompt
                ]
            ],
            "n": 1,
            "size": size,
            "duration": seconds
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SoraError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SoraError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Parse response to get video job ID
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videoId = json["id"] as? String else {
            throw SoraError.invalidResponse
        }
        
        return videoId
    }
    
    /// Poll job status
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - videoId: Video job ID from startGeneration
    /// - Returns: Job status with progress
    func pollJobStatus(apiKey: String, videoId: String) async throws -> SoraJobStatus {
        let url = URL(string: "\(baseURL)/videos/\(videoId)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SoraError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SoraError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else {
            throw SoraError.invalidResponse
        }
        
        // Map status to our model
        switch status {
        case "queued":
            return SoraJobStatus(status: .queued, progress: 0, error: nil)
        case "in_progress", "rendering":
            // Sora provides progress_pct for rendering jobs
            let progress = json["progress_pct"] as? Int
            return SoraJobStatus(status: .generating, progress: progress, error: nil)
        case "completed":
            return SoraJobStatus(status: .completed, progress: 100, error: nil)
        case "failed":
            let errorDetail = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown error"
            return SoraJobStatus(status: .failed, progress: nil, error: errorDetail)
        default:
            return SoraJobStatus(status: .generating, progress: nil, error: nil)
        }
    }
    
    /// Download completed video
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - videoId: Video job ID
    /// - Returns: Video data
    func downloadVideo(apiKey: String, videoId: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/videos/\(videoId)/content")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SoraError.downloadFailed
        }
        
        return data
    }
    
    /// Generate video with full polling loop (convenience method)
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - prompt: Text prompt
    ///   - model: Sora model
    ///   - size: Video size
    ///   - seconds: Duration
    ///   - onProgress: Progress callback
    /// - Returns: Video data
    func generateVideo(
        apiKey: String,
        prompt: String,
        model: String = "sora-2",
        size: String = "1280x720",
        seconds: Int = 8,
        onProgress: ((SoraJobStatus) async -> Void)? = nil
    ) async throws -> Data {
        // Start generation
        let videoId = try await startGeneration(
            apiKey: apiKey,
            prompt: prompt,
            model: model,
            size: size,
            seconds: seconds
        )
        
        // Poll until complete
        var status: SoraJobStatus
        repeat {
            try await Task.sleep(nanoseconds: pollingIntervalSeconds * 1_000_000_000)
            status = try await pollJobStatus(apiKey: apiKey, videoId: videoId)
            await onProgress?(status)
        } while !status.status.isTerminal
        
        // Check for error
        if let error = status.error {
            throw SoraError.generationFailed(error)
        }
        
        guard status.status == .completed else {
            throw SoraError.generationFailed("Video generation did not complete successfully")
        }
        
        // Download video
        return try await downloadVideo(apiKey: apiKey, videoId: videoId)
    }
}

// MARK: - Models

/// Sora job status
struct SoraJobStatus {
    let status: SoraJobState
    let progress: Int?  // 0-100
    let error: String?
}

/// Sora job state enum
enum SoraJobState: String, Codable {
    case queued
    case generating
    case completed
    case failed
    
    var isTerminal: Bool {
        self == .completed || self == .failed
    }
}

// MARK: - Errors

enum SoraError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case downloadFailed
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI Sora API"
        case .apiError(let statusCode, let message):
            return "Sora API error (\(statusCode)): \(message)"
        case .downloadFailed:
            return "Failed to download video"
        case .generationFailed(let message):
            return "Video generation failed: \(message)"
        }
    }
}
