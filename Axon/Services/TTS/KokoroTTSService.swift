//
//  KokoroTTSService.swift
//  Axon
//
//  On-device neural TTS service using Kokoro.
//  Provides high-quality speech synthesis without API costs.
//  Model files must be downloaded separately (~600MB).
//

import Foundation
import Combine

#if canImport(KokoroSwift)
import KokoroSwift
import MLX
#endif

// MARK: - Kokoro TTS Voice Options

/// Available voices for Kokoro TTS
/// Voices are loaded from .npz files containing embeddings
enum KokoroTTSVoice: String, Codable, CaseIterable, Identifiable {
    // American Female (11)
    case af_heart = "af_heart"
    case af_alloy = "af_alloy"
    case af_aoede = "af_aoede"
    case af_bella = "af_bella"
    case af_jessica = "af_jessica"
    case af_kore = "af_kore"
    case af_nicole = "af_nicole"
    case af_nova = "af_nova"
    case af_river = "af_river"
    case af_sarah = "af_sarah"
    case af_sky = "af_sky"

    // American Male (9)
    case am_echo = "am_echo"
    case am_adam = "am_adam"
    case am_eric = "am_eric"
    case am_fenrir = "am_fenrir"
    case am_liam = "am_liam"
    case am_michael = "am_michael"
    case am_onyx = "am_onyx"
    case am_puck = "am_puck"
    case am_santa = "am_santa"

    // British Female (4)
    case bf_alice = "bf_alice"
    case bf_emma = "bf_emma"
    case bf_isabella = "bf_isabella"
    case bf_lily = "bf_lily"

    // British Male (4)
    case bm_daniel = "bm_daniel"
    case bm_fable = "bm_fable"
    case bm_george = "bm_george"
    case bm_lewis = "bm_lewis"

    var id: String { rawValue }

    var displayName: String {
        // Convert rawValue like "af_heart" to "Heart"
        let parts = rawValue.split(separator: "_")
        guard parts.count >= 2 else { return rawValue }
        return parts.dropFirst().map { $0.capitalized }.joined(separator: " ")
    }

    var description: String {
        switch self {
        case .af_heart: return "Warm, expressive female voice"
        case .af_alloy: return "Balanced, versatile female voice"
        case .af_aoede: return "Melodic, artistic female voice"
        case .af_bella: return "Clear, friendly female voice"
        case .af_jessica: return "Professional, articulate female voice"
        case .af_kore: return "Youthful, energetic female voice"
        case .af_nicole: return "Smooth, sophisticated female voice"
        case .af_nova: return "Bright, modern female voice"
        case .af_river: return "Calm, flowing female voice"
        case .af_sarah: return "Natural, conversational female voice"
        case .af_sky: return "Light, airy female voice"
        case .am_echo: return "Resonant, clear male voice"
        case .am_adam: return "Deep, authoritative male voice"
        case .am_eric: return "Friendly, approachable male voice"
        case .am_fenrir: return "Strong, powerful male voice"
        case .am_liam: return "Warm, relatable male voice"
        case .am_michael: return "Professional, steady male voice"
        case .am_onyx: return "Rich, deep male voice"
        case .am_puck: return "Playful, mischievous male voice"
        case .am_santa: return "Jolly, festive male voice"
        case .bf_alice: return "Elegant British female voice"
        case .bf_emma: return "Refined British female voice"
        case .bf_isabella: return "Sophisticated British female voice"
        case .bf_lily: return "Gentle British female voice"
        case .bm_daniel: return "Distinguished British male voice"
        case .bm_fable: return "Storytelling British male voice"
        case .bm_george: return "Classic British male voice"
        case .bm_lewis: return "Thoughtful British male voice"
        }
    }

    var gender: VoiceGender {
        // Voices starting with 'af_' or 'bf_' are female
        rawValue.hasPrefix("af_") || rawValue.hasPrefix("bf_") ? .female : .male
    }

    var accent: KokoroVoiceAccent {
        rawValue.hasPrefix("bf_") || rawValue.hasPrefix("bm_") ? .british : .american
    }

    /// Whether this voice is built-in (bundled with app) or requires download
    var isBuiltIn: Bool {
        self == .af_heart || self == .am_echo
    }

    /// URL to download this voice embedding from HuggingFace
    var downloadURL: URL? {
        guard !isBuiltIn else { return nil }
        return URL(string: "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/voices/\(rawValue).npz")
    }

    /// Filter voices by gender
    static func voices(for gender: VoiceGender?) -> [KokoroTTSVoice] {
        guard let gender = gender else { return allCases }
        return allCases.filter { $0.gender == gender }
    }

    /// Filter voices by accent
    static func voices(for accent: KokoroVoiceAccent) -> [KokoroTTSVoice] {
        allCases.filter { $0.accent == accent }
    }

    /// Get all built-in voices
    static var builtInVoices: [KokoroTTSVoice] {
        allCases.filter { $0.isBuiltIn }
    }

    /// Get all downloadable voices
    static var downloadableVoices: [KokoroTTSVoice] {
        allCases.filter { !$0.isBuiltIn }
    }
}

/// Voice accent classification for Kokoro
enum KokoroVoiceAccent: String, Codable, CaseIterable {
    case american
    case british

    var displayName: String {
        switch self {
        case .american: return "American"
        case .british: return "British"
        }
    }
}

// MARK: - Kokoro TTS Service

@MainActor
final class KokoroTTSService: ObservableObject {
    static let shared = KokoroTTSService()

    #if canImport(KokoroSwift)
    private var kokoroTTS: KokoroTTS?
    private var voiceEmbeddings: [String: MLXArray] = [:]
    #endif

    @Published var isModelLoaded = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var loadingStatus: String = ""
    @Published var voiceDownloadProgress: [String: Double] = [:]

    private init() {}

    // MARK: - Errors

    enum KokoroTTSError: LocalizedError {
        case notAvailable
        case modelNotFound
        case voiceNotFound(String)
        case generationFailed(String)
        case downloadFailed(String)
        case simulatorNotSupported
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Kokoro TTS is not available. Requires Apple Silicon."
            case .modelNotFound:
                return "Kokoro model file not found. Please download the model."
            case .voiceNotFound(let voice):
                return "Voice '\(voice)' not found. Please download it first."
            case .generationFailed(let reason):
                return "Speech generation failed: \(reason)"
            case .downloadFailed(let reason):
                return "Download failed: \(reason)"
            case .simulatorNotSupported:
                return "Kokoro TTS requires a physical device with Metal GPU support."
            case .modelNotLoaded:
                return "Kokoro model is not loaded. Please wait for loading to complete."
            }
        }
    }

    // MARK: - Availability Check

    /// Check if Kokoro TTS is available on this device
    static var isAvailable: Bool {
        #if canImport(KokoroSwift)
        #if targetEnvironment(simulator)
        debugLog(.ttsPlayback, "🗣️ [Kokoro] isAvailable: false (simulator)")
        return false
        #else
        debugLog(.ttsPlayback, "🗣️ [Kokoro] isAvailable: true (KokoroSwift imported)")
        return true
        #endif
        #else
        debugLog(.ttsPlayback, "🗣️ [Kokoro] isAvailable: false (KokoroSwift not available)")
        return false
        #endif
    }

    // MARK: - Path Management

    /// Get the path to the Kokoro model file
    /// Checks App Bundle first (in KokoroTTS/Model subdirectory), then Documents/KokoroModels/
    func getModelPath() -> URL? {
        // Check App Bundle first - in KokoroTTS/Model subdirectory
        if let bundlePath = Bundle.main.url(
            forResource: "kokoro-v1_0",
            withExtension: "safetensors",
            subdirectory: "KokoroTTS/Model"
        ) {
            return bundlePath
        }

        // Also check without subdirectory (for flexibility)
        if let bundlePath = Bundle.main.url(forResource: "kokoro-v1_0", withExtension: "safetensors") {
            return bundlePath
        }

        // Check Documents/KokoroModels/
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = documentsPath.appendingPathComponent("KokoroModels/kokoro-v1_0.safetensors")

        if FileManager.default.fileExists(atPath: modelPath.path) {
            return modelPath
        }

        return nil
    }

    /// Get the directory for downloaded voice files
    var voicesDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("KokoroModels/voices")
    }

    /// Get path to built-in voices file (bundled with app)
    func getBuiltInVoicesPath() -> URL? {
        // Check in KokoroTTS/Voices subdirectory first
        if let path = Bundle.main.url(
            forResource: "voices_builtin",
            withExtension: "npz",
            subdirectory: "KokoroTTS/Voices"
        ) {
            return path
        }

        // Also check without subdirectory (for flexibility)
        return Bundle.main.url(forResource: "voices_builtin", withExtension: "npz")
    }

    /// Check if the model is available (either in bundle or documents)
    var isModelAvailable: Bool {
        getModelPath() != nil
    }

    // MARK: - Model Management

    /// Load the Kokoro TTS model
    func loadModel() async throws {
        debugLog(.ttsPlayback, "🗣️ [Kokoro] loadModel() called")

        #if canImport(KokoroSwift)
        debugLog(.ttsPlayback, "🗣️ [Kokoro] KokoroSwift is available, checking device...")

        guard Self.isAvailable else {
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Device not supported (simulator)")
            throw KokoroTTSError.simulatorNotSupported
        }

        debugLog(.ttsPlayback, "🗣️ [Kokoro] Looking for model path...")
        guard let modelPath = getModelPath() else {
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Model path not found!")
            throw KokoroTTSError.modelNotFound
        }
        debugLog(.ttsPlayback, "🗣️ [Kokoro] Found model at: \(modelPath.path)")

        loadingStatus = "Loading Kokoro model..."
        isDownloading = true

        do {
            // Initialize Kokoro TTS with model path
            // KokoroTTS expects the file URL directly (not directory)
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Initializing KokoroTTS with model file: \(modelPath.path)")

            kokoroTTS = KokoroTTS(modelPath: modelPath, g2p: .misaki)
            debugLog(.ttsPlayback, "🗣️ [Kokoro] KokoroTTS initialized successfully")

            // Load built-in voice embeddings
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Loading built-in voices...")
            try await loadBuiltInVoices()
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Built-in voices loaded")

            // Load any downloaded voices
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Loading downloaded voices...")
            try await loadDownloadedVoices()
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Downloaded voices loaded")

            // Log available voices for verification
            let availableVoiceNames = Array(voiceEmbeddings.keys).sorted()
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Available voice embeddings: \(availableVoiceNames)")

            isModelLoaded = true
            loadingStatus = "Model loaded"
            debugLog(.ttsPlayback, "🗣️ [Kokoro] ✅ Model loaded successfully!")
        } catch {
            loadingStatus = "Failed to load model"
            debugLog(.ttsPlayback, "🗣️ [Kokoro] ❌ Failed to load model: \(error)")
            throw KokoroTTSError.generationFailed(error.localizedDescription)
        }

        isDownloading = false
        #else
        debugLog(.ttsPlayback, "🗣️ [Kokoro] KokoroSwift not available in this build")
        throw KokoroTTSError.notAvailable
        #endif
    }

    /// Unload the model to free memory
    func unloadModel() {
        #if canImport(KokoroSwift)
        kokoroTTS = nil
        voiceEmbeddings.removeAll()
        #endif
        isModelLoaded = false
        loadingStatus = ""
        downloadProgress = 0.0
        debugLog(.ttsPlayback, "[KokoroTTSService] Model unloaded")
    }

    // MARK: - Voice Management

    /// Load built-in voice embeddings from bundled npz file
    private func loadBuiltInVoices() async throws {
        #if canImport(KokoroSwift)
        debugLog(.ttsPlayback, "🗣️ [Kokoro] Looking for built-in voices file...")
        guard let voicesPath = getBuiltInVoicesPath() else {
            debugLog(.ttsPlayback, "🗣️ [Kokoro] ⚠️ Built-in voices file not found")
            return
        }
        debugLog(.ttsPlayback, "🗣️ [Kokoro] Found voices file at: \(voicesPath.path)")

        debugLog(.ttsPlayback, "🗣️ [Kokoro] Reading NPZ file...")
        if let arrays = NpyzReader.read(fileFromPath: voicesPath) {
            debugLog(.ttsPlayback, "🗣️ [Kokoro] NPZ file contains \(arrays.count) voice(s)")
            for (name, array) in arrays {
                // Strip .npy extension if present (NPZ files store with .npy suffix)
                let voiceName = name.replacingOccurrences(of: ".npy", with: "")
                voiceEmbeddings[voiceName] = array
                debugLog(.ttsPlayback, "🗣️ [Kokoro] Loaded built-in voice: \(voiceName)")
            }
        } else {
            debugLog(.ttsPlayback, "🗣️ [Kokoro] ⚠️ Failed to read NPZ file")
        }
        #endif
    }

    /// Load downloaded voice embeddings from Documents directory
    private func loadDownloadedVoices() async throws {
        #if canImport(KokoroSwift)
        debugLog(.ttsPlayback, "🗣️ [Kokoro] Checking for downloaded voices...")
        let fileManager = FileManager.default

        // Create voices directory if it doesn't exist
        if !fileManager.fileExists(atPath: voicesDirectory.path) {
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Creating voices directory: \(voicesDirectory.path)")
            try fileManager.createDirectory(at: voicesDirectory, withIntermediateDirectories: true)
        }

        // Load each .npz file in the voices directory
        let contents = try fileManager.contentsOfDirectory(at: voicesDirectory, includingPropertiesForKeys: nil)
        let npzFiles = contents.filter { $0.pathExtension == "npz" }
        debugLog(.ttsPlayback, "🗣️ [Kokoro] Found \(npzFiles.count) downloaded voice file(s)")

        for fileURL in npzFiles {
            debugLog(.ttsPlayback, "🗣️ [Kokoro] Loading: \(fileURL.lastPathComponent)")
            if let arrays = NpyzReader.read(fileFromPath: fileURL) {
                debugLog(.ttsPlayback, "🗣️ [Kokoro] NPZ file contains \(arrays.count) array(s)")
                for (name, array) in arrays {
                    // Strip .npy extension if present (NPZ files store with .npy suffix)
                    let voiceName = name.replacingOccurrences(of: ".npy", with: "")
                    voiceEmbeddings[voiceName] = array
                    debugLog(.ttsPlayback, "🗣️ [Kokoro] Loaded downloaded voice: \(voiceName)")
                }
            } else {
                debugLog(.ttsPlayback, "🗣️ [Kokoro] ⚠️ Failed to read NPZ file: \(fileURL.lastPathComponent)")
            }
        }
        #endif
    }

    /// Check if a specific voice is available (loaded or built-in with bundled files)
    func isVoiceAvailable(_ voice: KokoroTTSVoice) -> Bool {
        #if canImport(KokoroSwift)
        // If model is loaded, check actual embeddings
        if isModelLoaded {
            return voiceEmbeddings[voice.rawValue] != nil
        }
        // If model isn't loaded yet, built-in voices are considered available if model files exist
        if voice.isBuiltIn && isModelAvailable && getBuiltInVoicesPath() != nil {
            return true
        }
        // Downloaded voices - check if their file exists
        if !voice.isBuiltIn {
            let voiceFile = voicesDirectory.appendingPathComponent("\(voice.rawValue).npz")
            return FileManager.default.fileExists(atPath: voiceFile.path)
        }
        return false
        #else
        return false
        #endif
    }

    /// Get list of currently available voices
    func getAvailableVoices() -> [KokoroTTSVoice] {
        #if canImport(KokoroSwift)
        // If model is loaded, return voices with loaded embeddings
        if isModelLoaded {
            return KokoroTTSVoice.allCases.filter { voiceEmbeddings[$0.rawValue] != nil }
        }
        // If model isn't loaded yet, return built-in voices if model files are bundled
        if isModelAvailable && getBuiltInVoicesPath() != nil {
            var voices = KokoroTTSVoice.builtInVoices
            // Also include any downloaded voices
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: voicesDirectory.path),
               let contents = try? fileManager.contentsOfDirectory(at: voicesDirectory, includingPropertiesForKeys: nil) {
                for fileURL in contents where fileURL.pathExtension == "npz" {
                    let voiceName = fileURL.deletingPathExtension().lastPathComponent
                    if let voice = KokoroTTSVoice(rawValue: voiceName), !voice.isBuiltIn {
                        voices.append(voice)
                    }
                }
            }
            return voices
        }
        return []
        #else
        return []
        #endif
    }

    /// Download a voice embedding file
    func downloadVoice(_ voice: KokoroTTSVoice) async throws {
        guard !voice.isBuiltIn else { return }
        guard let downloadURL = voice.downloadURL else {
            throw KokoroTTSError.downloadFailed("No download URL for voice")
        }

        voiceDownloadProgress[voice.rawValue] = 0.0

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)

            // Create voices directory if needed
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: voicesDirectory.path) {
                try fileManager.createDirectory(at: voicesDirectory, withIntermediateDirectories: true)
            }

            // Move to voices directory
            let destinationURL = voicesDirectory.appendingPathComponent("\(voice.rawValue).npz")
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempURL, to: destinationURL)

            // Load the voice embedding
            #if canImport(KokoroSwift)
            if let arrays = NpyzReader.read(fileFromPath: destinationURL) {
                for (name, array) in arrays {
                    // Strip .npy extension if present (NPZ files store with .npy suffix)
                    let voiceName = name.replacingOccurrences(of: ".npy", with: "")
                    voiceEmbeddings[voiceName] = array
                }
            }
            #endif

            voiceDownloadProgress[voice.rawValue] = 1.0
            debugLog(.ttsPlayback, "[KokoroTTSService] Downloaded voice: \(voice.rawValue)")
        } catch {
            voiceDownloadProgress.removeValue(forKey: voice.rawValue)
            throw KokoroTTSError.downloadFailed(error.localizedDescription)
        }
    }

    /// Delete a downloaded voice
    func deleteVoice(_ voice: KokoroTTSVoice) throws {
        guard !voice.isBuiltIn else { return }

        let fileURL = voicesDirectory.appendingPathComponent("\(voice.rawValue).npz")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        #if canImport(KokoroSwift)
        voiceEmbeddings.removeValue(forKey: voice.rawValue)
        #endif

        debugLog(.ttsPlayback, "[KokoroTTSService] Deleted voice: \(voice.rawValue)")
    }

    // MARK: - Speech Generation

    /// Maximum characters per chunk for text splitting
    /// Kokoro has a 510 token limit; ~4 chars per token on average, with margin for phoneme expansion
    private static let maxCharsPerChunk = 400

    /// Generate speech audio from text
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - speed: Speech speed (0.5 to 2.0, default 1.0)
    /// - Returns: Audio data in WAV format
    func generateSpeech(
        text: String,
        voice: KokoroTTSVoice = .af_heart,
        speed: Float = 1.0
    ) async throws -> Data {
        #if canImport(KokoroSwift)
        guard isModelLoaded, let tts = kokoroTTS else {
            throw KokoroTTSError.modelNotLoaded
        }

        guard let voiceEmbedding = voiceEmbeddings[voice.rawValue] else {
            throw KokoroTTSError.voiceNotFound(voice.rawValue)
        }

        // Determine language based on voice accent
        let language: Language = voice.accent == .british ? .enGB : .enUS

        debugLog(.ttsPlayback, "🗣️ [Kokoro] Generating speech for \(text.count) chars with voice \(voice.rawValue)...")

        // Split long text into chunks to avoid token limit (510 tokens max)
        let chunks = splitTextIntoChunks(text, maxChars: Self.maxCharsPerChunk)
        debugLog(.ttsPlayback, "🗣️ [Kokoro] Split into \(chunks.count) chunk(s)")

        var allAudioSamples: [Float] = []

        for (index, chunk) in chunks.enumerated() {
            do {
                debugLog(.ttsPlayback, "🗣️ [Kokoro] Processing chunk \(index + 1)/\(chunks.count) (\(chunk.count) chars)...")

                // Generate audio samples for this chunk
                let (audioSamples, _) = try tts.generateAudio(
                    voice: voiceEmbedding,
                    language: language,
                    text: chunk,
                    speed: speed
                )

                debugLog(.ttsPlayback, "🗣️ [Kokoro] Chunk \(index + 1) generated \(audioSamples.count) samples")
                allAudioSamples.append(contentsOf: audioSamples)

                // Add a small pause between chunks (0.15 seconds at 24kHz)
                if index < chunks.count - 1 {
                    let pauseSamples = Int(0.15 * Float(KokoroTTS.Constants.samplingRate))
                    allAudioSamples.append(contentsOf: [Float](repeating: 0, count: pauseSamples))
                }
            } catch {
                debugLog(.ttsPlayback, "🗣️ [Kokoro] ❌ Chunk \(index + 1) failed: \(error)")
                debugLog(.ttsPlayback, "🗣️ [Kokoro] ❌ Error type: \(type(of: error))")
                debugLog(.ttsPlayback, "🗣️ [Kokoro] ❌ Error description: \(String(describing: error))")
                throw KokoroTTSError.generationFailed(error.localizedDescription)
            }
        }

        debugLog(.ttsPlayback, "🗣️ [Kokoro] Total audio samples: \(allAudioSamples.count)")

        // Convert to WAV format
        let wavData = createWAVData(
            from: allAudioSamples,
            sampleRate: KokoroTTS.Constants.samplingRate,
            channels: 1,
            bitsPerSample: 16
        )

        debugLog(.ttsPlayback, "[KokoroTTSService] Generated \(wavData.count) bytes of audio for \(text.count) chars")
        return wavData
        #else
        throw KokoroTTSError.notAvailable
        #endif
    }

    /// Split text into chunks at sentence boundaries
    /// - Parameters:
    ///   - text: The text to split
    ///   - maxChars: Maximum characters per chunk
    /// - Returns: Array of text chunks
    private func splitTextIntoChunks(_ text: String, maxChars: Int) -> [String] {
        // If text is short enough, return as single chunk
        guard text.count > maxChars else {
            return [text]
        }

        var chunks: [String] = []
        var currentChunk = ""

        // Split by sentences (period, exclamation, question mark followed by space or end)
        let sentencePattern = #"[^.!?]*[.!?]+\s*"#
        let regex = try? NSRegularExpression(pattern: sentencePattern, options: [])
        let range = NSRange(text.startIndex..., in: text)

        var lastEnd = text.startIndex
        regex?.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match, let matchRange = Range(match.range, in: text) else { return }

            let sentence = String(text[matchRange])

            // Check if adding this sentence would exceed the limit
            if currentChunk.count + sentence.count > maxChars {
                // Save current chunk if not empty
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                    currentChunk = ""
                }

                // If a single sentence is too long, split it further
                if sentence.count > maxChars {
                    let subChunks = splitLongSentence(sentence, maxChars: maxChars)
                    chunks.append(contentsOf: subChunks.dropLast())
                    currentChunk = subChunks.last ?? ""
                } else {
                    currentChunk = sentence
                }
            } else {
                currentChunk += sentence
            }

            lastEnd = matchRange.upperBound
        }

        // Handle remaining text (if any text after the last sentence match)
        if lastEnd < text.endIndex {
            let remaining = String(text[lastEnd...])
            if currentChunk.count + remaining.count > maxChars {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                }
                if remaining.count > maxChars {
                    chunks.append(contentsOf: splitLongSentence(remaining, maxChars: maxChars))
                } else {
                    chunks.append(remaining.trimmingCharacters(in: .whitespaces))
                }
            } else {
                currentChunk += remaining
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                }
            }
        } else if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
        }

        // Filter out empty chunks
        return chunks.filter { !$0.isEmpty }
    }

    /// Split a long sentence at word boundaries
    private func splitLongSentence(_ sentence: String, maxChars: Int) -> [String] {
        var chunks: [String] = []
        var currentChunk = ""

        let words = sentence.split(separator: " ", omittingEmptySubsequences: true)
        for word in words {
            let wordStr = String(word)
            if currentChunk.count + wordStr.count + 1 > maxChars {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                    currentChunk = ""
                }
            }
            if currentChunk.isEmpty {
                currentChunk = wordStr
            } else {
                currentChunk += " " + wordStr
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
        }

        return chunks
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
