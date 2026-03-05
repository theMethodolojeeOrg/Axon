//
//  RepetitionPenaltySection.swift
//  Axon
//
//  Section for configuring repetition penalty for local MLX models.
//

import SwiftUI

struct RepetitionPenaltySection: View {
    @Binding var settings: ModelGenerationSettings
    
    var body: some View {
        Section {
            Toggle("Enable Repetition Penalty", isOn: $settings.repetitionPenaltyEnabled)

            if settings.repetitionPenaltyEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Penalty Strength")
                        Spacer()
                        Text(String(format: "%.1f", settings.repetitionPenalty))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $settings.repetitionPenalty,
                        in: 1.0...2.0,
                        step: 0.1
                    ) {
                        Text("Repetition Penalty")
                    } minimumValueLabel: {
                        Text("1.0")
                            .font(.caption2)
                    } maximumValueLabel: {
                        Text("2.0")
                            .font(.caption2)
                    }

                    HStack {
                        Label("No penalty", systemImage: "arrow.trianglehead.counterclockwise")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("Strong penalty", systemImage: "xmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Context Window")
                        Spacer()
                        Text("\(settings.repetitionContextSize) tokens")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(settings.repetitionContextSize) },
                            set: { settings.repetitionContextSize = Int($0) }
                        ),
                        in: 16...256,
                        step: 16
                    )
                }
            }
        } header: {
            HStack {
                Text("Repetition Penalty")
                Spacer()
                Text("Local MLX Only")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Prevents repetitive loops in local model output. Higher values (1.3-1.5) more aggressively discourage repeated phrases. Context window determines how far back to check for repetition.")
        }
    }
}

#Preview {
    Form {
        RepetitionPenaltySection(settings: .constant(ModelGenerationSettings()))
    }
}
