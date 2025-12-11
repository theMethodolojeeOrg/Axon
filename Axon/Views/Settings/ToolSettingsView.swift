//
//  ToolSettingsView.swift
//  Axon
//
//  AI Tools configuration - enable web search, code execution, and more
//

import SwiftUI

struct ToolSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Master Toggle
            SettingsSection(title: "AI Tools") {
                VStack(spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.toolSettings.toolsEnabled },
                        set: { newValue in
                            Task {
                                var updated = viewModel.settings.toolSettings
                                updated.toolsEnabled = newValue
                                await viewModel.updateSetting(\.toolSettings, updated)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable AI Tools")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Allow AI to use external tools like web search and code execution")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .tint(AppColors.signalMercury)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            if viewModel.settings.toolSettings.toolsEnabled {
                // Gemini Tools Section
                SettingsSection(title: "Google (Gemini) Tools") {
                    VStack(spacing: 0) {
                        ForEach(ToolId.tools(for: .gemini)) { tool in
                            ToolToggleRow(
                                tool: tool,
                                isEnabled: viewModel.settings.toolSettings.enabledToolIds.contains(tool.rawValue),
                                onToggle: { enabled in
                                    Task {
                                        var updated = viewModel.settings.toolSettings
                                        if enabled {
                                            updated.enableTool(tool)
                                        } else {
                                            updated.disableTool(tool)
                                        }
                                        await viewModel.updateSetting(\.toolSettings, updated)
                                    }
                                }
                            )

                            if tool != ToolId.tools(for: .gemini).last {
                                Divider()
                                    .background(AppColors.divider)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)

                    // API key requirement notice
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12))
                        Text("Requires Gemini API key in Settings > API Keys")
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                }

                // Built-in Tools Section
                SettingsSection(title: "Built-in Tools") {
                    VStack(spacing: 0) {
                        ForEach(ToolId.tools(for: .internal)) { tool in
                            ToolToggleRow(
                                tool: tool,
                                isEnabled: viewModel.settings.toolSettings.enabledToolIds.contains(tool.rawValue),
                                onToggle: { enabled in
                                    Task {
                                        var updated = viewModel.settings.toolSettings
                                        if enabled {
                                            updated.enableTool(tool)
                                        } else {
                                            updated.disableTool(tool)
                                        }
                                        await viewModel.updateSetting(\.toolSettings, updated)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }

                // Configuration Section
                SettingsSection(title: "Configuration") {
                    VStack(spacing: 20) {
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

                            Text("Maximum number of tool calls the AI can make in a single response")
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
                    .cornerRadius(8)
                }
            }

            // Experimental Section - Only show if experimental features enabled
            if viewModel.settings.toolSettings.experimentalFeaturesEnabled {
                SettingsSection(title: "Experimental") {
                    VStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { viewModel.settings.toolSettings.mediaProxyEnabled },
                            set: { newValue in
                                Task {
                                    var updated = viewModel.settings.toolSettings
                                    updated.mediaProxyEnabled = newValue
                                    await viewModel.updateSetting(\.toolSettings, updated)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("Gemini Media Proxy")
                                        .font(AppTypography.bodyMedium(.medium))
                                        .foregroundColor(AppColors.textPrimary)

                                    Text("BETA")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.accentWarning)
                                        .cornerRadius(4)
                                }

                                Text("Proxy video/audio through Gemini for non-Gemini models")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .tint(AppColors.signalMercury)

                        // Warning about experimental status
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.accentWarning)
                            Text("This feature is experimental and may not work reliably.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }
            }

            // Experimental Features Toggle (always visible)
            SettingsSection(title: "Advanced") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.toolSettings.experimentalFeaturesEnabled },
                    set: { newValue in
                        Task {
                            var updated = viewModel.settings.toolSettings
                            updated.experimentalFeaturesEnabled = newValue
                            await viewModel.updateSetting(\.toolSettings, updated)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Experimental Features")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Enable beta features that are still in development")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.signalMercury)
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // How It Works Section
            SettingsSection(title: "How It Works") {
                VStack(spacing: 12) {
                    ToolInfoRow(
                        icon: "sparkles",
                        title: "Native Execution",
                        description: "Tools are called directly via Gemini API from your device - no backend needed",
                        color: AppColors.signalMercury
                    )

                    ToolInfoRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Smart Tool Use",
                        description: "Your AI decides when to use tools based on your query",
                        color: AppColors.signalLichen
                    )

                    ToolInfoRow(
                        icon: "bolt.fill",
                        title: "Real-Time Data",
                        description: "Get current information like search results, code execution, and more",
                        color: AppColors.signalCopper
                    )
                }
            }
        }
    }
}

// MARK: - Tool Toggle Row

struct ToolToggleRow: View {
    let tool: ToolId
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isEnabled },
            set: { onToggle($0) }
        )) {
            HStack(spacing: 12) {
                Image(systemName: tool.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(tool.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .tint(AppColors.signalMercury)
        .padding(.vertical, 8)
    }
}

// MARK: - Tool Info Row

struct ToolInfoRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ToolSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
