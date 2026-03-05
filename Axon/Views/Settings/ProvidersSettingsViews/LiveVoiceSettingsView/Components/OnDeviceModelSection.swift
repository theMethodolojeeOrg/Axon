//
//  OnDeviceModelSection.swift
//  Axon
//
//  On-Device MLX model selection for Live Voice mode
//

import SwiftUI

/// Section for MLX model selection (on-device mode)
struct OnDeviceModelSection: View {
    @Binding var preferredMLXModel: String?
    let availableMLXModels: [String]

    var body: some View {
        Section {
            Picker("MLX Model", selection: mlxModelBinding) {
                Text("Default (Gemma3)").tag("")
                ForEach(availableMLXModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        } header: {
            Text("On-Device Model")
        } footer: {
            Text("Selects MLX model to use for on-device Live mode.")
        }
    }

    private var mlxModelBinding: Binding<String> {
        Binding(
            get: { preferredMLXModel ?? "" },
            set: { preferredMLXModel = $0.isEmpty ? nil : $0 }
        )
    }
}
