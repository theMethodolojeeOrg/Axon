//
//  ToolsStatusMenu.swift
//  Axon
//
//  Lightweight UI component to show enabled tools status (Settings > Tools)
//

import SwiftUI

struct ToolsStatusMenu: View {
    enum Style {
        case iconOnly
        case pill
    }

    var style: Style = .pill

    @ObservedObject private var settingsViewModel = SettingsViewModel.shared
    @ObservedObject private var toolPluginLoader = ToolPluginLoader.shared
    @ObservedObject private var toolsToggle = ToolsV2Toggle.shared

    // MARK: - Active Tool System

    /// Whether V2 plugin system is the active tool system
    private var isV2Active: Bool {
        toolsToggle.isV2Active
    }

    // MARK: - V1 Tools (Legacy)

    /// V1 tools are enabled only when V1 is active AND master toggle is on
    private var hasV1ToolsEnabled: Bool {
        !isV2Active &&
        settingsViewModel.settings.toolSettings.toolsEnabled &&
        !settingsViewModel.settings.toolSettings.enabledToolIds.isEmpty
    }

    private var v1EnabledToolCount: Int {
        guard !isV2Active && settingsViewModel.settings.toolSettings.toolsEnabled else { return 0 }
        return settingsViewModel.settings.toolSettings.enabledToolIds.count
    }

    /// Group enabled V1 tools by category for organized display
    private var groupedV1EnabledTools: [(category: ToolCategory, tools: [ToolId])] {
        guard hasV1ToolsEnabled else { return [] }
        let enabledTools = settingsViewModel.settings.toolSettings.enabledTools
        let grouped = Dictionary(grouping: enabledTools) { $0.category }
        return grouped.keys.sorted { $0.displayName < $1.displayName }
            .map { (category: $0, tools: grouped[$0] ?? []) }
    }

    // MARK: - V2 Tools (Plugin System)

    /// V2 tools are enabled only when V2 is active AND master toggle is on
    private var hasV2ToolsEnabled: Bool {
        isV2Active &&
        toolPluginLoader.masterToolsEnabled &&
        !toolPluginLoader.enabledTools.isEmpty
    }

    private var v2EnabledToolCount: Int {
        guard isV2Active && toolPluginLoader.masterToolsEnabled else { return 0 }
        return toolPluginLoader.enabledTools.count
    }

    /// Group enabled V2 tools by category for organized display
    private var groupedV2EnabledTools: [(category: ToolCategoryV2, tools: [LoadedTool])] {
        guard hasV2ToolsEnabled else { return [] }
        let grouped = Dictionary(grouping: toolPluginLoader.enabledTools) { $0.category }
        return grouped.keys.sorted { $0.displayName < $1.displayName }
            .map { (category: $0, tools: grouped[$0] ?? []) }
    }

    // MARK: - Combined

    private var hasToolsEnabled: Bool {
        hasV1ToolsEnabled || hasV2ToolsEnabled
    }

    private var enabledToolCount: Int {
        v1EnabledToolCount + v2EnabledToolCount
    }

    /// Status text for the menu header
    private var statusText: String {
        if !hasToolsEnabled {
            if isV2Active && !toolPluginLoader.masterToolsEnabled {
                return "Tools disabled"
            } else if !isV2Active && !settingsViewModel.settings.toolSettings.toolsEnabled {
                return "Tools disabled"
            }
            return "No tools enabled"
        }
        return "\(enabledToolCount) tool\(enabledToolCount == 1 ? "" : "s") enabled"
    }

    /// Which tool system is currently active
    private var activeSystemLabel: String {
        isV2Active ? "Plugin System (V2)" : "Classic System (V1)"
    }

    var body: some View {
        Menu {
            // Header with status
            Text(statusText)
                .font(.headline)

            // Show active system indicator
            Label(activeSystemLabel, systemImage: isV2Active ? "2.circle" : "1.circle")
                .font(.caption)

            Divider()

            if hasToolsEnabled {
                // V2 Tools (Plugin System)
                if hasV2ToolsEnabled {
                    ForEach(groupedV2EnabledTools, id: \.category) { group in
                        Section(group.category.displayName) {
                            ForEach(group.tools, id: \.id) { tool in
                                Label(tool.name, systemImage: tool.icon)
                            }
                        }
                    }
                }

                // V1 Tools (Legacy)
                if hasV1ToolsEnabled {
                    ForEach(groupedV1EnabledTools, id: \.category) { group in
                        Section(group.category.displayName) {
                            ForEach(group.tools, id: \.id) { tool in
                                Label(tool.displayName, systemImage: tool.icon)
                            }
                        }
                    }
                }

                Divider()
                Text("Configure in Settings > Tools")
                    .font(.caption)
            } else {
                // Show reason why no tools are active
                if isV2Active && !toolPluginLoader.masterToolsEnabled {
                    Label("Master toggle is off", systemImage: "power")
                        .foregroundColor(.secondary)
                } else if !isV2Active && !settingsViewModel.settings.toolSettings.toolsEnabled {
                    Label("Master toggle is off", systemImage: "power")
                        .foregroundColor(.secondary)
                } else {
                    Label("No tools selected", systemImage: "sparkles")
                        .foregroundColor(.secondary)
                }

                Divider()
                Text("Enable tools in Settings > Tools")
                    .font(.caption)
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .accessibilityLabel(hasToolsEnabled ? "Tools enabled" : "No tools enabled")
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .iconOnly:
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(hasToolsEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 28, height: 28)
                .background(hasToolsEnabled ? AppColors.signalMercury.opacity(0.12) : Color.clear)
                .clipShape(Circle())

        case .pill:
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))

                if hasToolsEnabled {
                    Text("\(enabledToolCount)")
                        .font(AppTypography.labelSmall())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.signalMercury.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(hasToolsEnabled ? AppColors.signalMercury : AppColors.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppColors.substrateSecondary)
                    .overlay(
                        Capsule()
                            .stroke(AppColors.glassBorder, lineWidth: 1)
                    )
            )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ToolsStatusMenu(style: .iconOnly)
        ToolsStatusMenu(style: .pill)
    }
    .padding()
    .background(AppColors.substratePrimary)
}
