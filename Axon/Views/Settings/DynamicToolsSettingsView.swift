//
//  DynamicToolsSettingsView.swift
//  Axon
//
//  Settings view for managing dynamic/custom AI tools
//

import SwiftUI

struct DynamicToolsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var configService = DynamicToolConfigurationService.shared
    @StateObject private var executionEngine = DynamicToolExecutionEngine.shared

    @State private var showingDraftPreview = false
    @State private var showingAddTool = false
    @State private var showingResetConfirmation = false
    @State private var selectedTool: DynamicToolConfig?
    @State private var testOutput: String?
    @State private var showingTestOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsInfoBanner(
                icon: "arrow.triangle.branch",
                text: "Create custom tool pipelines that chain models and APIs. Enable/disable tools, view details, and run quick tests.")

            // Current Configuration
            currentConfigSection

            // Draft Section (if available)
            if configService.hasPendingDraft {
                draftSection
            }

            // Tools by Category
            toolsListSection

            // Secrets Configuration
            secretsSection

            // Advanced Actions
            advancedSection
        }
    }


    // MARK: - Current Config Section

    private var currentConfigSection: some View {
        UnifiedSettingsSection(title: "Active Configuration") {
            if let catalog = configService.activeCatalog {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version \(catalog.version)")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Updated \(catalog.lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                let enabledCount = catalog.tools.filter { $0.enabled }.count
                                Text("\(enabledCount)/\(catalog.tools.count) Enabled")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    // Quick stats by category
                    HStack(spacing: 16) {
                        ForEach(DynamicToolCategory.allCases, id: \.self) { category in
                            let count = catalog.tools.filter { $0.category == category }.count
                            if count > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: categoryIcon(category))
                                        .font(.system(size: 12))
                                    Text("\(count)")
                                        .font(AppTypography.labelSmall())
                                }
                                .foregroundColor(categoryColor(category))
                            }
                        }
                    }
                }
            } else {
                SettingsCard(padding: 12) {
                    Text("No configuration loaded")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Draft Section

    private var draftSection: some View {
        UnifiedSettingsSection(title: "Pending Draft") {
            VStack(alignment: .leading, spacing: 12) {
                if let draft = configService.draftCatalog {
                    SettingsCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Version \(draft.version)")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("\(draft.tools.count) tools")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()

                            Button {
                                showingDraftPreview = true
                            } label: {
                                Image(systemName: "eye")
                                    .font(.system(size: 18))
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(AppColors.signalMercury)
                        }
                    }

                    // Validation issues
                    if !configService.draftIssues.isEmpty {
                        SettingsCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(AppColors.accentWarning)
                                    Text("Validation Issues")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.accentWarning)
                                }

                                ForEach(configService.draftIssues.prefix(3), id: \.description) { issue in
                                    Text("• \(issue.description)")
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            activateDraft()
                        } label: {
                            Label("Activate Draft", systemImage: "checkmark.circle")
                                .font(AppTypography.bodyMedium())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accentSuccess)

                        Button {
                            configService.discardDraft()
                            viewModel.successMessage = "Draft discarded"
                        } label: {
                            Label("Discard", systemImage: "xmark.circle")
                                .font(AppTypography.bodyMedium())
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.accentError)
                    }
                }
            }
        }
        .sheet(isPresented: $showingDraftPreview) {
            DynamicToolsDraftPreviewSheet(catalog: configService.draftCatalog)
        }
    }

    // MARK: - Tools List Section

    private var toolsListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(DynamicToolCategory.allCases, id: \.self) { category in
                let tools = configService.tools(forCategory: category)
                if !tools.isEmpty {
                    UnifiedSettingsSection(title: categoryDisplayName(category)) {
                        SettingsCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(tools) { tool in
                                    DynamicToolRow(
                                        tool: tool,
                                        onToggle: { enabled in
                                            toggleTool(tool.id, enabled: enabled)
                                        },
                                        onTap: {
                                            selectedTool = tool
                                        },
                                        onTest: {
                                            testTool(tool)
                                        }
                                    )

                                    if tool.id != tools.last?.id {
                                        Divider()
                                            .background(AppColors.divider)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Add Tool Button
            Button {
                showingAddTool = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Custom Tool")
                }
                .font(AppTypography.bodyMedium())
            }
            .buttonStyle(.bordered)
            .tint(AppColors.signalMercury)
        }
        .sheet(item: $selectedTool) { tool in
            DynamicToolDetailSheet(tool: tool)
        }
        .sheet(isPresented: $showingAddTool) {
            DynamicToolEditorSheet(mode: .create)
        }
        .alert("Test Output", isPresented: $showingTestOutput) {
            Button("OK") {
                testOutput = nil
            }
        } message: {
            Text(testOutput ?? "No output")
        }
    }

    // MARK: - Secrets Section

    private var secretsSection: some View {
        UnifiedSettingsSection(title: "Tool Secrets") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure API keys for external integrations used by dynamic tools.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                // List unique required secrets from enabled tools
                let requiredSecrets = Set(configService.enabledTools().flatMap { $0.requiredSecrets })

                if requiredSecrets.isEmpty {
                    SettingsCard(padding: 12) {
                        Text("No secrets required by enabled tools")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(requiredSecrets).sorted(), id: \.self) { secretKey in
                            SecretConfigRow(secretKey: secretKey)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        UnifiedSettingsSection(title: "Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    showingResetConfirmation = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(AppTypography.bodyMedium())
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accentError)

                Text("This will restore the bundled tool configurations that shipped with the app.")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .alert("Reset to Defaults?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will replace your current tool configuration with the bundled defaults. Your current configuration will be backed up.")
        }
    }

    // MARK: - Actions

    private func toggleTool(_ toolId: String, enabled: Bool) {
        do {
            try configService.setToolEnabled(toolId, enabled: enabled)
            viewModel.successMessage = "Tool \(enabled ? "enabled" : "disabled")"
        } catch {
            viewModel.error = error.localizedDescription
        }
    }

    private func activateDraft() {
        do {
            try configService.activateDraft()
            viewModel.successMessage = "Draft configuration activated"
        } catch {
            viewModel.error = error.localizedDescription
        }
    }

    private func resetToDefaults() {
        do {
            try configService.resetToDefaults()
            viewModel.successMessage = "Reset to bundled defaults"
        } catch {
            viewModel.error = error.localizedDescription
        }
    }

    private func testTool(_ tool: DynamicToolConfig) {
        Task {
            do {
                // Use empty inputs for test - real implementation would prompt
                let result = try await executionEngine.execute(toolId: tool.id, inputs: [:])
                testOutput = result.output
                showingTestOutput = true
            } catch {
                testOutput = "Error: \(error.localizedDescription)"
                showingTestOutput = true
            }
        }
    }

    // MARK: - Helpers

    private func categoryDisplayName(_ category: DynamicToolCategory) -> String {
        switch category {
        case .integration: return "Integrations"
        case .composite: return "Composite Tools"
        case .research: return "Research"
        case .utility: return "Utilities"
        case .custom: return "Custom Tools"
        }
    }

    private func categoryIcon(_ category: DynamicToolCategory) -> String {
        switch category {
        case .integration: return "link"
        case .composite: return "arrow.triangle.branch"
        case .research: return "magnifyingglass"
        case .utility: return "wrench"
        case .custom: return "star"
        }
    }

    private func categoryColor(_ category: DynamicToolCategory) -> Color {
        switch category {
        case .integration: return AppColors.signalMercury
        case .composite: return AppColors.signalLichen
        case .research: return AppColors.signalCopper
        case .utility: return AppColors.textSecondary
        case .custom: return AppColors.accentWarning
        }
    }
}

// MARK: - Dynamic Tool Row

struct DynamicToolRow: View {
    let tool: DynamicToolConfig
    let onToggle: (Bool) -> Void
    let onTap: () -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.system(size: 20))
                .foregroundColor(tool.enabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(tool.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)

                // Show pipeline info
                HStack(spacing: 8) {
                    Text("\(tool.pipeline.count) steps")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    if !tool.requiredSecrets.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 10))
                            Text("\(tool.requiredSecrets.count)")
                        }
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                    }
                }
            }

            Spacer()

            // Test button
            Button {
                onTest()
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
            .foregroundColor(tool.enabled ? AppColors.signalMercury : AppColors.textTertiary)
            .disabled(!tool.enabled)

            // Info button
            Button {
                onTap()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
            }
            .buttonStyle(.borderless)
            .foregroundColor(AppColors.textSecondary)

            // Toggle
            Toggle("", isOn: Binding(
                get: { tool.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(AppColors.signalMercury)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Secret Config Row

struct SecretConfigRow: View {
    let secretKey: String
    @State private var isConfigured: Bool = false
    @State private var showingSecretInput = false
    @State private var secretValue: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatSecretName(secretKey))
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                Text(secretKey)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            if isConfigured {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Configured")
                }
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.accentSuccess)
            } else {
                Button("Configure") {
                    showingSecretInput = true
                }
                .font(AppTypography.labelSmall())
                .buttonStyle(.bordered)
                .tint(AppColors.signalMercury)
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
        .onAppear {
            checkIfConfigured()
        }
        .alert("Configure \(formatSecretName(secretKey))", isPresented: $showingSecretInput) {
            SecureField("API Key", text: $secretValue)
            Button("Cancel", role: .cancel) {
                secretValue = ""
            }
            Button("Save") {
                saveSecret()
            }
        } message: {
            Text("Enter the API key for \(secretKey)")
        }
    }

    private func formatSecretName(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "api key", with: "API Key")
            .capitalized
    }

    private func checkIfConfigured() {
        if let _ = try? SecureVault.shared.retrieveString(forKey: "custom_secret_\(secretKey)") {
            isConfigured = true
        } else {
            isConfigured = false
        }
    }

    private func saveSecret() {
        guard !secretValue.isEmpty else { return }
        do {
            try SecureVault.shared.store(secretValue, forKey: "custom_secret_\(secretKey)")
            isConfigured = true
            secretValue = ""
        } catch {
            print("Failed to save secret: \(error)")
        }
    }
}

// MARK: - Draft Preview Sheet

struct DynamicToolsDraftPreviewSheet: View {
    let catalog: DynamicToolCatalog?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let catalog = catalog {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Version \(catalog.version)")
                                .font(AppTypography.titleMedium())
                            Spacer()
                            Text(catalog.lastUpdated.formatted())
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding()

                        ForEach(catalog.tools) { tool in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: tool.icon)
                                    Text(tool.name)
                                        .font(AppTypography.titleSmall())
                                    Spacer()
                                    Text(tool.enabled ? "Enabled" : "Disabled")
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(tool.enabled ? AppColors.accentSuccess : AppColors.textTertiary)
                                }

                                Text(tool.description)
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)

                                Text("\(tool.pipeline.count) pipeline steps")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                            .padding(12)
                            .background(AppColors.substrateSecondary)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.glassBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding()
                } else {
                    Text("No draft available")
                        .foregroundColor(AppColors.textSecondary)
                        .padding()
                }
            }
            .background(AppColors.substratePrimary)
            .navigationTitle("Draft Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Tool Detail Sheet

struct DynamicToolDetailSheet: View {
    let tool: DynamicToolConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack {
                        Image(systemName: tool.icon)
                            .font(.system(size: 32))
                            .foregroundColor(AppColors.signalMercury)

                        VStack(alignment: .leading) {
                            Text(tool.name)
                                .font(AppTypography.titleLarge())
                            Text(tool.category.rawValue.capitalized)
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    Text(tool.description)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)

                    Divider()

                    // Parameters
                    if !tool.parameters.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Parameters")
                                .font(AppTypography.titleSmall())

                            ForEach(tool.parameters.sorted(by: { $0.key < $1.key }), id: \.key) { key, param in
                                HStack {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(key)
                                                .font(AppTypography.bodyMedium(.medium))
                                            if param.required {
                                                Text("*")
                                                    .foregroundColor(AppColors.accentError)
                                            }
                                        }
                                        Text(param.description)
                                            .font(AppTypography.bodySmall())
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                    Spacer()
                                    Text(param.type.rawValue)
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                .padding(12)
                                .background(AppColors.substrateSecondary)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(AppColors.glassBorder, lineWidth: 1)
                                )
                            }
                        }
                    }

                    // Pipeline
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pipeline (\(tool.pipeline.count) steps)")
                            .font(AppTypography.titleSmall())

                        ForEach(Array(tool.pipeline.enumerated()), id: \.offset) { index, step in
                            HStack {
                                Text("\(index + 1)")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(AppColors.signalMercury)
                                    .clipShape(Circle())

                                VStack(alignment: .leading) {
                                    Text(step.id)
                                        .font(AppTypography.bodyMedium(.medium))
                                    Text(step.type.rawValue)
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    // Required Secrets
                    if !tool.requiredSecrets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Required Secrets")
                                .font(AppTypography.titleSmall())

                            ForEach(tool.requiredSecrets, id: \.self) { secret in
                                HStack {
                                    Image(systemName: "key.fill")
                                    Text(secret)
                                }
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.substratePrimary)
            .navigationTitle("Tool Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Tool Editor Sheet (Placeholder)

struct DynamicToolEditorSheet: View {
    enum Mode {
        case create
        case edit(DynamicToolConfig)
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.signalMercury)

                Text("Tool Editor Coming Soon")
                    .font(AppTypography.titleLarge())

                Text("You'll be able to create and edit custom tools with a visual pipeline builder.")
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("For now, you can manually edit the tools-active.json file in ~/Library/Application Support/Axon/")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .background(AppColors.substratePrimary)
            .navigationTitle(mode.isCreate ? "Create Tool" : "Edit Tool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension DynamicToolEditorSheet.Mode {
    var isCreate: Bool {
        if case .create = self { return true }
        return false
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        DynamicToolsSettingsView(viewModel: SettingsViewModel.shared)
            .padding()
    }
    .background(AppColors.substratePrimary)
}
