//
//  ToolSettingsViewV2.swift
//  Axon
//
//  Browse, enable/disable, and manage V2 plugin-based tools.
//

import SwiftUI

// MARK: - Tools V2 Settings View

struct ToolSettingsViewV2: View {
    @ObservedObject var viewModel: SettingsViewModel
    @StateObject private var pluginLoader = ToolPluginLoader.shared
    @StateObject private var toolsToggle = ToolsV2Toggle.shared

    @State private var searchQuery = ""
    @State private var selectedCategory: ToolCategoryV2?
    @State private var showingToolDetail: LoadedTool?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // V1/V2 Toggle Section
            SettingsSection(title: "Tool System") {
                ToolSystemToggleCard(toolsToggle: toolsToggle)
            }

            if toolsToggle.isV2Active {
                // Master Tools Toggle
                MasterToolsToggleCard(
                    isEnabled: $pluginLoader.masterToolsEnabled,
                    enabledCount: pluginLoader.stats.enabledCount,
                    totalCount: pluginLoader.stats.totalCount
                )

                if pluginLoader.masterToolsEnabled {
                    // V2 Content
                    v2ContentView
                } else {
                    // Disabled hint
                    toolsDisabledHintView
                }
            } else {
                // V1 hint
                v1HintView
            }
        }
        .task {
            if pluginLoader.loadedTools.isEmpty {
                isLoading = true
                await pluginLoader.loadAllTools()
                isLoading = false
            }
        }
        .sheet(item: $showingToolDetail) { tool in
            ToolDetailSheet(tool: tool, onToggle: { enabled in
                pluginLoader.setToolEnabled(tool.id, enabled: enabled)
            })
        }
    }

    // MARK: - V2 Content

    private var v2ContentView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Stats banner
            ToolStatsBanner(stats: pluginLoader.stats)

            // Search bar
            SearchBar(text: $searchQuery, placeholder: "Search tools...")

            // Category filter
            CategoryFilterBar(
                selectedCategory: $selectedCategory,
                categories: Array(pluginLoader.toolsByCategory.keys).sorted { $0.rawValue < $1.rawValue }
            )

            // Tools list
            if isLoading {
                LoadingToolsView()
            } else if filteredTools.isEmpty {
                EmptyToolsView(searchQuery: searchQuery)
            } else {
                ToolsListView(
                    toolsByCategory: groupedFilteredTools,
                    onToggle: { tool, enabled in
                        pluginLoader.setToolEnabled(tool.id, enabled: enabled)
                    },
                    onSelect: { tool in
                        showingToolDetail = tool
                    },
                    onCategoryToggle: { category, enabled in
                        pluginLoader.setCategoryEnabled(category, enabled: enabled)
                    }
                )
            }

            // Refresh button
            HStack {
                Spacer()
                Button {
                    Task {
                        isLoading = true
                        await pluginLoader.reloadTools()
                        isLoading = false
                    }
                } label: {
                    Label("Reload Tools", systemImage: "arrow.clockwise")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.signalMercury)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    // MARK: - Tools Disabled Hint View

    private var toolsDisabledHintView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text("Tools Disabled")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            Text("Enable the master toggle above to allow AI to use tools during conversations.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }

    // MARK: - V1 Hint View

    private var v1HintView: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text("Classic Tool System Active")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            Text("Enable the Plugin-Based (V2) system above to manage tools via the new plugin architecture.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            Text("V2 features:")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                ToolsV2FeatureRow(icon: "folder.badge.gearshape", text: "JSON-based tool definitions")
                ToolsV2FeatureRow(icon: "icloud", text: "Import tools from iCloud")
                ToolsV2FeatureRow(icon: "square.and.arrow.down", text: "Community tool sharing")
                ToolsV2FeatureRow(icon: "arrow.clockwise", text: "Hot-reload support")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }

    // MARK: - Filtered Tools

    private var filteredTools: [LoadedTool] {
        var tools = pluginLoader.loadedTools

        // Filter by category
        if let category = selectedCategory {
            tools = tools.filter { $0.category == category }
        }

        // Filter by search
        if !searchQuery.isEmpty {
            tools = pluginLoader.searchTools(query: searchQuery)
            if let category = selectedCategory {
                tools = tools.filter { $0.category == category }
            }
        }

        return tools
    }

    private var groupedFilteredTools: [ToolCategoryV2: [LoadedTool]] {
        Dictionary(grouping: filteredTools, by: { $0.category })
    }
}

// MARK: - Tool System Toggle Card

private struct ToolSystemToggleCard: View {
    @ObservedObject var toolsToggle: ToolsV2Toggle

    var body: some View {
        HStack(spacing: 16) {
            // V1 option
            ToolSystemOption(
                version: .v1,
                isSelected: toolsToggle.isV1Active,
                onSelect: { toolsToggle.switchTo(.v1) }
            )

            // V2 option
            ToolSystemOption(
                version: .v2,
                isSelected: toolsToggle.isV2Active,
                onSelect: { toolsToggle.switchTo(.v2) }
            )
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
    }
}

private struct ToolSystemOption: View {
    let version: ToolSystemVersion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: version.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)

                Text(version.displayName)
                    .font(AppTypography.labelMedium())
                    .foregroundColor(isSelected ? AppColors.textPrimary : AppColors.textSecondary)

                Text(version.versionDescription)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? AppColors.signalMercury : AppColors.glassBorder, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Master Tools Toggle Card

private struct MasterToolsToggleCard: View {
    @Binding var isEnabled: Bool
    let enabledCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .tint(AppColors.signalMercury)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text("Enable AI Tools")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Allow AI to use tools during conversations")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            if isEnabled {
                Text("\(enabledCount)/\(totalCount) active")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Stats Banner

private struct ToolStatsBanner: View {
    let stats: ToolLoaderStats

    var body: some View {
        HStack(spacing: 24) {
            StatItem(value: "\(stats.totalCount)", label: "Total")
            StatItem(value: "\(stats.enabledCount)", label: "Enabled")
            StatItem(value: "\(stats.bundledCount)", label: "Built-in")
            if stats.customCount > 0 {
                StatItem(value: "\(stats.customCount)", label: "Custom")
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

private struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.signalMercury)
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Search Bar

private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColors.textTertiary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .foregroundColor(AppColors.textPrimary)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Category Filter Bar

private struct CategoryFilterBar: View {
    @Binding var selectedCategory: ToolCategoryV2?
    let categories: [ToolCategoryV2]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: "All",
                    icon: "square.grid.2x2",
                    isSelected: selectedCategory == nil,
                    onTap: { selectedCategory = nil }
                )

                ForEach(categories, id: \.self) { category in
                    CategoryChip(
                        title: category.displayName,
                        icon: category.sfSymbol,
                        isSelected: selectedCategory == category,
                        onTap: { selectedCategory = category }
                    )
                }
            }
        }
    }
}

private struct CategoryChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(AppTypography.labelSmall())
            }
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? AppColors.signalMercury : AppColors.substrateSecondary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tools List View

private struct ToolsListView: View {
    let toolsByCategory: [ToolCategoryV2: [LoadedTool]]
    let onToggle: (LoadedTool, Bool) -> Void
    let onSelect: (LoadedTool) -> Void
    let onCategoryToggle: (ToolCategoryV2, Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ForEach(toolsByCategory.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { category in
                if let tools = toolsByCategory[category], !tools.isEmpty {
                    ToolCategorySection(
                        category: category,
                        tools: tools,
                        onToggle: onToggle,
                        onSelect: onSelect,
                        onCategoryToggle: onCategoryToggle
                    )
                }
            }
        }
    }
}

// MARK: - Category Toggle State

enum CategoryToggleStateV2 {
    case allEnabled
    case partiallyEnabled
    case allDisabled
}

// MARK: - Category Toggle Button

private struct CategoryToggleButtonV2: View {
    let state: CategoryToggleStateV2
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

private struct ToolCategorySection: View {
    let category: ToolCategoryV2
    let tools: [LoadedTool]
    let onToggle: (LoadedTool, Bool) -> Void
    let onSelect: (LoadedTool) -> Void
    let onCategoryToggle: (ToolCategoryV2, Bool) -> Void

    @State private var isExpanded = true

    private var categoryState: CategoryToggleStateV2 {
        let enabledCount = tools.filter { $0.isEnabled }.count
        if enabledCount == tools.count {
            return .allEnabled
        } else if enabledCount > 0 {
            return .partiallyEnabled
        } else {
            return .allDisabled
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // Category toggle (3-state)
                    CategoryToggleButtonV2(
                        state: categoryState,
                        onToggle: {
                            let shouldEnable = categoryState != .allEnabled
                            onCategoryToggle(category, shouldEnable)
                        }
                    )

                    Image(systemName: category.sfSymbol)
                        .font(.system(size: 18))
                        .foregroundColor(categoryState != .allDisabled ? AppColors.signalMercury : AppColors.textTertiary)
                        .frame(width: 24)

                    Text(category.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text("\(tools.filter { $0.isEnabled }.count)/\(tools.count)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Tools
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(tools) { tool in
                        ToolRowV2(
                            tool: tool,
                            onToggle: { enabled in onToggle(tool, enabled) },
                            onSelect: { onSelect(tool) }
                        )

                        if tool.id != tools.last?.id {
                            Divider()
                                .background(AppColors.divider)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(AppColors.substrateTertiary.opacity(0.5))
                .cornerRadius(8)
                .padding(.top, 4)
            }
        }
    }
}

private struct ToolRowV2: View {
    let tool: LoadedTool
    let onToggle: (Bool) -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { tool.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            Image(systemName: tool.icon)
                .font(.system(size: 18))
                .foregroundColor(tool.isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if tool.manifest.tool.effectiveRequiresApproval {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.accentWarning)
                    }

                    SourceBadge(source: tool.source)
                }

                Text(tool.description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onSelect) {
                Image(systemName: "info.circle")
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

private struct SourceBadge: View {
    let source: ToolSource

    var body: some View {
        if source != .bundled {
            Text(source.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(badgeColor)
                .cornerRadius(3)
        }
    }

    private var badgeColor: Color {
        switch source {
        case .bundled: return AppColors.signalMercury
        case .iCloud: return AppColors.signalLichen
        case .imported: return AppColors.signalCopper
        case .custom: return AppColors.accentWarning
        }
    }
}

// MARK: - Loading & Empty States

private struct LoadingToolsView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
            Text("Loading tools...")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
}

private struct EmptyToolsView: View {
    let searchQuery: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: searchQuery.isEmpty ? "puzzlepiece.extension" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(AppColors.textTertiary)

            Text(searchQuery.isEmpty ? "No tools found" : "No results for \"\(searchQuery)\"")
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textSecondary)

            if !searchQuery.isEmpty {
                Text("Try a different search term")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }
}

// MARK: - V2 Feature Row

private struct ToolsV2FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 20)

            Text(text)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Tool Detail Sheet

private struct ToolDetailSheet: View {
    let tool: LoadedTool
    let onToggle: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack(spacing: 16) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 32))
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 48, height: 48)
                            .background(AppColors.signalMercury.opacity(0.1))
                            .cornerRadius(12)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(tool.name)
                                .font(AppTypography.titleMedium())
                                .foregroundColor(AppColors.textPrimary)

                            HStack(spacing: 8) {
                                Text(tool.category.displayName)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)

                                SourceBadge(source: tool.source)
                            }
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { tool.isEnabled },
                            set: { onToggle($0) }
                        ))
                        .toggleStyle(.switch)
                        .tint(AppColors.signalMercury)
                        .labelsHidden()
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        Text(tool.description)
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)
                    }

                    // Tags
                    if let tags = tool.manifest.tool.tags, !tags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            ToolSettingsFlowLayout(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppColors.substrateTertiary)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    // Execution
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Execution")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        HStack(spacing: 8) {
                            Image(systemName: executionIcon)
                                .foregroundColor(AppColors.signalMercury)
                            Text(executionDescription)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }

                    // Approval requirement
                    if tool.manifest.tool.effectiveRequiresApproval {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(AppColors.accentWarning)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Requires Approval")
                                    .font(AppTypography.bodySmall(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("This tool will ask for confirmation before executing")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .padding()
                        .background(AppColors.accentWarning.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Manifest path (for debugging)
                    #if DEBUG
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Debug Info")
                            .font(AppTypography.labelMedium())
                            .foregroundColor(AppColors.textSecondary)

                        Text("ID: \(tool.id)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)

                        Text("Path: \(tool.manifestPath.path)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(2)
                    }
                    .padding()
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(8)
                    #endif
                }
                .padding()
            }
            .background(AppColors.substratePrimary)
            .navigationTitle("Tool Details")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var executionIcon: String {
        switch tool.manifest.execution.type {
        case .internalHandler: return "cpu"
        case .pipeline: return "arrow.triangle.branch"
        case .providerNative: return "cloud"
        case .urlScheme: return "link"
        case .shortcut: return "square.on.square"
        case .bridge: return "personalhotspot"
        }
    }

    private var executionDescription: String {
        switch tool.manifest.execution.type {
        case .internalHandler: return "Internal handler: \(tool.manifest.execution.handler ?? "unknown")"
        case .pipeline: return "Pipeline execution"
        case .providerNative: return "Provider: \(tool.manifest.execution.provider ?? "unknown")"
        case .urlScheme: return "URL scheme"
        case .shortcut: return "Shortcut: \(tool.manifest.execution.shortcutName ?? "unknown")"
        case .bridge: return "Bridge: \(tool.manifest.execution.bridgeMethod ?? "unknown")"
        }
    }
}

// Flow layout for tags in tool settings V2
private struct ToolSettingsFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let maxX = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxX && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        ToolSettingsViewV2(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}

