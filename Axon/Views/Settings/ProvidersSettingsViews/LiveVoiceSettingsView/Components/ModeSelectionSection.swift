//
//  ModeSelectionSection.swift
//  Axon
//
//  Mode selection for Live Voice (On-Device vs Cloud)
//

import SwiftUI

/// Section for selecting between on-device and cloud modes
struct ModeSelectionSection: View {
    @Binding var useOnDeviceModels: Bool

    var body: some View {
        Section {
            Toggle("Use On-Device Models", isOn: $useOnDeviceModels)
        } header: {
            Text("Mode")
        } footer: {
            if useOnDeviceModels {
                Text("Live mode runs entirely on-device using MLX models. No internet required.")
            } else {
                Text("Use cloud providers for real-time voice conversations.")
            }
        }
    }
}
