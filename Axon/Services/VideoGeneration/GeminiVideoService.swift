//
//  GeminiVideoService.swift
//  Axon
//
//  Service for Gemini Veo 3.1 video generation.
//  Uses long-running operation pattern with polling.
//

import Foundation

/// Service for Gemini Veo video generation
/// Uses long-running operation pattern with polling
actor GeminiVideoService {
    static let shared = GeminiVideoService()
    
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private let pollingIntervalSeconds: UInt64 = 10
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start video generation, returns operation name for polling
    /// - Parameters:
    ///   - apiKey: Gemini API key
    ///   - prompt: Text prompt describing the video
    ///   - model: Veo model to use (default: veo-3.1-generate-preview)
    ///   - aspectRatio: Aspect ratio (16:9 or 9:16)
    ///   - durationSeconds: Duration in seconds (5-8)
    ///   - resolution: Video resolution (720p or 1080p)
    /// - Returns: Operation name for polling status
    func startGeneration(
        apiKey: String,
        prompt: String,
        model: String = "veo-3.1-generate-preview",
        aspectRatio: String = "16:9",
        durationSeconds: Int = 8,
        resolution: String = "720p"
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/models/\(model):predictLongRunning?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body following Veo API spec
        let requestBody: [String: Any] = [
            "instances": [
                [
                    "prompt": prompt
                ]
            ],
            "parameters": [
                "aspectRatio": aspectRatio,
                "durationSeconds": durationSeconds,
                "resolution": resolution,
                "personGeneration": "dont_allow",  // Safety setting
                "generateAudio": true
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VeoError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VeoError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Parse response to get operation name
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let operationName = json["name"] as? String else {
            throw VeoError.invalidResponse
        }
        
        return operationName
    }
    
    /// Poll operation status
    /// - Parameters:
    ///   - apiKey: Gemini API key
    ///   - operationName: Operation name from startGeneration
    /// - Returns: Operation status with video URI if complete
    func pollOperation(apiKey: String, operationName: String) async throws -> VeoOperationStatus {
        // The operation name already includes the full path
        let url = URL(string: "\(baseURL)/\(operationName)?key=\(apiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VeoError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw VeoError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VeoError.invalidResponse
        }
        
        let done = json["done"] as? Bool ?? false
        
        if done {
            // Check for error
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return VeoOperationStatus(done: true, progress: nil, videoUri: nil, error: message)
            }
            
            // Extract video URI from response
            if let response = json["response"] as? [String: Any],
               let generatedVideos = response["generatedVideos"] as? [[String: Any]],
               let firstVideo = generatedVideos.first,
               let videoUri = firstVideo["video"] as? [String: Any],
               let uri = videoUri["uri"] as? String {
                return VeoOperationStatus(done: true, progress: 100, videoUri: uri, error: nil)
            }
            
            throw VeoError.noVideoGenerated
        }
        
        // Still processing - Gemini doesn't provide progress percentage
        // We'll estimate based on typical generation times
        return VeoOperationStatus(done: false, progress: nil, videoUri: nil, error: nil)
    }
    
    /// Download completed video
    /// - Parameters:
    ///   - apiKey: Gemini API key
    ///   - videoUri: Video URI from pollOperation
    /// - Returns: Video data
    func downloadVideo(apiKey: String, videoUri: String) async throws -> Data {
        // The video URI may need the API key appended
        var downloadUrl = videoUri
        if !downloadUrl.contains("key=") {
            downloadUrl += downloadUrl.contains("?") ? "&key=\(apiKey)" : "?key=\(apiKey)"
        }
        
        guard let url = URL(string: downloadUrl) else {
            throw VeoError.invalidVideoUri
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw VeoError.downloadFailed
        }
        
        return data
    }
    
    /// Generate video with full polling loop (convenience method)
    /// - Parameters:
    ///   - apiKey: Gemini API key
    ///   - prompt: Text prompt
    ///   - model: Veo model
    ///   - aspectRatio: Aspect ratio
    ///   - durationSeconds: Duration
    ///   - resolution: Resolution
    ///   - onProgress: Progress callback
    /// - Returns: Video data
    func generateVideo(
        apiKey: String,
        prompt: String,
        model: String = "veo-3.1-generate-preview",
        aspectRatio: String = "16:9",
        durationSeconds: Int = 8,
        resolution: String = "720p",
        onProgress: ((VeoOperationStatus) async -> Void)? = nil
    ) async throws -> Data {
        // Start generation
        let operationName = try await startGeneration(
            apiKey: apiKey,
            prompt: prompt,
            model: model,
            aspectRatio: aspectRatio,
            durationSeconds: durationSeconds,
            resolution: resolution
        )
        
        // Poll until complete
        var status: VeoOperationStatus
        repeat {
            try await Task.sleep(nanoseconds: pollingIntervalSeconds * 1_000_000_000)
            status = try await pollOperation(apiKey: apiKey, operationName: operationName)
            await onProgress?(status)
        } while !status.done
        
        // Check for error
        if let error = status.error {
            throw VeoError.generationFailed(error)
        }
        
        // Download video
        guard let videoUri = status.videoUri else {
            throw VeoError.noVideoGenerated
        }
        
        return try await downloadVideo(apiKey: apiKey, videoUri: videoUri)
    }
}

// MARK: - Models

/// Veo operation status
struct VeoOperationStatus {
    let done: Bool
    let progress: Int?  // Gemini doesn't provide this, but we estimate
    let videoUri: String?
    let error: String?
}

// MARK: - Errors

enum VeoError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case noVideoGenerated
    case invalidVideoUri
    case downloadFailed
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Gemini Veo API"
        case .apiError(let statusCode, let message):
            return "Veo API error (\(statusCode)): \(message)"
        case .noVideoGenerated:
            return "No video was generated"
        case .invalidVideoUri:
            return "Invalid video URI returned"
        case .downloadFailed:
            return "Failed to download video"
        case .generationFailed(let message):
            return "Video generation failed: \(message)"
        }
    }
}
