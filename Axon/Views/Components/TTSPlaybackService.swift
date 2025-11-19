//
//  TTSPlaybackService.swift
//  Axon
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class TTSPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = TTSPlaybackService()

    private var player: AVAudioPlayer?

    @Published var isPlaying = false
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
        currentMessageId = nil
        currentTime = 0
        duration = 0
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
        return FileManager.default.fileExists(atPath: audioFileURL(for: messageId).path)
    }

    private func cacheAudio(_ data: Data, for messageId: String) {
        // Save to memory
        audioCache[messageId] = data
        
        // Save to disk
        saveAudioToDisk(data, for: messageId)
        
        print("[TTSPlaybackService] Cached audio for message: \(messageId) (\(data.count) bytes)")
    }

    private func getCachedAudio(for messageId: String) -> Data? {
        // Check memory first
        if let data = audioCache[messageId] {
            return data
        }
        
        // Check disk
        if let data = loadAudioFromDisk(for: messageId) {
            // Populate memory cache
            audioCache[messageId] = data
            return data
        }
        
        return nil
    }
    
    // MARK: - Persistence Helpers
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func audioFileURL(for messageId: String) -> URL {
        let directory = getDocumentsDirectory().appendingPathComponent("AudioCache")
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(messageId).mp3")
    }

    private func saveAudioToDisk(_ data: Data, for messageId: String) {
        let url = audioFileURL(for: messageId)
        do {
            try data.write(to: url)
            print("[TTSPlaybackService] Saved audio to disk: \(url.path)")
        } catch {
            print("[TTSPlaybackService] Failed to save audio to disk: \(error)")
        }
    }

    private func loadAudioFromDisk(for messageId: String) -> Data? {
        let url = audioFileURL(for: messageId)
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
        print("[TTSPlaybackService] Settings loaded - Voice ID: \(settings.ttsSettings.selectedVoiceId ?? "nil"), Voice Name: \(settings.ttsSettings.selectedVoiceName ?? "nil")")

        guard let voiceId = settings.ttsSettings.selectedVoiceId else {
            print("[TTSPlaybackService] Error: No voice selected in TTS settings")
            throw NSError(domain: "TTSPlaybackService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No voice selected in TTS settings. Please select a voice in Settings > Text-to-Speech."])
        }

        print("[TTSPlaybackService] Using voice ID: \(voiceId)")
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
        let audioData = try await ElevenLabsService.shared.generateTTSBase64(
            text: text,
            voiceId: voiceId,
            model: settings.ttsSettings.model.rawValue,
            format: settings.ttsSettings.outputFormat.rawValue,
            voiceSettings: payload
        )

        print("[TTSPlaybackService] Received audio data: \(audioData.count) bytes")

        // Cache the audio if we have a message ID
        if let messageId = messageId {
            cacheAudio(audioData, for: messageId)
        }

        // Play the audio
        try await playAudio(audioData, messageId: messageId)
    }

    func playGenerated(messageId: String) async throws {
        guard let audioData = getCachedAudio(for: messageId) else {
            print("[TTSPlaybackService] No cached audio for message: \(messageId)")
            throw NSError(domain: "TTSPlaybackService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No generated audio found for this message"])
        }

        print("[TTSPlaybackService] Playing cached audio for message: \(messageId)")
        try await playAudio(audioData, messageId: messageId)
    }

    private func playAudio(_ audioData: Data, messageId: String?) async throws {
        print("[TTSPlaybackService] Preparing to play audio data: \(audioData.count) bytes")

        // Ensure audio session is active before creating player
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
            print("[TTSPlaybackService] Audio session activated")
        } catch {
            print("[TTSPlaybackService] Failed to activate audio session: \(error)")
            throw error
        }

        // Create and configure audio player
        self.player = try AVAudioPlayer(data: audioData)
        self.player?.delegate = self
        print("[TTSPlaybackService] AVAudioPlayer created successfully")

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
