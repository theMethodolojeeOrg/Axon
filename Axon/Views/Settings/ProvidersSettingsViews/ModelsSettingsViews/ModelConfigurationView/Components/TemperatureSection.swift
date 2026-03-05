//
//  TemperatureSection.swift
//  Axon
//
//  Section for configuring model temperature parameter.
//

import SwiftUI

struct TemperatureSection: View {
    @Binding var settings: ModelGenerationSettings
    
    var body: some View {
        Section {
            Toggle("Enable Custom Temperature", isOn: $settings.temperatureEnabled)
            
            if settings.temperatureEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", settings.temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                    Slider(
                        value: $settings.temperature,
                        in: 0...1,
                        step: 0.1
                    ) {
                        Text("Temperature")
                    } minimumValueLabel: {
                        Text("0")
                            .font(.caption2)
                    } maximumValueLabel: {
                        Text("1")
                            .font(.caption2)
                    }
                    
                    HStack {
                        Label("Deterministic", systemImage: "target")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Label("Creative", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Temperature")
        } footer: {
            Text("Controls randomness. Lower values (0.0-0.3) for factual tasks, higher values (0.7-1.0) for creative writing.")
        }
    }
}

#Preview {
    Form {
        TemperatureSection(settings: .constant(ModelGenerationSettings()))
    }
}
