//
//  VoiceActivityDetectionSection.swift
//  Axon
//
//  Voice Activity Detection settings for Live Voice mode
//

import SwiftUI

/// Section for local VAD sensitivity settings
struct VoiceActivityDetectionSection: View {
    @Binding var useLocalVAD: Bool
    @Binding var vadSensitivity: Float

    var body: some View {
        Section {
            Toggle("Local Voice Detection", isOn: $useLocalVAD)

            if useLocalVAD {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(sensitivityLabel)
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $vadSensitivity,
                        in: 0...1,
                        step: 0.1
                    )
                }
            }
        } header: {
            Text("Voice Activity Detection")
        } footer: {
            Text("Local VAD detects when you start and stop speaking. Higher sensitivity picks up quieter speech.")
        }
    }

    private var sensitivityLabel: String {
        let value = vadSensitivity
        if value < 0.3 {
            return "Very Sensitive"
        } else if value < 0.5 {
            return "Sensitive"
        } else if value < 0.7 {
            return "Balanced"
        } else {
            return "Less Sensitive"
        }
    }
}
