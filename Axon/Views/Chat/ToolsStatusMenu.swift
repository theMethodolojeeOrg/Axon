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

    private var hasToolsEnabled: Bool {
        settingsViewModel.settings.toolSettings.toolsEnabled &&
        !settingsViewModel.settings.toolSettings.enabledToolIds.isEmpty
    }

    private var enabledToolCount: Int {
        settingsViewModel.settings.toolSettings.enabledToolIds.count
    }

    var body: some View {
        Menu {
            if hasToolsEnabled {
                Text("\(enabledToolCount) tool\(enabledToolCount == 1 ? "" : "s") enabled")
                ForEach(settingsViewModel.settings.toolSettings.enabledTools, id: \.id) { tool in
                    Label(tool.displayName, systemImage: tool.icon)
                }
                Divider()
                Text("Configure in Settings > Tools")
                    .font(.caption)
            } else {
                Text("No tools enabled")
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
