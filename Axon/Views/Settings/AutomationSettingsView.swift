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
    @StateObject private var toolsV2Toggle = ToolsV2Toggle.shared
    @StateObject private var pluginLoader = ToolPluginLoader.shared

    // MARK: - Dynamic Subtitles

    private var toolsSubtitle: String {
        // Show V2 stats if V2 is active
        if toolsV2Toggle.isV2Active {
            let stats = pluginLoader.stats
            if stats.totalCount == 0 {
                return "Plugin system - loading..."
            }
            return "\(stats.enabledCount) of \(stats.totalCount) enabled (V2)"
        }

        // V1 stats
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
            // Tool System Quick Toggle
            ToolSystemQuickToggle(toolsToggle: toolsV2Toggle)

            // Tools - routes to V1 or V2 view based on toggle
            NavigationLink {
                SettingsSubviewContainer {
                    if toolsV2Toggle.isV2Active {
                        ToolSettingsViewV2(viewModel: viewModel)
                    } else {
                        ToolSettingsView(viewModel: viewModel)
                    }
                }
            } label: {
                SettingsCategoryRow(
                    icon: toolsV2Toggle.isV2Active ? "puzzlepiece.extension.fill" : "wrench.and.screwdriver.fill",
                    iconColor: AppColors.signalMercury,
                    title: "Tools",
                    subtitle: toolsSubtitle
                )
            }
            .buttonStyle(.plain)

            // Pipelines (Dynamic Tools)
            NavigationLink {
                SettingsSubviewContainer {
                    DynamicToolsSettingsView(viewModel: viewModel)
                }
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
                SettingsSubviewContainer {
                    IntentsSettingsView()
                }
            } label: {
                SettingsCategoryRow(
                    icon: "app.connected.to.app.below.fill",
                    iconColor: AppColors.signalCopper,
                    title: "Intents",
                    subtitle: intentsSubtitle
                )
            }
            .buttonStyle(.plain)

            // Tool Execution Configuration (applies to V1 and V2)
            ToolExecutionConfigSection(viewModel: viewModel)
        }
        .navigationTitle("Automation")
    }
}

// MARK: - Tool Execution Configuration Section

/// Configuration settings that apply globally to all tool execution (V1 and V2)
private struct ToolExecutionConfigSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text("Tool Execution")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 20) {
                // Execution Mode Toggle
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Execution Mode")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        // Segmented picker for immediate/deferred
                        Picker("", selection: Binding(
                            get: { viewModel.settings.toolSettings.executionMode },
                            set: { newMode in
                                Task {
                                    var updated = viewModel.settings.toolSettings
                                    updated.executionMode = newMode
                                    await viewModel.updateSetting(\.toolSettings, updated)
                                }
                            }
                        )) {
                            ForEach(ToolExecutionMode.allCases) { mode in
                                Label(mode.displayName, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                    Text(viewModel.settings.toolSettings.executionMode.description)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Divider()
                    .background(AppColors.divider)

                // Max Tool Calls Per Turn
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Tool Calls Per Turn")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Text("\(viewModel.settings.toolSettings.maxToolCallsPerTurn)")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.settings.toolSettings.maxToolCallsPerTurn) },
                            set: { newValue in
                                Task {
                                    var updated = viewModel.settings.toolSettings
                                    updated.maxToolCallsPerTurn = Int(newValue)
                                    await viewModel.updateSetting(\.toolSettings, updated)
                                }
                            }
                        ),
                        in: 1...10,
                        step: 1
                    )
                    .tint(AppColors.signalMercury)

                    Text("Maximum number of tool calls per response")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Divider()
                    .background(AppColors.divider)

                // Tool Timeout
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tool Timeout")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Text("\(viewModel.settings.toolSettings.toolTimeout)s")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.settings.toolSettings.toolTimeout) },
                            set: { newValue in
                                Task {
                                    var updated = viewModel.settings.toolSettings
                                    updated.toolTimeout = Int(newValue)
                                    await viewModel.updateSetting(\.toolSettings, updated)
                                }
                            }
                        ),
                        in: 10...120,
                        step: 10
                    )
                    .tint(AppColors.signalMercury)

                    Text("How long to wait for tool execution before timing out")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(12)

            // Info text
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("These settings apply to all tool systems (V1 and V2)")
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Tool System Quick Toggle

/// Compact toggle for switching between V1 and V2 tool systems
private struct ToolSystemQuickToggle: View {
    @ObservedObject var toolsToggle: ToolsV2Toggle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toolsToggle.activeVersion.icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 2) {
                Text("Tool System")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(toolsToggle.activeVersion.displayName)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Quick toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    _ = toolsToggle.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(toolsToggle.isV2Active ? "V2" : "V1")
                        .font(AppTypography.labelSmall())
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
                }
                .foregroundColor(AppColors.signalMercury)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.signalMercury.opacity(0.15))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        AutomationSettingsView(viewModel: SettingsViewModel.shared)
    }
}
