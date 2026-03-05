//
//  MaxResponseTokensSection.swift
//  Axon
//
//  Section for configuring maximum response tokens for local MLX models.
//

import SwiftUI

struct MaxResponseTokensSection: View {
    @Binding var settings: ModelGenerationSettings
    
    var body: some View {
        Section {
            Toggle("Limit Response Length", isOn: $settings.maxResponseTokensEnabled)

            if settings.maxResponseTokensEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Tokens")
                        Spacer()
                        Text("\(settings.maxResponseTokens)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { Double(settings.maxResponseTokens) },
                            set: { settings.maxResponseTokens = Int($0) }
                        ),
                        in: 128...4096,
                        step: 128
                    ) {
                        Text("Max Response Tokens")
                    } minimumValueLabel: {
                        Text("128")
                            .font(.caption2)
                    } maximumValueLabel: {
                        Text("4096")
                            .font(.caption2)
                    }

                    HStack {
                        Label("Short", systemImage: "text.alignleft")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("Long", systemImage: "text.justify")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Response Length")
                Spacer()
                Text("Local MLX Only")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        } footer: {
            Text("Limits how many tokens the model can generate. Lower values produce shorter, more concise responses. 1 token ≈ 0.75 words.")
        }
    }
}

#Preview {
    Form {
        MaxResponseTokensSection(settings: .constant(ModelGenerationSettings()))
    }
}
