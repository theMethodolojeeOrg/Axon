//
//  NoiseGateSection.swift
//  Axon
//
//  Noise Gate settings for Live Voice mode
//

import SwiftUI

/// Section for noise gate threshold and hold time settings
struct NoiseGateSection: View {
    @Binding var noiseGateEnabled: Bool
    @Binding var noiseGateThreshold: Float
    @Binding var noiseGateHoldMs: Int

    var body: some View {
        Section {
            Toggle("Noise Gate", isOn: $noiseGateEnabled)

            if noiseGateEnabled {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Threshold")
                        Spacer()
                        Text(noiseGateThresholdLabel)
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $noiseGateThreshold,
                        in: 0.005...0.1,
                        step: 0.005
                    )
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Hold Time")
                        Spacer()
                        Text("\(noiseGateHoldMs) ms")
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: noiseGateHoldBinding,
                        in: 50...500,
                        step: 50
                    )
                }
            }
        } header: {
            Text("Noise Gate")
        } footer: {
            Text("Filters out background noise. Higher threshold blocks more ambient sounds but may cut off quiet speech.")
        }
    }

    private var noiseGateThresholdLabel: String {
        let value = noiseGateThreshold
        if value < 0.015 {
            return "Very Low"
        } else if value < 0.03 {
            return "Low"
        } else if value < 0.05 {
            return "Medium"
        } else if value < 0.07 {
            return "High"
        } else {
            return "Very High"
        }
    }

    private var noiseGateHoldBinding: Binding<Double> {
        Binding(
            get: { Double(noiseGateHoldMs) },
            set: { noiseGateHoldMs = Int($0) }
        )
    }
}
