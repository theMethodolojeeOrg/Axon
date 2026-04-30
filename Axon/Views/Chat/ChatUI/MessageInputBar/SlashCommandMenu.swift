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
    var availableHeight: CGFloat? = nil
    let menuState: SlashMenuState
    let commandSuggestions: [SlashCommandSuggestion]
    let toolSuggestions: [ToolSuggestion]
    let onSelectCommand: (SlashCommandSuggestion) -> Void
    let onSelectTool: (ToolSuggestion) -> Void
    let onSelectUseTool: (ToolSuggestion) -> Void  // For /use command
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0

    private var currentItems: Int {
        switch menuState {
        case .hidden:
            return 0
        case .showingCommands:
            return commandSuggestions.count
        case .showingTools, .showingUseTools:
            return toolSuggestions.count
        }
    }

    private var menuMaxHeight: CGFloat {
        guard let availableHeight else {
            return ChatVisualTokens.slashMenuAbsoluteMaxHeight
        }
        return min(
            ChatVisualTokens.slashMenuAbsoluteMaxHeight,
            availableHeight * ChatVisualTokens.slashMenuMaxHeightRatio
        )
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

            case .showingUseTools:
                if !toolSuggestions.isEmpty {
                    useToolMenuContent
                } else {
                    noToolsFoundView
                }
            }
        }
        .onChange(of: menuState) {
            selectedIndex = 0
        }
        .onChange(of: commandSuggestions) {
            selectedIndex = min(selectedIndex, max(0, commandSuggestions.count - 1))
        }
        .onChange(of: toolSuggestions) {
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
            .frame(maxHeight: min(menuMaxHeight, 240))
        }
        .appMaterialSurface(radius: 12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -4)
    }

    // MARK: - Tool Menu

    private var toolMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with hint
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.signalMercury)
                Text("Select a tool")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text("\(toolSuggestions.count) available")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppSurfaces.color(.selectedBackground))

            Divider()
                .background(AppColors.divider)

            // Tool list grouped by category - larger scrollable area
            ScrollView(.vertical, showsIndicators: true) {
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
                .padding(.bottom, 8)
            }
            .frame(maxHeight: menuMaxHeight)

            // Footer hint - clarify this shows definition to AI
            HStack {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                Text("Tap to show tool definition to AI")
                    .font(.system(size: 11))
            }
            .foregroundColor(AppColors.textTertiary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(AppSurfaces.color(.controlMutedBackground))
        }
        .appMaterialSurface(radius: 12)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: -6)
    }

    // MARK: - Use Tool Menu (for /use command)

    private var useToolMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with different styling for /use
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.signalLichen)
                Text("Run a tool")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text("\(toolSuggestions.count) available")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.signalLichen.opacity(0.12))

            Divider()
                .background(AppColors.divider)

            // Tool list grouped by category
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    let groupedTools = Dictionary(grouping: toolSuggestions) { $0.category }
                    let sortedCategories = groupedTools.keys.sorted()

                    ForEach(sortedCategories, id: \.self) { category in
                        Section {
                            ForEach(groupedTools[category] ?? []) { tool in
                                UseToolRow(
                                    tool: tool,
                                    isSelected: false,
                                    onSelect: { onSelectUseTool(tool) }
                                )
                            }
                        } header: {
                            CategoryHeader(title: category)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: menuMaxHeight)

            // Footer hint for /use
            HStack {
                Image(systemName: "hand.tap")
                    .font(.system(size: 10))
                Text("Tap to invoke tool directly")
                    .font(.system(size: 11))
            }
            .foregroundColor(AppColors.textTertiary.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(AppSurfaces.color(.controlMutedBackground))
        }
        .appMaterialSurface(radius: 12)
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: -6)
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
        .appMaterialSurface(radius: 12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: -4)
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let suggestion: SlashCommandSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isPressed = false
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon with colored background for better touch target visibility
                Image(systemName: suggestion.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isPressed || isHovering || isSelected ? .white : AppColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isPressed || isHovering || isSelected ? AppColors.signalMercury : AppSurfaces.color(.controlBackground))
                    )

                // Command info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("/\(suggestion.command)")
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundColor(AppColors.textPrimary)

                        if suggestion.hasSubmenu {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppColors.signalMercury)
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
            .padding(.vertical, 12) // Taller for better touch targets
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isPressed || isHovering || isSelected ? AppSurfaces.color(.selectedBackground) : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(TouchFeedbackButtonStyle(isPressed: $isPressed))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Touch Feedback Button Style

private struct TouchFeedbackButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

// MARK: - Tool Row

private struct ToolRow: View {
    let tool: ToolSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon with colored background
                Image(systemName: tool.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovering || isSelected ? .white : AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovering || isSelected ? AppColors.signalMercury : AppSurfaces.color(.controlBackground))
                    )

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

                // Info indicator (shows definition, not invoke)
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundColor(isHovering || isSelected ? AppColors.signalMercury : AppColors.textTertiary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering || isSelected ? AppSurfaces.color(.selectedBackground) : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Use Tool Row (for /use command - shows play icon)

private struct UseToolRow: View {
    let tool: ToolSuggestion
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon with green background for invoke action
                Image(systemName: tool.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovering || isSelected ? .white : AppColors.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovering || isSelected ? AppColors.signalLichen : AppSurfaces.color(.controlBackground))
                    )

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

                // Play indicator (invoke action)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isHovering || isSelected ? AppColors.signalLichen : AppColors.textTertiary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering || isSelected ? AppColors.signalLichen.opacity(0.1) : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
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
        .background(.ultraThinMaterial)
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
            onSelectUseTool: { _ in },
            onDismiss: {}
        )
        .padding(.horizontal)
        .padding(.bottom, 60)
    }
    .background(AppSurfaces.color(.contentBackground))
}
