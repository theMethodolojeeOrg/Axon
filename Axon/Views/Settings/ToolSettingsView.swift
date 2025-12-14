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

                #if os(macOS)
                // VS Code Bridge Section
                VSCodeBridgeSection(bridgeServer: bridgeServer)
                #endif

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
            .background(AppColors.substrateSecondary)
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

// MARK: - Preview

#Preview {
    ScrollView {
        ToolSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
