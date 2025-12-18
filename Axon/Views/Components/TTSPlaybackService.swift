//
//  TTSPlaybackService.swift
//  Axon
//

import Foundation
import AVFoundation
import Combine

/// Audio format enum to track provider-specific formats
enum TTSAudioFormat: String {
    case mp3 = "mp3"
    case wav = "wav"
    case m4a = "m4a"

    var fileTypeHint: String {
        switch self {
        case .mp3: return AVFileType.mp3.rawValue
        case .wav: return AVFileType.wav.rawValue
        case .m4a: return AVFileType.m4a.rawValue
        }
    }
}

@MainActor
final class TTSPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = TTSPlaybackService()

    private var player: AVAudioPlayer?

    @Published var isPlaying = false
    @Published var isGenerating = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentMessageId: String?
    @Published var hasCachedAudio = false // Track if any audio is cached

    // Cache for generated audio by message ID
    private var audioCache: [String: Data] = [:] {
        didSet {
            hasCachedAudio = !audioCache.isEmpty
        }
    }
    // Track audio format for each cached message
    private var audioFormatCache: [String: TTSAudioFormat] = [:]
    private var generationToken: UUID?

    // Timer for updating playback position
    private var playbackTimer: Timer?

    override private init() {
        super.init()
        // Configure audio session on initialization
        configureAudioSession()
        // Start playback monitoring timer
        startPlaybackTimer()
    }

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("[TTSPlaybackService] Audio session configured successfully")
        } catch {
            print("[TTSPlaybackService] Failed to configure audio session: \(error)")
        }
        #else
        // AVAudioSession is iOS/tvOS-only. On macOS we can play audio without a session.
        print("[TTSPlaybackService] Audio session not applicable on this platform")
        #endif
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player, self.isPlaying else { return }
            Task { @MainActor in
                self.currentTime = player.currentTime
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        isGenerating = false
        currentMessageId = nil
        currentTime = 0
        duration = 0
        generationToken = nil
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        player?.play()
        isPlaying = true
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func hasGeneratedAudio(for messageId: String, settings: AppSettings? = nil) -> Bool {
        let key = cacheKey(for: messageId, settings: settings)
        if audioCache[key] != nil { return true }
        // Check all formats on disk (mp3, wav, m4a)
        return FileManager.default.fileExists(atPath: audioFileURL(for: key, format: .mp3).path) ||
               FileManager.default.fileExists(atPath: audioFileURL(for: key, format: .wav).path) ||
               FileManager.default.fileExists(atPath: audioFileURL(for: key, format: .m4a).path)
    }

    /// Check if audio is available (locally or remotely via CloudKit).
    /// This is an async version that checks the sync service.
    func hasAudioAvailable(for messageId: String, settings: AppSettings) async -> Bool {
        let key = cacheKey(for: messageId, settings: settings)

        // Check local first
        if hasGeneratedAudio(for: messageId, settings: settings) {
            return true
        }

        // Check remote via AudioSyncService
        return await AudioSyncService.shared.hasRemoteAudio(for: key)
    }

    private func cacheKey(for messageId: String, settings: AppSettings?) -> String {
        // If no settings provided, fall back to legacy behavior (messageId-only).
        // This is mainly used for older call sites.
        guard let settings else { return messageId }

        let strip = settings.ttsSettings.stripMarkdownBeforeTTS ? "1" : "0"
        let friendly = settings.ttsSettings.spokenFriendlyTTS ? "1" : "0"

        // Keep it deterministic + file-name safe.
        return "\(messageId)_md\(strip)_sf\(friendly)"
    }

    private func cacheAudio(_ data: Data, for messageId: String, format: TTSAudioFormat, settings: AppSettings?) {
        let key = cacheKey(for: messageId, settings: settings)

        // Save to memory
        audioCache[key] = data
        audioFormatCache[key] = format

        // Save to disk with correct extension
        saveAudioToDisk(data, for: key, format: format)

        print("[TTSPlaybackService] Cached audio for message: \(messageId) -> \(key) (\(data.count) bytes, format: \(format.rawValue))")
    }

    private func getCachedAudio(for messageId: String, settings: AppSettings?) -> (data: Data, format: TTSAudioFormat)? {
        let key = cacheKey(for: messageId, settings: settings)

        // Check memory first
        if let data = audioCache[key] {
            let format = audioFormatCache[key] ?? .mp3
            return (data, format)
        }

        // Check disk - try all formats (mp3, wav, m4a)
        for format in [TTSAudioFormat.mp3, .wav, .m4a] {
            if let data = loadAudioFromDisk(for: key, format: format) {
                // Populate memory cache
                audioCache[key] = data
                audioFormatCache[key] = format
                return (data, format)
            }
        }

        return nil
    }

    /// Try to fetch audio from CloudKit if available remotely but not locally.
    /// Returns the audio data and format if found, nil otherwise.
    private func fetchRemoteAudio(for messageId: String, settings: AppSettings) async -> (data: Data, format: TTSAudioFormat)? {
        let key = cacheKey(for: messageId, settings: settings)

        do {
            if let audioData = try await AudioSyncService.shared.fetchRemoteAudio(for: key) {
                // Determine format from the metadata (check Core Data for the format)
                // For now, try to detect format from data or default to mp3
                let format: TTSAudioFormat = detectAudioFormat(from: audioData) ?? .mp3

                // Cache locally
                audioCache[key] = audioData
                audioFormatCache[key] = format
                saveAudioToDisk(audioData, for: key, format: format)

                print("[TTSPlaybackService] Fetched remote audio for: \(key)")
                return (audioData, format)
            }
        } catch {
            print("[TTSPlaybackService] Failed to fetch remote audio: \(error)")
        }

        return nil
    }

    /// Detect audio format from data by checking file signatures.
    private func detectAudioFormat(from data: Data) -> TTSAudioFormat? {
        guard data.count >= 12 else { return nil }

        let bytes = [UInt8](data.prefix(12))

        // Check for MP3 (ID3 tag or frame sync)
        if bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33 { // "ID3"
            return .mp3
        }
        if bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0 { // Frame sync
            return .mp3
        }

        // Check for WAV ("RIFF" + "WAVE")
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            return .wav
        }

        // Check for M4A/AAC ("ftyp" at offset 4)
        if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return .m4a
        }

        return nil
    }
    
    // MARK: - Persistence Helpers
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func audioFileURL(for messageId: String, format: TTSAudioFormat = .mp3) -> URL {
        let directory = getDocumentsDirectory().appendingPathComponent("AudioCache")
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(messageId).\(format.rawValue)")
    }

    private func saveAudioToDisk(_ data: Data, for messageId: String, format: TTSAudioFormat) {
        let url = audioFileURL(for: messageId, format: format)
        do {
            try data.write(to: url)
            print("[TTSPlaybackService] Saved audio to disk: \(url.path)")
        } catch {
            print("[TTSPlaybackService] Failed to save audio to disk: \(error)")
        }
    }

    private func loadAudioFromDisk(for messageId: String, format: TTSAudioFormat = .mp3) -> Data? {
        let url = audioFileURL(for: messageId, format: format)
        do {
            let data = try Data(contentsOf: url)
            print("[TTSPlaybackService] Loaded audio from disk: \(url.path)")
            return data
        } catch {
            return nil
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            print("[TTSPlaybackService] Playback finished successfully: \(flag)")
            self.isPlaying = false
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            print("[TTSPlaybackService] Decode error: \(error?.localizedDescription ?? "unknown")")
            self.isPlaying = false
        }
    }

    func speak(text: String, settings: AppSettings, messageId: String? = nil, conversationId: String? = nil) async throws {
        print("[TTSPlaybackService] Starting TTS playback")
        print("[TTSPlaybackService] Text length (raw): \(text.count) characters")
        print("[TTSPlaybackService] Provider: \(settings.ttsSettings.provider.displayName)")

        // Preprocess text for TTS (strip markdown, optionally normalize)
        let processedText = preprocessTextForTTS(text, settings: settings)
        print("[TTSPlaybackService] Text length (processed): \(processedText.count) characters")

        // Prime UI state so the player can show a loading indicator while we fetch audio
        isGenerating = true
        isPlaying = false
        currentMessageId = messageId
        currentTime = 0
        duration = 0
        let token = UUID()
        generationToken = token

        do {
            var audioData: Data
            var audioFormat: TTSAudioFormat

            // Check if we have this audio cached locally first
            if let messageId = messageId, let cached = getCachedAudio(for: messageId, settings: settings) {
                print("[TTSPlaybackService] Found locally cached audio")
                audioData = cached.data
                audioFormat = cached.format
            }
            // Check if audio is available remotely (CloudKit)
            else if let messageId = messageId,
                    settings.audioSyncSettings.syncEnabled,
                    let remote = await fetchRemoteAudio(for: messageId, settings: settings) {
                print("[TTSPlaybackService] Found remotely synced audio from CloudKit")
                audioData = remote.data
                audioFormat = remote.format
            }
            // Generate new audio
            else {
                switch settings.ttsSettings.provider {
                case .elevenlabs:
                    audioData = try await generateElevenLabsAudio(text: processedText, settings: settings)
                    audioFormat = .mp3

                case .gemini:
                    audioData = try await generateGeminiAudio(text: processedText, settings: settings)
                    audioFormat = .wav  // Gemini returns WAV format (24kHz)
                }

                print("[TTSPlaybackService] Received audio data: \(audioData.count) bytes (format: \(audioFormat.rawValue))")

                // Cache the audio if we have a message ID.
                // Cache key includes relevant preprocessing toggles so cache stays correct
                // when the user flips settings.
                if let messageId = messageId {
                    cacheAudio(audioData, for: messageId, format: audioFormat, settings: settings)

                    // Save metadata to Core Data for cross-device sync
                    if settings.audioSyncSettings.syncEnabled {
                        let key = cacheKey(for: messageId, settings: settings)
                        let voiceId: String?
                        let voiceName: String?

                        switch settings.ttsSettings.provider {
                        case .elevenlabs:
                            voiceId = settings.ttsSettings.selectedVoiceId
                            voiceName = settings.ttsSettings.selectedVoiceName
                        case .gemini:
                            voiceId = settings.ttsSettings.geminiVoice.rawValue
                            voiceName = settings.ttsSettings.geminiVoice.displayName
                        }

                        Task {
                            do {
                                try await AudioSyncService.shared.saveAudioMetadata(
                                    messageId: messageId,
                                    conversationId: conversationId ?? "",
                                    provider: settings.ttsSettings.provider.rawValue,
                                    voiceId: voiceId,
                                    voiceName: voiceName,
                                    format: audioFormat.rawValue,
                                    cacheKey: key,
                                    audioData: audioData,
                                    duration: nil // Duration is calculated during playback
                                )
                            } catch {
                                print("[TTSPlaybackService] Failed to save audio metadata: \(error)")
                            }
                        }
                    }
                }
            }

            // Switch UI from generating to playback
            isGenerating = false

            // If generation was cancelled mid-flight, skip playback
            guard generationToken == token else {
                print("[TTSPlaybackService] Generation cancelled; skipping playback")
                return
            }
            generationToken = nil

            // Play the audio with correct format hint
            try await playAudio(audioData, messageId: messageId, format: audioFormat)
        } catch {
            isGenerating = false
            if generationToken == token {
                generationToken = nil
            }
            if !isPlaying {
                currentMessageId = nil
            }
            throw error
        }
    }

    // MARK: - ElevenLabs TTS

    private func generateElevenLabsAudio(text: String, settings: AppSettings) async throws -> Data {
        guard let voiceId = settings.ttsSettings.selectedVoiceId else {
            print("[TTSPlaybackService] Error: No ElevenLabs voice selected")
            throw NSError(domain: "TTSPlaybackService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No voice selected in TTS settings. Please select a voice in Settings > Text-to-Speech."])
        }

        print("[TTSPlaybackService] Using ElevenLabs voice ID: \(voiceId)")
        print("[TTSPlaybackService] Using voice name: \(settings.ttsSettings.selectedVoiceName ?? "unknown")")
        print("[TTSPlaybackService] Using model: \(settings.ttsSettings.model.rawValue)")

        let vs = settings.ttsSettings.voiceSettings
        let payload = ElevenLabsService.VoiceSettingsPayload(
            stability: vs.stability,
            similarityBoost: vs.similarityBoost,
            style: vs.style,
            useSpeakerBoost: vs.useSpeakerBoost
        )

        print("[TTSPlaybackService] Requesting audio generation from ElevenLabs...")
        return try await ElevenLabsService.shared.generateTTSBase64(
            text: text,
            voiceId: voiceId,
            model: settings.ttsSettings.model.rawValue,
            format: settings.ttsSettings.outputFormat.rawValue,
            voiceSettings: payload
        )
    }

    // MARK: - Gemini TTS

    private func generateGeminiAudio(text: String, settings: AppSettings) async throws -> Data {
        // Get Gemini API key from settings
        guard let geminiKey = SettingsViewModel.shared.getAPIKey(.gemini), !geminiKey.isEmpty else {
            print("[TTSPlaybackService] Error: No Gemini API key configured")
            throw NSError(domain: "TTSPlaybackService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gemini API key is required for Gemini TTS. Please add your key in Settings > API Keys."])
        }

        let voice = settings.ttsSettings.geminiVoice
        print("[TTSPlaybackService] Using Gemini voice: \(voice.displayName) (\(voice.toneDescription))")

        print("[TTSPlaybackService] Requesting audio generation from Gemini...")
        return try await GeminiTTSService.shared.generateSpeech(
            text: text,
            voice: GeminiTTSService.GeminiVoice(rawValue: voice.rawValue) ?? .puck,
            apiKey: geminiKey
        )
    }

    func playGenerated(messageId: String, settings: AppSettings? = nil) async throws {
        guard let cached = getCachedAudio(for: messageId, settings: settings) else {
            print("[TTSPlaybackService] No cached audio for message: \(messageId)")
            throw NSError(domain: "TTSPlaybackService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No generated audio found for this message"])
        }

        print("[TTSPlaybackService] Playing cached audio for message: \(messageId) (format: \(cached.format.rawValue))")
        try await playAudio(cached.data, messageId: messageId, format: cached.format)
    }

    // MARK: - Text Preprocessing

    private func preprocessTextForTTS(_ text: String, settings: AppSettings) -> String {
        var out = text

        if settings.ttsSettings.stripMarkdownBeforeTTS {
            out = MarkdownToPlainText.renderedPlainText(from: out)
        }

        if settings.ttsSettings.spokenFriendlyTTS {
            out = MarkdownToPlainText.spokenFriendly(from: out)
        }

        return out
    }

    private func playAudio(_ audioData: Data, messageId: String?, format: TTSAudioFormat = .mp3) async throws {
        print("[TTSPlaybackService] Preparing to play audio data: \(audioData.count) bytes (format: \(format.rawValue))")

        // Ensure audio session is active before creating player
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
            print("[TTSPlaybackService] Audio session activated")
        } catch {
            print("[TTSPlaybackService] Failed to activate audio session: \(error)")
            throw error
        }
        #endif

        // Create and configure audio player with format hint
        // This is critical for WAV data from Gemini TTS to play correctly
        self.player = try AVAudioPlayer(data: audioData, fileTypeHint: format.fileTypeHint)
        self.player?.delegate = self
        print("[TTSPlaybackService] AVAudioPlayer created successfully with format hint: \(format.fileTypeHint)")

        // Set volume to maximum to ensure we can hear it
        self.player?.volume = 1.0
        print("[TTSPlaybackService] Volume set to: \(self.player?.volume ?? 0)")

        self.player?.prepareToPlay()
        print("[TTSPlaybackService] Audio player prepared")

        // Check if player is ready and set duration
        if let playerDuration = self.player?.duration {
            self.duration = playerDuration
            print("[TTSPlaybackService] Audio duration: \(playerDuration) seconds")
        }

        // Set the current message ID
        self.currentMessageId = messageId
        self.currentTime = 0
        print("[TTSPlaybackService] Set currentMessageId to: \(messageId ?? "nil")")
        print("[TTSPlaybackService] isPlaying before play: \(self.isPlaying)")

        let success = self.player?.play() ?? false
        print("[TTSPlaybackService] Playback started: \(success)")

        if success {
            self.isPlaying = true
            print("[TTSPlaybackService] Audio is now playing")
        } else {
            print("[TTSPlaybackService] Warning: AVAudioPlayer.play() returned false")
        }
    }
}
