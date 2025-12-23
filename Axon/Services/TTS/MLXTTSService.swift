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

#if canImport(F5TTS)
import F5TTS
import MLX
#endif

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

    #if canImport(F5TTS)
    private var f5tts: F5TTS?
    #endif

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
        #if canImport(F5TTS)
        #if targetEnvironment(simulator)
        throw MLXTTSError.simulatorNotSupported
        #endif

        guard !isModelLoaded else {
            print("[MLXTTSService] Model already loaded")
            return
        }

        isDownloading = true
        loadingStatus = "Downloading F5-TTS model..."

        defer {
            isDownloading = false
        }

        do {
            print("[MLXTTSService] Loading F5-TTS from pretrained model...")

            f5tts = try await F5TTS.fromPretrained(repoId: "lucasnewman/f5-tts-mlx") { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress.fractionCompleted
                    self?.loadingStatus = "Downloading: \(Int(progress.fractionCompleted * 100))%"
                }
            }

            isModelLoaded = true
            loadingStatus = "Model loaded"
            print("[MLXTTSService] F5-TTS model loaded successfully")

        } catch {
            loadingStatus = "Failed to load model"
            print("[MLXTTSService] Failed to load F5-TTS: \(error)")
            throw MLXTTSError.modelLoadFailed(error.localizedDescription)
        }
        #else
        throw MLXTTSError.notAvailable
        #endif
    }

    /// Unload the model to free memory
    func unloadModel() {
        #if canImport(F5TTS)
        f5tts = nil
        isModelLoaded = false
        loadingStatus = ""
        downloadProgress = 0.0
        print("[MLXTTSService] Model unloaded")
        #endif
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
        #if canImport(F5TTS)
        #if targetEnvironment(simulator)
        throw MLXTTSError.simulatorNotSupported
        #endif

        // Load model if not already loaded
        if !isModelLoaded || f5tts == nil {
            try await loadModel()
        }

        guard let f5tts = f5tts else {
            throw MLXTTSError.modelNotLoaded
        }

        print("[MLXTTSService] Generating speech for text: \(text.prefix(50))...")

        do {
            // Generate audio using F5-TTS
            // Uses built-in reference audio for voice cloning
            let audioArray = try await f5tts.generate(
                text: text,
                speed: Double(speed)
            ) { progress in
                print("[MLXTTSService] Generation progress: \(Int(progress * 100))%")
            }

            // Convert MLXArray to Float array
            let floatArray = audioArray.asArray(Float.self)

            print("[MLXTTSService] Generated \(floatArray.count) samples @ \(F5TTS.sampleRate) Hz")

            // Convert to WAV data
            let wavData = createWAVData(
                from: floatArray,
                sampleRate: F5TTS.sampleRate
            )

            print("[MLXTTSService] Created WAV data: \(wavData.count) bytes")
            return wavData

        } catch {
            print("[MLXTTSService] Generation failed: \(error)")
            throw MLXTTSError.generationFailed(error.localizedDescription)
        }
        #else
        throw MLXTTSError.notAvailable
        #endif
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
