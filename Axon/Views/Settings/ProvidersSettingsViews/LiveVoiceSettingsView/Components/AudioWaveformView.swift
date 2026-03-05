//
//  AudioWaveformView.swift
//  Axon
//
//  Static waveform visualization for TTS playback
//

import SwiftUI

/// View for displaying static audio waveform with playback progress
struct AudioWaveformView: View {
    let samples: [Float]
    let progress: Double
    let isPlaying: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<samples.count, id: \.self) { index in
                    let sample = samples.indices.contains(index) ? samples[index] : 0.3
                    let progressIndex = Int(progress * Double(samples.count))
                    let isPast = index < progressIndex

                    Capsule()
                        .fill(isPast ? Color.accentColor : Color.accentColor.opacity(0.3))
                        .frame(width: max(2, (geometry.size.width - CGFloat(samples.count) * 2) / CGFloat(samples.count)),
                               height: CGFloat(sample) * geometry.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.2), Color.orange.opacity(0.2), Color.red.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .cornerRadius(8)
        )
    }
}
