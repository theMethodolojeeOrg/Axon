//
//  MicrophonePreviewController.swift
//  Axon
//
//  Controller for live microphone input visualization
//

import AVFoundation
import Combine

/// Controller for visualizing live microphone input with noise gate support
@MainActor
class MicrophonePreviewController: ObservableObject {
    @Published var isListening = false
    @Published var waveformSamples: [Float] = Array(repeating: 0.0, count: 64)
    @Published var peakLevel: Float = 0
    @Published var isNoiseGateOpen = false

    private var audioEngine: AVAudioEngine?
    private var noiseGateEnabled = true
    private var noiseGateThreshold: Float = 0.02
    private var sampleIndex = 0

    func startListening(noiseGateEnabled: Bool, noiseGateThreshold: Float) {
        self.noiseGateEnabled = noiseGateEnabled
        self.noiseGateThreshold = Float(noiseGateThreshold)

            do {
            // Configure audio session with preferred sample rate (iOS only)
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setPreferredSampleRate(16000)
            try audioSession.setPreferredIOBufferDuration(0.005)
            try audioSession.setActive(true)
            #endif

            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }

            let inputNode = engine.inputNode

            // Install tap for audio visualization using input node's native format (nil)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                Task { @MainActor in
                    self?.processAudioBuffer(buffer)
                }
            }

            try engine.start()
            isListening = true
            waveformSamples = Array(repeating: 0.0, count: 64)
            sampleIndex = 0
        } catch {
            print("[MicPreview] Error starting audio engine: \(error.localizedDescription)")
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
            print("[MicPreview] Error deactivating audio session: \(error.localizedDescription)")
        }
        #endif

        isListening = false
        peakLevel = 0
        isNoiseGateOpen = false
        waveformSamples = Array(repeating: 0.0, count: 64)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        // Calculate RMS level
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        peakLevel = min(1.0, rms * 5) // Amplify for visibility

        // Check noise gate
        if noiseGateEnabled {
            isNoiseGateOpen = rms > noiseGateThreshold
        } else {
            isNoiseGateOpen = true
        }

        // Update waveform samples (rolling buffer)
        let normalizedLevel = min(1.0, rms * 8) // Amplify for visualization
        waveformSamples[sampleIndex % 64] = normalizedLevel
        sampleIndex += 1

        // Shift samples for scrolling effect
        if sampleIndex >= 64 {
            waveformSamples = Array(waveformSamples.dropFirst()) + [normalizedLevel]
        }
    }
}
