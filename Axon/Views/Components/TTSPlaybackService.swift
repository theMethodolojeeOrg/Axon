//
//  TTSPlaybackService.swift
//  Axon
//

import Foundation
import AVFoundation

@MainActor
final class TTSPlaybackService: ObservableObject {
    static let shared = TTSPlaybackService()

    private var player: AVAudioPlayer?

    private init() {}

    func stop() {
        player?.stop()
        player = nil
    }

    func speak(text: String, settings: AppSettings) async throws {
        guard let voiceId = settings.ttsSettings.selectedVoiceId else {
            throw NSError(domain: "TTSPlaybackService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No voice selected in TTS settings"]) 
        }

        let vs = settings.ttsSettings.voiceSettings
        let payload = ElevenLabsService.VoiceSettingsPayload(
            stability: vs.stability,
            similarityBoost: vs.similarityBoost,
            style: vs.style,
            useSpeakerBoost: vs.useSpeakerBoost
        )

        let audioData = try await ElevenLabsService.shared.generateTTSBase64(
            text: text,
            voiceId: voiceId,
            model: settings.ttsSettings.model.rawValue,
            format: settings.ttsSettings.outputFormat.rawValue,
            voiceSettings: payload
        )

        self.player = try AVAudioPlayer(data: audioData)
        self.player?.prepareToPlay()
        self.player?.play()
    }
}
