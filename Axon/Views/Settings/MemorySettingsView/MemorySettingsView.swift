//
//  MemorySettingsView.swift
//  Axon
//
//  Memory system configuration and preferences
//

import SwiftUI

struct MemorySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            MemorySystemSection(viewModel: viewModel)
            if viewModel.settings.memoryEnabled {
                MemoryRetrievalSection(viewModel: viewModel)
            }
            MemoryTypesSection(viewModel: viewModel)
            if viewModel.settings.memoryEnabled {
                EpistemicEngineSection(viewModel: viewModel)
                DebuggingSection(viewModel: viewModel)
            }
            AnalyticsSection(viewModel: viewModel)
            InternalThreadSection(viewModel: viewModel)
            HeartbeatSection(viewModel: viewModel)
            NotificationsSection(viewModel: viewModel)
            if viewModel.settings.memoryEnabled {
                HeuristicsSection(viewModel: viewModel)
                if viewModel.settings.heuristicsSettings.enabled {
                    SmallModelOptimizationSection(viewModel: viewModel)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MemorySettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppSurfaces.color(.contentBackground))
}
