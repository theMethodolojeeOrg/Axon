//
//  ToolsSection.swift
//  Axon
//
//  Tools section for ChatInfoSettingsView
//

import SwiftUI

struct ToolsSection: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    
    @Binding var localEnabledTools: Set<String>
    
    let onToggleTool: (ToolId, Bool) -> Void
    
    #if os(macOS)
    @ObservedObject var bridgeServer = BridgeServer.shared
    #else
    @ObservedObject var bridgeManager = BridgeConnectionManager.shared
    #endif
    
    var body: some View {
        ChatInfoSection(title: "Tools") {
            VStack(spacing: 16) {
                // Execution Mode Toggle
                executionModeRow
                
                // Gemini Tools
                ChatInfoToolCategorySection(
                    title: "Google (Gemini)",
                    icon: "globe",
                    tools: ToolId.tools(for: .gemini),
                    enabledTools: localEnabledTools,
                    onToggle: { tool, enabled in onToggleTool(tool, enabled) }
                )
                
                // OpenAI Tools
                ChatInfoToolCategorySection(
                    title: "OpenAI",
                    icon: "cpu",
                    tools: ToolId.tools(for: .openai),
                    enabledTools: localEnabledTools,
                    onToggle: { tool, enabled in onToggleTool(tool, enabled) }
                )
                
                // Internal Tools (grouped by category)
                let internalCategories = ToolCategory.allCases.filter { category in
                    category != .geminiTools && category != .openaiTools && !ToolId.tools(for: category).isEmpty
                }
                
                ForEach(internalCategories) { category in
                    ChatInfoToolCategorySection(
                        title: category.displayName,
                        icon: category.icon,
                        tools: ToolId.tools(for: category),
                        enabledTools: localEnabledTools,
                        onToggle: { tool, enabled in onToggleTool(tool, enabled) }
                    )
                }
                
                // VS Code Bridge status
                Divider()
                    .padding(.vertical, 4)
                
                #if os(macOS)
                macOSBridgeStatus
                #endif
            }
        }
    }
    
    // MARK: - Execution Mode Row
    
    private var executionModeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: settingsViewModel.settings.toolSettings.executionMode.icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Execution Mode")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                
                Text(settingsViewModel.settings.toolSettings.executionMode.description)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
            
            Spacer()
            
            // Segmented picker
            Picker("", selection: Binding(
                get: { settingsViewModel.settings.toolSettings.executionMode },
                set: { newMode in
                    Task {
                        var updated = settingsViewModel.settings.toolSettings
                        updated.executionMode = newMode
                        await settingsViewModel.updateSetting(\.toolSettings, updated)
                    }
                }
            )) {
                ForEach(ToolExecutionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
    
    // MARK: - macOS Bridge Status
    
    #if os(macOS)
    private var macOSBridgeStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: bridgeServer.isConnected ? "personalhotspot" : "personalhotspot.slash")
                .font(.system(size: 16))
                .foregroundColor(bridgeServer.isConnected ? AppColors.signalLichen : AppColors.textTertiary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("VS Code Bridge")
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                
                if let session = bridgeServer.connectedSession {
                    Text(session.workspaceName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalLichen)
                } else if bridgeServer.isRunning {
                    Text("Waiting for connection...")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                } else {
                    Text("Not running")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            
            Spacer()
            
            // Connection status indicator
            Circle()
                .fill(bridgeServer.isConnected ? AppColors.signalLichen : (bridgeServer.isRunning ? AppColors.accentWarning : AppColors.textTertiary))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
    #endif
}

#Preview {
    ToolsSection(
        settingsViewModel: SettingsViewModel(),
        localEnabledTools: .constant(Set<String>()),
        onToggleTool: { _, _ in }
    )
    .padding()
    .background(AppSurfaces.color(.contentBackground))
}
