//
//  MicrophonePreviewSection.swift
//  Axon
//
//  Microphone preview section for testing live input visualization
//

import SwiftUI

/// Section for testing microphone input with live waveform visualization
struct MicrophonePreviewSection: View {
    @ObservedObject var micPreviewController: MicrophonePreviewController
    @Binding var noiseGateEnabled: Bool
    @Binding var noiseGateThreshold: Float

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Test Microphone")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(action: {
                        if micPreviewController.isListening {
                            micPreviewController.stopListening()
                        } else {
                            micPreviewController.startListening(
                                noiseGateEnabled: noiseGateEnabled,
                                noiseGateThreshold: Float(noiseGateThreshold)
                            )
                        }
                    }) {
                        Image(systemName: micPreviewController.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(micPreviewController.isListening ? Color.red : Color.accentColor))
                    }
                    .buttonStyle(.plain)
                }

                // Live waveform visualization
                LiveWaveformView(
                    samples: micPreviewController.waveformSamples,
                    isActive: micPreviewController.isListening,
                    isGateOpen: micPreviewController.isNoiseGateOpen
                )
                .frame(height: 60)

                // Status indicators
                if micPreviewController.isListening {
                    HStack(spacing: 16) {
                        // Noise gate indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(micPreviewController.isNoiseGateOpen ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(micPreviewController.isNoiseGateOpen ? "Transmitting" : "Gate Closed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Peak level
                        Text("Level: \(Int(micPreviewController.peakLevel * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Microphone Preview")
        } footer: {
            Text("See how your microphone input looks to the AI. The noise gate filters out background sounds.")
        }
    }
}
