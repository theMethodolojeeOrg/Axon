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

    var fileTypeHint: String {
        switch self {
        case .mp3: return AVFileType.mp3.rawValue
        case .wav: return AVFileType.wav.rawValue
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
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("[TTSPlaybackService] Audio session configured successfully")
        } catch {
            print("[TTSPlaybackService] Failed to configure audio session: \(error)")
        }
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

    func hasGeneratedAudio(for messageId: String) -> Bool {
        if audioCache[messageId] != nil { return true }
        // Check both mp3 and wav formats on disk
        return FileManager.default.fileExists(atPath: audioFileURL(for: messageId, format: .mp3).path) ||
               FileManager.default.fileExists(atPath: audioFileURL(for: messageId, format: .wav).path)
    }

    private func cacheAudio(_ data: Data, for messageId: String, format: TTSAudioFormat) {
        // Save to memory
        audioCache[messageId] = data
        audioFormatCache[messageId] = format

        // Save to disk with correct extension
        saveAudioToDisk(data, for: messageId, format: format)

        print("[TTSPlaybackService] Cached audio for message: \(messageId) (\(data.count) bytes, format: \(format.rawValue))")
    }

    private func getCachedAudio(for messageId: String) -> (data: Data, format: TTSAudioFormat)? {
        // Check memory first
        if let data = audioCache[messageId] {
            let format = audioFormatCache[messageId] ?? .mp3
            return (data, format)
        }

        // Check disk - try both formats
        for format in [TTSAudioFormat.mp3, .wav] {
            if let data = loadAudioFromDisk(for: messageId, format: format) {
                // Populate memory cache
                audioCache[messageId] = data
                audioFormatCache[messageId] = format
                return (data, format)
            }
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

    func speak(text: String, settings: AppSettings, messageId: String? = nil) async throws {
        print("[TTSPlaybackService] Starting TTS playback")
        print("[TTSPlaybackService] Text length: \(text.count) characters")
        print("[TTSPlaybackService] Provider: \(settings.ttsSettings.provider.displayName)")

        // Prime UI state so the player can show a loading indicator while we fetch audio
        isGenerating = true
        isPlaying = false
        currentMessageId = messageId
        currentTime = 0
        duration = 0
        let token = UUID()
        generationToken = token

        do {
            let audioData: Data
            let audioFormat: TTSAudioFormat

            switch settings.ttsSettings.provider {
            case .elevenlabs:
                audioData = try await generateElevenLabsAudio(text: text, settings: settings)
                audioFormat = .mp3

            case .gemini:
                audioData = try await generateGeminiAudio(text: text, settings: settings)
                audioFormat = .wav  // Gemini returns WAV format (24kHz)
            }

            print("[TTSPlaybackService] Received audio data: \(audioData.count) bytes (format: \(audioFormat.rawValue))")

            // Cache the audio if we have a message ID
            if let messageId = messageId {
                cacheAudio(audioData, for: messageId, format: audioFormat)
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

    func playGenerated(messageId: String) async throws {
        guard let cached = getCachedAudio(for: messageId) else {
            print("[TTSPlaybackService] No cached audio for message: \(messageId)")
            throw NSError(domain: "TTSPlaybackService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No generated audio found for this message"])
        }

        print("[TTSPlaybackService] Playing cached audio for message: \(messageId) (format: \(cached.format.rawValue))")
        try await playAudio(cached.data, messageId: messageId, format: cached.format)
    }

    private func playAudio(_ audioData: Data, messageId: String?, format: TTSAudioFormat = .mp3) async throws {
        print("[TTSPlaybackService] Preparing to play audio data: \(audioData.count) bytes (format: \(format.rawValue))")

        // Ensure audio session is active before creating player
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
            print("[TTSPlaybackService] Audio session activated")
        } catch {
            print("[TTSPlaybackService] Failed to activate audio session: \(error)")
            throw error
        }

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
