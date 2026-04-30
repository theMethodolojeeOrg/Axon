//
//  ToolSettingsView.swift
//  Axon
//
//  AI Tools configuration - enable web search, code execution, and more
//

import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ToolSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var bridgeServer = BridgeServer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Master Toggle
            SettingsSection(title: "AI Tools") {
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.settings.toolSettings.toolsEnabled },
                        set: { newValue in
                            Task {
                                var updated = viewModel.settings.toolSettings
                                updated.toolsEnabled = newValue
                                await viewModel.updateSetting(\.toolSettings, updated)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppColors.signalMercury)
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable AI Tools")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Allow AI to use external tools like web search and code execution")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }

            if viewModel.settings.toolSettings.toolsEnabled {
                // Provider Tools Section (Gemini + OpenAI in accordions)
                SettingsSection(title: "Provider Tools") {
                    VStack(spacing: 12) {
                        // Gemini Tools Accordion
                        ToolCategoryAccordion(
                            category: .geminiTools,
                            tools: ToolId.tools(for: .geminiTools),
                            toolSettings: viewModel.settings.toolSettings,
                            onCategoryToggle: { enabled in
                                Task {
                                    var updated = viewModel.settings.toolSettings
                                    if enabled {
                                        updated.enableCategory(.geminiTools)
                                    } else {
                                        updated.disableCategory(.geminiTools)
                                    }
                                    await viewModel.updateSetting(\.toolSettings, updated)
                                }
                            },
                            onToolToggle: { tool, enabled in
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

                        // OpenAI Tools Accordion
                        ToolCategoryAccordion(
                            category: .openaiTools,
                            tools: ToolId.tools(for: .openaiTools),
                            toolSettings: viewModel.settings.toolSettings,
                            onCategoryToggle: { enabled in
                                Task {
                                    var updated = viewModel.settings.toolSettings
                                    if enabled {
                                        updated.enableCategory(.openaiTools)
                                    } else {
                                        updated.disableCategory(.openaiTools)
                                    }
                                    await viewModel.updateSetting(\.toolSettings, updated)
                                }
                            },
                            onToolToggle: { tool, enabled in
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

                    // API key requirement notice
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 12))
                        Text("Provider tools require their respective API keys in Settings > API Keys")
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                }


                // Built-in Tools Section (organized by category accordions)
                SettingsSection(title: "Built-in Tools") {
                    VStack(spacing: 12) {
                        // Get all internal tool categories (excluding geminiTools and openaiTools since those are separate)
                        let internalCategories = ToolCategory.allCases.filter { category in
                            category != .geminiTools && category != .openaiTools && !ToolId.tools(for: category).isEmpty
                        }

                        ForEach(internalCategories) { category in
                            ToolCategoryAccordion(
                                category: category,
                                tools: ToolId.tools(for: category),
                                toolSettings: viewModel.settings.toolSettings,
                                onCategoryToggle: { enabled in
                                    Task {
                                        var updated = viewModel.settings.toolSettings
                                        if enabled {
                                            updated.enableCategory(category)
                                        } else {
                                            updated.disableCategory(category)
                                        }
                                        await viewModel.updateSetting(\.toolSettings, updated)
                                    }
                                },
                                onToolToggle: { tool, enabled in
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
                }

                #if os(macOS)
                // VS Code Bridge Section
                VSCodeBridgeSection(bridgeServer: bridgeServer)
                #endif

            }

            // Experimental Section - Only show if experimental features enabled
            if viewModel.settings.toolSettings.experimentalFeaturesEnabled {
                SettingsSection(title: "Experimental") {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Toggle("", isOn: Binding(
                                get: { viewModel.settings.toolSettings.mediaProxyEnabled },
                                set: { newValue in
                                    Task {
                                        var updated = viewModel.settings.toolSettings
                                        updated.mediaProxyEnabled = newValue
                                        await viewModel.updateSetting(\.toolSettings, updated)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .tint(AppColors.signalMercury)
                            .labelsHidden()

                            VStack(alignment: .leading, spacing: 2) {
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

                            Spacer()
                        }

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
                    .background(AppSurfaces.color(.cardBackground))
                    .cornerRadius(8)
                }
            }

            // Experimental Features Toggle (always visible)
            SettingsSection(title: "Advanced") {
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { viewModel.settings.toolSettings.experimentalFeaturesEnabled },
                        set: { newValue in
                            Task {
                                var updated = viewModel.settings.toolSettings
                                updated.experimentalFeaturesEnabled = newValue
                                await viewModel.updateSetting(\.toolSettings, updated)
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .tint(AppColors.signalMercury)
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Experimental Features")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Enable beta features that are still in development")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
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
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            Image(systemName: tool.icon)
                .font(.system(size: 20))
                .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.displayName)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(tool.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
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
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
}

// MARK: - VS Code Bridge Section

#if os(macOS)
struct VSCodeBridgeSection: View {
    @ObservedObject var bridgeServer: BridgeServer
    @State private var showingExportSuccess = false
    @State private var exportError: String?

    var body: some View {
        SettingsSection(title: "VS Code Bridge") {
            VStack(spacing: 16) {
                // Status Row
                HStack(spacing: 12) {
                    Image(systemName: bridgeServer.isConnected ? "personalhotspot" : "personalhotspot.slash")
                        .font(.system(size: 24))
                        .foregroundColor(bridgeServer.isConnected ? AppColors.signalLichen : AppColors.textTertiary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text(statusDescription)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Start/Stop Button
                    Button {
                        Task {
                            if bridgeServer.isRunning {
                                await bridgeServer.stop()
                            } else {
                                await bridgeServer.start()
                            }
                        }
                    } label: {
                        Text(bridgeServer.isRunning ? "Stop" : "Start")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(bridgeServer.isRunning ? AppColors.accentWarning : AppColors.signalMercury)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                    .background(AppColors.divider)

                // Download Extension Button
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("VS Code Extension")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Download and install in VS Code to connect")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Button {
                            exportVSIX()
                        } label: {
                            Text("Download")
                                .font(AppTypography.bodySmall(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }
                        .buttonStyle(.bordered)
                    }

                    if showingExportSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.signalLichen)
                            Text("Extension saved! Install via VS Code → Extensions → Install from VSIX")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalLichen)
                        }
                        .transition(.opacity)
                    }

                    if let error = exportError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.accentWarning)
                            Text(error)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentWarning)
                        }
                        .transition(.opacity)
                    }
                }

                Divider()
                    .background(AppColors.divider)

                // Setup Instructions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Setup Instructions")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        instructionRow(number: "1", text: "Download the extension above")
                        instructionRow(number: "2", text: "In VS Code: Cmd+Shift+P → \"Install from VSIX\"")
                        instructionRow(number: "3", text: "Click \"Start\" above to begin the bridge server")
                        instructionRow(number: "4", text: "VS Code will auto-connect when the extension loads")
                    }
                }
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
    }

    private var statusTitle: String {
        if bridgeServer.isConnected, let session = bridgeServer.connectedSession {
            return "Connected to \(session.workspaceName)"
        } else if bridgeServer.isRunning {
            return "Waiting for VS Code..."
        } else {
            return "Bridge Disabled"
        }
    }

    private var statusDescription: String {
        if bridgeServer.isConnected {
            return "AI can read/write files and run commands"
        } else if bridgeServer.isRunning {
            return "Listening on port 8081"
        } else {
            return "Start the bridge to enable VS Code integration"
        }
    }

    @ViewBuilder
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 16)

            Text(text)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private func exportVSIX() {
        // Reset states
        showingExportSuccess = false
        exportError = nil

        // Find the bundled VSIX
        guard let vsixURL = Bundle.main.url(forResource: "axon-bridge-0.1.0", withExtension: "vsix") else {
            exportError = "Extension not found in app bundle"
            return
        }

        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.title = "Save VS Code Extension"
        savePanel.nameFieldStringValue = "axon-bridge-0.1.0.vsix"
        savePanel.allowedContentTypes = [.item]
        savePanel.canCreateDirectories = true

        // Default to Downloads folder
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloads
        }

        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else {
                return
            }

            do {
                // Remove existing file if present
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                // Copy the VSIX
                try FileManager.default.copyItem(at: vsixURL, to: destinationURL)

                DispatchQueue.main.async {
                    withAnimation {
                        showingExportSuccess = true
                    }

                    // Hide success message after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            showingExportSuccess = false
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    exportError = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}
#endif

// MARK: - Tool Category Accordion

/// 3-state toggle state for category headers
enum CategoryToggleState {
    case allEnabled
    case partiallyEnabled
    case allDisabled
}

/// Accordion component for organizing tools by category
struct ToolCategoryAccordion: View {
    let category: ToolCategory
    let tools: [ToolId]
    let toolSettings: ToolSettings
    let onCategoryToggle: (Bool) -> Void
    let onToolToggle: (ToolId, Bool) -> Void

    @State private var isExpanded = false

    private var categoryState: CategoryToggleState {
        if toolSettings.isCategoryFullyEnabled(category) {
            return .allEnabled
        } else if toolSettings.isCategoryPartiallyEnabled(category) {
            return .partiallyEnabled
        } else {
            return .allDisabled
        }
    }

    private var enabledCount: Int {
        toolSettings.enabledCountForCategory(category)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Accordion Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Category toggle (3-state)
                    CategoryToggleButton(
                        state: categoryState,
                        onToggle: {
                            let shouldEnable = categoryState != .allEnabled
                            onCategoryToggle(shouldEnable)
                        }
                    )

                    // Category icon
                    Image(systemName: category.icon)
                        .font(.system(size: 20))
                        .foregroundColor(categoryState != .allDisabled ? AppColors.signalMercury : AppColors.textTertiary)
                        .frame(width: 28)

                    // Category info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(category.displayName)
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            // Show enabled count
                            Text("\(enabledCount)/\(tools.count)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        Text(category.description)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Expanded tool list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(tools) { tool in
                        ToolToggleRow(
                            tool: tool,
                            isEnabled: toolSettings.isToolEnabled(tool),
                            onToggle: { enabled in onToolToggle(tool, enabled) }
                        )
                        .padding(.horizontal)

                        if tool != tools.last {
                            Divider()
                                .background(AppColors.divider)
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(AppSurfaces.color(.controlMutedBackground))
                .cornerRadius(8)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// 3-state toggle button for category headers
struct CategoryToggleButton: View {
    let state: CategoryToggleState
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .frame(width: 24, height: 24)

                if state != .allDisabled {
                    Image(systemName: state == .allEnabled ? "checkmark" : "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch state {
        case .allEnabled:
            return AppColors.signalLichen
        case .partiallyEnabled:
            return AppColors.signalCopper
        case .allDisabled:
            return AppColors.textDisabled.opacity(0.3)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ToolSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppSurfaces.color(.contentBackground))
}
