//
//  ModelSelectionSection.swift
//  Axon
//
//  Model selection section for ChatInfoSettingsView
//

import SwiftUI

struct ChatModelSelectionSection: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    
    let provider: UnifiedProvider?
    @Binding var selectedModel: UnifiedModel?
    let estimatedTokens: Int
    
    let onModelSelected: (UnifiedModel) -> Void
    
    var body: some View {
        ChatInfoSection(title: "Model") {
            if let provider = provider ?? settingsViewModel.currentUnifiedProvider() {
                let providerIndex = settingsViewModel.settings.customProviders.firstIndex(where: {
                    if case .custom(let config) = provider {
                        return $0.id == config.id
                    }
                    return false
                }) ?? 0
                
                UnifiedModelPicker(
                    provider: provider,
                    customProviderIndex: providerIndex + 1,
                    selectedModel: $selectedModel,
                    estimatedTokens: estimatedTokens,
                    showInsufficientModels: true,
                    showInfoCard: false,
                    onModelSelected: onModelSelected
                )
            }
        }
    }
}

#Preview {
    ChatModelSelectionSection(
        settingsViewModel: SettingsViewModel(),
        provider: nil,
        selectedModel: .constant(nil),
        estimatedTokens: 5000,
        onModelSelected: { _ in }
    )
    .padding()
    .background(AppSurfaces.color(.contentBackground))
}
