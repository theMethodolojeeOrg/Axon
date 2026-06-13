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

                PositiveIntegerSettingRow(
                    title: "Max Tool Calls Per Turn",
                    value: viewModel.settings.toolSettings.maxToolCallsPerTurn,
                    description: "Maximum number of tool calls per response",
                    accessibilityIdentifier: "maxToolCallsPerTurnInput"
                ) { newValue in
                    Task {
                        var updated = viewModel.settings.toolSettings
                        updated.maxToolCallsPerTurn = newValue
                        await viewModel.updateSetting(\.toolSettings, updated)
                    }
                }

                Divider()
                    .background(AppColors.divider)

                PositiveIntegerSettingRow(
                    title: "Tool Timeout",
                    value: viewModel.settings.toolSettings.toolTimeout,
                    unitSuffix: "s",
                    description: "How long to wait for tool execution before timing out",
                    accessibilityIdentifier: "toolTimeoutInput"
                ) { newValue in
                    Task {
                        var updated = viewModel.settings.toolSettings
                        updated.toolTimeout = newValue
                        await viewModel.updateSetting(\.toolSettings, updated)
                    }
                }

                Divider()
                    .background(AppColors.divider)

                // Multi-File Artifact Prompting
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Multi-File Artifacts")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Guide assistants to emit `language:relative/path.ext` fenced blocks for bundle-style HTML/CSS/JS artifacts.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { viewModel.settings.toolSettings.multiFileArtifactsEnabled },
                            set: { newValue in
                                Task {
                                    var updated = viewModel.settings.toolSettings
                                    updated.multiFileArtifactsEnabled = newValue
                                    await viewModel.updateSetting(\.toolSettings, updated)
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(AppColors.signalMercury)
                    }
                }
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
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

// MARK: - Positive Integer Setting Row

private struct PositiveIntegerSettingRow: View {
    let title: String
    let value: Int
    let unitSuffix: String?
    let description: String
    let accessibilityIdentifier: String
    let onValueChange: (Int) -> Void

    @State private var text = ""
    @State private var validationMessage: String?

    init(
        title: String,
        value: Int,
        unitSuffix: String? = nil,
        description: String,
        accessibilityIdentifier: String,
        onValueChange: @escaping (Int) -> Void
    ) {
        self.title = title
        self.value = value
        self.unitSuffix = unitSuffix
        self.description = description
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onValueChange = onValueChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                HStack(spacing: 6) {
                    TextField("1", text: $text)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(validationMessage == nil ? AppColors.signalMercury : AppColors.accentError)
                        .multilineTextAlignment(.trailing)
                        .positiveIntegerKeyboard()
                        .textFieldStyle(.plain)
                        .frame(width: 96)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppSurfaces.color(.inputBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(validationMessage == nil ? AppColors.divider : AppColors.accentError, lineWidth: 1)
                        )
                        .cornerRadius(6)
                        .accessibilityIdentifier(accessibilityIdentifier)

                    if let unitSuffix {
                        Text(unitSuffix)
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }

            Text(description)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

            if let validationMessage {
                Text(validationMessage)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.accentError)
            }
        }
        .onAppear {
            text = String(value)
            validateAndSave(text)
        }
        .onChange(of: value) { newValue in
            let newText = String(newValue)
            if validationMessage == nil && text != newText {
                text = newText
            }
        }
        .onChange(of: text) { newText in
            validateAndSave(newText)
        }
    }

    private func validateAndSave(_ candidate: String) {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Enter a positive whole number."
            return
        }

        guard trimmed.allSatisfy(\.isNumber) else {
            validationMessage = "Use digits only."
            return
        }

        guard let parsed = Int(trimmed) else {
            validationMessage = "Number is too large."
            return
        }

        guard parsed >= 1 else {
            validationMessage = "Value must be at least 1."
            return
        }

        validationMessage = nil
        if parsed != value {
            onValueChange(parsed)
        }
    }
}

private extension View {
    @ViewBuilder
    func positiveIntegerKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad)
        #else
        self
        #endif
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
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        AutomationSettingsView(viewModel: SettingsViewModel.shared)
    }
}
