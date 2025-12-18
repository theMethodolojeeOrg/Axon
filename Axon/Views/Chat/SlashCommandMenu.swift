//
//  SlashCommandMenu.swift
//  Axon
//
//  Autocomplete menu for slash commands that appears above the input bar.
//  Shows command suggestions and tool submenu when typing /tool.
//

import SwiftUI

// MARK: - Slash Command Menu

struct SlashCommandMenu: View {
    let menuState: SlashMenuState
    let commandSuggestions: [SlashCommandSuggestion]
    let toolSuggestions: [ToolSuggestion]
    let onSelectCommand: (SlashCommandSuggestion) -> Void
    let onSelectTool: (ToolSuggestion) -> Void
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0

    private var currentItems: Int {
        switch menuState {
        case .hidden:
            return 0
        case .showingCommands:
            return commandSuggestions.count
        case .showingTools:
            return toolSuggestions.count
        }
    }

    var body: some View {
        Group {
            switch menuState {
            case .hidden:
                EmptyView()

            case .showingCommands:
                if !commandSuggestions.isEmpty {
                    commandMenuContent
                }

            case .showingTools:
                if !toolSuggestions.isEmpty {
                    toolMenuContent
                } else {
                    noToolsFoundView
                }
            }
        }
        .onChange(of: menuState) { _ in
            selectedIndex = 0
        }
        .onChange(of: commandSuggestions) { _ in
            selectedIndex = min(selectedIndex, max(0, commandSuggestions.count - 1))
        }
        .onChange(of: toolSuggestions) { _ in
            selectedIndex = min(selectedIndex, max(0, toolSuggestions.count - 1))
        }
    }

    // MARK: - Command Menu

    private var commandMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Commands")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                Spacer()
                Text("esc to dismiss")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(AppColors.divider)

            // Command list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(commandSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                        CommandRow(
                            suggestion: suggestion,
                            isSelected: index == selectedIndex,
                            onSelect: { onSelectCommand(suggestion) }
                        )
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .background(menuBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -4)
    }

    // MARK: - Tool Menu

    private var toolMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Select a tool")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                Spacer()
                Text("\(toolSuggestions.count) tools")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .background(AppColors.divider)

            // Tool list grouped by category
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    let groupedTools = Dictionary(grouping: toolSuggestions) { $0.category }
                    let sortedCategories = groupedTools.keys.sorted()

                    ForEach(sortedCategories, id: \.self) { category in
                        Section {
                            ForEach(groupedTools[category] ?? []) { tool in
                                ToolRow(
                                    tool: tool,
                                    isSelected: false,
                                    onSelect: { onSelectTool(tool) }
                                )
                            }
                        } header: {
                            CategoryHeader(title: category)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
        .background(menuBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -4)
    }

    private var noToolsFoundView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(AppColors.textTertiary)
            Text("No matching tools")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(menuBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -4)
    }

    private var menuBackground: some View {
        ZStack {
            AppColors.substrateSecondary
            Color.black.opacity(0.1)
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let suggestion: SlashCommandSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: suggestion.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                    .frame(width: 24)

                // Command info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("/\(suggestion.command)")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        if suggestion.hasSubmenu {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    Text(suggestion.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? AppColors.signalMercury.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tool Row

private struct ToolRow: View {
    let tool: ToolSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: tool.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                    .frame(width: 24)

                // Tool info
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(tool.description)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Tool ID badge
                Text(tool.toolId)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.substrateTertiary)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? AppColors.signalMercury.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Header

private struct CategoryHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppColors.substrateSecondary.opacity(0.95))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        SlashCommandMenu(
            menuState: .showingCommands,
            commandSuggestions: SlashCommandParser.availableCommands,
            toolSuggestions: [],
            onSelectCommand: { _ in },
            onSelectTool: { _ in },
            onDismiss: {}
        )
        .padding(.horizontal)
        .padding(.bottom, 60)
    }
    .background(AppColors.substratePrimary)
}
