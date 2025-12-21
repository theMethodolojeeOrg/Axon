//
//  AutomationSettingsView.swift
//  Axon
//
//  Category view for automation-related settings: Tools, Pipelines, and Intents
//

import SwiftUI

struct AutomationSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var dynamicToolService = DynamicToolConfigurationService.shared

    // MARK: - Dynamic Subtitles

    private var toolsSubtitle: String {
        let settings = viewModel.settings.toolSettings
        if !settings.toolsEnabled {
            return "Tools disabled"
        }
        let enabledCount = settings.enabledTools.count
        let totalCount = ToolId.allCases.count
        return "\(enabledCount) of \(totalCount) enabled"
    }

    private var pipelinesSubtitle: String {
        if let catalog = dynamicToolService.activeCatalog {
            let enabledCount = catalog.tools.filter { $0.enabled }.count
            let totalCount = catalog.tools.count
            if totalCount == 0 {
                return "No pipelines configured"
            }
            return "\(enabledCount) of \(totalCount) enabled"
        }
        return "Custom tool pipelines"
    }

    private var intentsSubtitle: String {
        return "Siri & Shortcuts"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tools
            NavigationLink {
                ToolSettingsView(viewModel: viewModel)
            } label: {
                SettingsCategoryRow(
                    icon: "wrench.and.screwdriver.fill",
                    iconColor: AppColors.signalMercury,
                    title: "Tools",
                    subtitle: toolsSubtitle
                )
            }
            .buttonStyle(.plain)

            // Pipelines (Dynamic Tools)
            NavigationLink {
                DynamicToolsSettingsView(viewModel: viewModel)
            } label: {
                SettingsCategoryRow(
                    icon: "arrow.triangle.branch",
                    iconColor: AppColors.signalLichen,
                    title: "Pipelines",
                    subtitle: pipelinesSubtitle
                )
            }
            .buttonStyle(.plain)

            // Intents
            NavigationLink {
                IntentsSettingsView()
            } label: {
                SettingsCategoryRow(
                    icon: "app.connected.to.app.below.fill",
                    iconColor: AppColors.signalCopper,
                    title: "Intents",
                    subtitle: intentsSubtitle
                )
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Automation")
    }
}

#Preview {
    NavigationStack {
        AutomationSettingsView(viewModel: SettingsViewModel.shared)
    }
}
