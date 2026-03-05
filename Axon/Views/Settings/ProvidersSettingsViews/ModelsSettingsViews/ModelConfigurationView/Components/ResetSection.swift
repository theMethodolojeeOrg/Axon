//
//  ResetSection.swift
//  Axon
//
//  Section with button to reset model configuration to defaults.
//

import SwiftUI

struct ResetSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Section {
            Button(role: .destructive) {
                resetToDefaults()
            } label: {
                Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
            }
        }
    }
    
    private func resetToDefaults() {
        viewModel.settings.modelGenerationSettings = ModelGenerationSettings()
    }
}

#Preview {
    Form {
        ResetSection(viewModel: SettingsViewModel.shared)
    }
}
