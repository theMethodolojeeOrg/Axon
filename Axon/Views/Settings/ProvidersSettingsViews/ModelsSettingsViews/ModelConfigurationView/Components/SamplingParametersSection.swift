//
//  SamplingParametersSection.swift
//  Axon
//
//  Section for configuring Top-P and Top-K sampling parameters.
//

import SwiftUI

struct SamplingParametersSection: View {
    @Binding var settings: ModelGenerationSettings
    
    var body: some View {
        Section {
            // Top-P
            Toggle("Enable Top-P (Nucleus Sampling)", isOn: $settings.topPEnabled)
            
            if settings.topPEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top-P")
                        Spacer()
                        Text(String(format: "%.2f", settings.topP))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: $settings.topP,
                        in: 0...1,
                        step: 0.05
                    )
                }
            }
            
            // Top-K
            Toggle("Enable Top-K", isOn: $settings.topKEnabled)
            
            if settings.topKEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Top-K")
                        Spacer()
                        Text("\(settings.topK)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(settings.topK) },
                            set: { settings.topK = Int($0) }
                        ),
                        in: 1...100,
                        step: 1
                    )
                    
                    Text("Only supported by Anthropic and Gemini")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Sampling Parameters")
        } footer: {
            Text("Advanced controls for token selection. Top-P limits choices to a cumulative probability threshold. Top-K limits to the K most likely tokens.")
        }
    }
}

#Preview {
    Form {
        SamplingParametersSection(settings: .constant(ModelGenerationSettings()))
    }
}
