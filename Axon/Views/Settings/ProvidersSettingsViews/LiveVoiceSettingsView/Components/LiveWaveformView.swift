//
//  LiveWaveformView.swift
//  Axon
//
//  Scrolling waveform visualization for live microphone input
//

import SwiftUI

/// View for displaying scrolling microphone input waveform with noise gate status
struct LiveWaveformView: View {
    let samples: [Float]
    let isActive: Bool
    let isGateOpen: Bool

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 1) {
                ForEach(0..<samples.count, id: \.self) { index in
                    let sample = samples.indices.contains(index) ? samples[index] : 0.0
                    let barHeight = max(2, CGFloat(sample) * geometry.size.height)

                    Capsule()
                        .fill(barColor(for: sample))
                        .frame(
                            width: max(2, (geometry.size.width - CGFloat(samples.count)) / CGFloat(samples.count)),
                            height: barHeight
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? (isGateOpen ? Color.green.opacity(0.5) : Color.gray.opacity(0.3)) : Color.clear, lineWidth: 2)
                )
        )
        .animation(.easeOut(duration: 0.05), value: samples)
    }

    private func barColor(for sample: Float) -> Color {
        if !isActive {
            return Color.gray.opacity(0.3)
        }

        if !isGateOpen {
            return Color.gray.opacity(0.5)
        }

        // Color gradient based on level
        if sample > 0.8 {
            return Color.red
        } else if sample > 0.5 {
            return Color.orange
        } else if sample > 0.2 {
            return Color.green
        } else {
            return Color.green.opacity(0.7)
        }
    }
}
