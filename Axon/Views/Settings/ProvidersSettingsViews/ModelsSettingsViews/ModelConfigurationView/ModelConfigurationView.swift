//
//  ModelConfigurationView.swift
//  Axon
//
//  Settings view for configuring AI model generation parameters
//  (temperature, top-p, top-k) and custom system prompt suffix.
//

import SwiftUI

struct ModelConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    private var settings: Binding<ModelGenerationSettings> {
        $viewModel.settings.modelGenerationSettings
    }
    
    var body: some View {
        Form {
            SystemPromptSection(settings: settings)
            TemperatureSection(settings: settings)
            SamplingParametersSection(settings: settings)
            RepetitionPenaltySection(settings: settings)
            MaxResponseTokensSection(settings: settings)
            ProviderCompatibilitySection()
            ResetSection(viewModel: viewModel)
        }
        .formStyle(.grouped)
        .navigationTitle("Model Tuning")
    }
}

#Preview {
    NavigationStack {
        ModelConfigurationView(viewModel: SettingsViewModel.shared)
    }
}
