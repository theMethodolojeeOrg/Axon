//
//  TranscriptionTestController.swift
//  Axon
//
//  Controller for testing speech recognition with live feedback
//

import AVFoundation
import Combine

/// Controller for testing speech recognition with transcript and audio level display
@MainActor
class TranscriptionTestController: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private let speechService = SpeechRecognitionService.shared

    func startListening() {
        Task {
            // Request authorization if needed
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                transcript = "Speech recognition not authorized. Please enable in Settings."
                return
            }

            do {
                // Configure audio session with preferred sample rate (iOS only)
                #if os(iOS)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .measurement, options: [])
                try audioSession.setPreferredSampleRate(16000)
                try audioSession.setPreferredIOBufferDuration(0.005)
                try audioSession.setActive(true)
                #endif

                // Setup audio engine
                audioEngine = AVAudioEngine()
                guard let engine = audioEngine else { return }

                let inputNode = engine.inputNode

                // Start speech recognition
                try speechService.startRecognition()

                // Install tap for audio level and recognition using input node's native format (nil)
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                    Task { @MainActor in
                        // Update audio level
                        self?.updateAudioLevel(buffer: buffer)
                    }

                    // Send to speech recognition
                    self?.speechService.appendAudio(buffer: buffer)
                }

                try engine.start()
                isListening = true
                transcript = ""

                // Listen for transcript updates
                speechService.onTranscriptUpdate = { [weak self] text, isFinal in
                    Task { @MainActor in
                        self?.transcript = text
                    }
                }
            } catch {
                transcript = "Error: \(error.localizedDescription)"
            }
        }
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Deactivate audio session (iOS only)
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("[TranscriptionTest] Error deactivating audio session: \(error.localizedDescription)")
        }
        #endif

        speechService.stopRecognition()
        isListening = false
        audioLevel = 0
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        audioLevel = min(1.0, rms * 5) // Amplify for visibility
    }
}
