//
//  VoicePreviewController.swift
//  Axon
//
//  Controller for TTS voice preview playback
//

import AVFoundation
import Combine
#if os(macOS)
import AppKit
#endif

/// Controller for playing TTS voice previews with waveform visualization
@MainActor
class VoicePreviewController: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var playbackProgress: Double = 0
    @Published var waveformSamples: [Float] = Array(repeating: 0.3, count: 50)

    private var audioPlayer: AVAudioPlayer?
    private var displayLink: Timer?
    private var playerDelegate: AudioPlayerDelegateWrapper?

    private let previewText = "Hello! I'm your AI assistant. How can I help you today?"

    func playPreview(voice: KokoroTTSVoice, engine: TTSEngine) async {
        if isPlaying {
            stop()
            return
        }

        guard engine == .kokoro else {
            // System TTS preview
            await playSystemTTSPreview()
            return
        }

        isLoading = true

        do {
            let ttsService = KokoroTTSService.shared

            // Generate speech
            let audioData = try await ttsService.generateSpeech(
                text: previewText,
                voice: voice,
                speed: 1.0
            )

            // Generate waveform samples from audio
            waveformSamples = generateWaveformSamples(from: audioData)

            // Play audio
            audioPlayer = try AVAudioPlayer(data: audioData)
            playerDelegate = AudioPlayerDelegateWrapper { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.stopDisplayLink()
                }
            }
            audioPlayer?.delegate = playerDelegate
            audioPlayer?.play()
            isPlaying = true
            isLoading = false

            startDisplayLink()
        } catch {
            print("[AudioPreview] Error: \(error.localizedDescription)")
            isLoading = false
        }
    }

    private func playSystemTTSPreview() async {
        #if os(macOS)
        let synthesizer = NSSpeechSynthesizer()
        synthesizer.startSpeaking(previewText)
        #else
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: previewText)
        synthesizer.speak(utterance)
        #endif

        // Generate placeholder waveform
        waveformSamples = (0..<50).map { _ in Float.random(in: 0.2...0.8) }
        isPlaying = true

        // Approximate duration
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        isPlaying = false
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        playerDelegate = nil
        isPlaying = false
        playbackProgress = 0
        stopDisplayLink()
    }

    private func startDisplayLink() {
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.playbackProgress = player.currentTime / player.duration
            }
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        playbackProgress = 0
    }

    private func generateWaveformSamples(from data: Data) -> [Float] {
        // Simple waveform extraction - sample amplitude at regular intervals
        let sampleCount = 50
        var samples: [Float] = []

        // Treat data as Int16 samples
        let int16Count = data.count / 2
        guard int16Count > 0 else { return Array(repeating: 0.3, count: sampleCount) }

        let step = max(1, int16Count / sampleCount)

        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for i in stride(from: 0, to: min(int16Count, sampleCount * step), by: step) {
                let sample = Float(abs(int16Buffer[i])) / 32768.0
                samples.append(min(1.0, sample * 2)) // Amplify for visibility
            }
        }

        // Ensure we have enough samples
        while samples.count < sampleCount {
            samples.append(0.3)
        }

        return samples
    }
}

