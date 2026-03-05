//
//  MLXTTSService.swift
//  Axon
//
//  On-device neural TTS service using F5-TTS.
//  Provides high-quality speech synthesis without API costs.
//  Models are auto-downloaded on first use (~300MB).
//

import Foundation
import Combine

// F5-TTS package temporarily disabled due to swift-transformers version conflict
// between f5-tts-swift (requires 0.x) and mlx-swift-lm (requires 1.x)
// Uncomment when dependency conflict is resolved:
// #if canImport(F5TTS)
// import F5TTS
// import MLX
// #endif

// MARK: - MLX TTS Voice Options

/// Available voices for F5-TTS
/// F5-TTS uses voice cloning - these represent bundled reference voices
enum MLXTTSVoice: String, Codable, CaseIterable, Identifiable {
    case defaultVoice = "default"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultVoice: return "Default"
        }
    }

    var description: String {
        switch self {
        case .defaultVoice: return "Natural voice (Mother Nature)"
        }
    }

    var gender: VoiceGender {
        switch self {
        case .defaultVoice: return .female
        }
    }
}

// MARK: - MLX TTS Service

@MainActor
final class MLXTTSService: ObservableObject {
    static let shared = MLXTTSService()

    // F5-TTS package temporarily disabled
    // Uncomment when dependency conflict is resolved:
    // #if canImport(F5TTS)
    // private var f5tts: F5TTS?
    // #endif

    @Published var isModelLoaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var loadingStatus: String = ""

    private init() {}

    // MARK: - Errors

    enum MLXTTSError: LocalizedError {
        case notAvailable
        case modelLoadFailed(String)
        case generationFailed(String)
        case simulatorNotSupported
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "F5-TTS is not available on this device. Requires Apple Silicon."
            case .modelLoadFailed(let reason):
                return "Failed to load F5-TTS model: \(reason)"
            case .generationFailed(let reason):
                return "F5-TTS speech generation failed: \(reason)"
            case .simulatorNotSupported:
                return "F5-TTS requires a physical device with Metal GPU support."
            case .modelNotLoaded:
                return "F5-TTS model is not loaded. Please wait for download to complete."
            }
        }
    }

    // MARK: - Availability Check

    /// Check if F5-TTS is available on this device
    /// NOTE: Currently disabled due to mlx-swift version incompatibility.
    /// F5-TTS requires mlx-swift 0.18.1 but other MLX packages need newer versions.
    /// See: https://github.com/lucasnewman/f5-tts-swift/issues/6
    static var isAvailable: Bool {
        // Temporarily disabled until F5-TTS is updated for newer mlx-swift versions
        return false

        // Original implementation (re-enable when F5-TTS is updated):
        // #if canImport(F5TTS)
        // #if targetEnvironment(simulator)
        // return false
        // #else
        // return true
        // #endif
        // #else
        // return false
        // #endif
    }

    // MARK: - Model Management

    /// Load the F5-TTS model
    func loadModel() async throws {
        // F5-TTS package temporarily disabled
        throw MLXTTSError.notAvailable
    }

    /// Unload the model to free memory
    func unloadModel() {
        // F5-TTS package temporarily disabled
        isModelLoaded = false
        loadingStatus = ""
        downloadProgress = 0.0
        print("[MLXTTSService] Model unloaded (F5-TTS disabled)")
    }

    // MARK: - Speech Generation

    /// Generate speech audio from text
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice preset to use (currently only default supported)
    ///   - speed: Speech speed (0.5 to 2.0, default 1.0)
    /// - Returns: Audio data in WAV format
    func generateSpeech(
        text: String,
        voice: MLXTTSVoice = .defaultVoice,
        speed: Float = 1.0
    ) async throws -> Data {
        // F5-TTS package temporarily disabled
        throw MLXTTSError.notAvailable
    }

    // MARK: - Audio Conversion

    /// Convert Float PCM samples to WAV format
    private func createWAVData(from samples: [Float], sampleRate: Int, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        var wavData = Data()

        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        // Convert Float samples to Int16
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * Float(Int16.max))
        }

        let dataSize = int16Samples.count * 2 // 2 bytes per Int16
        let chunkSize = 36 + dataSize

        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(chunkSize).littleEndian) { Array($0) })
        wavData.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Subchunk1Size for PCM
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // AudioFormat (1 = PCM)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        wavData.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data subchunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Append audio samples
        for sample in int16Samples {
            wavData.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        return wavData
    }
}
