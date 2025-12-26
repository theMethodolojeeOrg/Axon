//
//  LogSettingsSection.swift
//  Axon
//
//  Logging toggles UI for Developer Settings.
//  Inspired by ToolSettingsViewV2 category management pattern.
//

import SwiftUI

// MARK: - Log Settings Section

struct LogSettingsSection: View {
    @StateObject private var logger = DebugLogger.shared

    var body: some View {
        VStack(spacing: 0) {
            // Master Toggle
            MasterLogToggle(
                isEnabled: $logger.loggingEnabled,
                enabledCount: logger.enabledCount,
                totalCount: logger.totalCount
            )

            if logger.loggingEnabled {
                Divider()
                    .background(AppColors.divider)

                // Quick actions
                QuickActionsRow(
                    onEnableAll: { logger.enableAll() },
                    onDisableAll: { logger.disableAll() }
                )

                Divider()
                    .background(AppColors.divider)

                // Category groups
                ForEach(LogCategoryGroup.allCases) { group in
                    LogCategoryGroupSection(
                        group: group,
                        logger: logger
                    )

                    if group != LogCategoryGroup.allCases.last {
                        Divider()
                            .background(AppColors.divider)
                    }
                }
            }
        }
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Master Log Toggle

private struct MasterLogToggle: View {
    @Binding var isEnabled: Bool
    let enabledCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isEnabled ? "ant.fill" : "ant")
                .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textSecondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text("Debug Logging")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(isEnabled ? "\(enabledCount)/\(totalCount) categories active" : "Enable to see detailed logs in console")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(AppColors.signalMercury)
        }
        .padding()
    }
}

// MARK: - Quick Actions Row

private struct QuickActionsRow: View {
    let onEnableAll: () -> Void
    let onDisableAll: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEnableAll) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Enable All")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.signalLichen)
            }
            .buttonStyle(.plain)

            Button(action: onDisableAll) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Disable All")
                        .font(AppTypography.labelSmall())
                }
                .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(AppColors.substrateTertiary.opacity(0.5))
    }
}

// MARK: - Category Group Section

private struct LogCategoryGroupSection: View {
    let group: LogCategoryGroup
    @ObservedObject var logger: DebugLogger

    @State private var isExpanded = false

    private var state: LogCategoryToggleState {
        logger.groupState(for: group)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Group header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // 3-state toggle
                    LogCategoryToggleButton(
                        state: state,
                        onToggle: { logger.toggleGroup(group) }
                    )

                    Image(systemName: group.icon)
                        .font(.system(size: 16))
                        .foregroundColor(state != .allDisabled ? AppColors.signalMercury : AppColors.textTertiary)
                        .frame(width: 24)

                    Text(group.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text("\(logger.enabledCount(for: group))/\(group.categories.count)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Individual categories
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.categories) { category in
                        LogCategoryRow(
                            category: category,
                            isEnabled: logger.enabledCategories.contains(category),
                            onToggle: { logger.toggleCategory(category) }
                        )

                        if category != group.categories.last {
                            Divider()
                                .background(AppColors.divider)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(AppColors.substrateTertiary.opacity(0.5))
            }
        }
    }
}

// MARK: - Category Toggle Button (3-state)

private struct LogCategoryToggleButton: View {
    let state: LogCategoryToggleState
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

// MARK: - Individual Category Row

private struct LogCategoryRow: View {
    let category: LogCategory
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            Image(systemName: category.icon)
                .font(.system(size: 16))
                .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 24)

            Text(category.displayName)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Text("[\(category.rawValue)]")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Developer Console Row

struct DeveloperConsoleRow: View {
    @StateObject private var logger = DebugLogger.shared
    @State private var showingConsole = false

    var body: some View {
        VStack(spacing: 0) {
            // Console Toggle
            HStack(spacing: 12) {
                Image(systemName: logger.consoleEnabled ? "terminal.fill" : "terminal")
                    .foregroundColor(logger.consoleEnabled ? AppColors.signalMercury : AppColors.textSecondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Developer Console")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(logger.consoleEnabled ? "Quick access enabled in Chat Info" : "Enable to show console in Chat Info")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(logger.consoleEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                }

                Spacer()

                Toggle("", isOn: $logger.consoleEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(AppColors.signalMercury)
            }
            .padding()

            // Open Console Button
            if logger.loggingEnabled {
                Divider()
                    .background(AppColors.divider)

                Button {
                    showingConsole = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.and.text.magnifyingglass")
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 32)

                        Text("Open Console")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)

                        Spacer()

                        // Log count badge
                        if !logger.logEntries.isEmpty {
                            Text("\(logger.logEntries.count)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.signalMercury)
                                .cornerRadius(10)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingConsole) {
            #if os(iOS)
            NavigationView {
                DeveloperConsoleView()
            }
            #else
            DeveloperConsoleView()
                .frame(minWidth: 800, idealWidth: 1000, minHeight: 500, idealHeight: 700)
            #endif
        }
    }
}

// MARK: - Developer Console Quick Access (for ChatInfoSettingsView)

/// Shows developer console quick access when console is enabled
struct DeveloperConsoleQuickAccess: View {
    @StateObject private var logger = DebugLogger.shared
    @State private var showingConsole = false

    var body: some View {
        if logger.consoleEnabled && logger.loggingEnabled {
            ChatInfoSection(title: "Developer") {
                Button {
                    showingConsole = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "terminal.fill")
                            .foregroundColor(AppColors.signalMercury)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Developer Console")
                                .font(AppTypography.bodySmall(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("\(logger.logEntries.count) log entries")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        Spacer()

                        // Status indicator
                        Circle()
                            .fill(AppColors.signalLichen)
                            .frame(width: 8, height: 8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showingConsole) {
                #if os(iOS)
                NavigationView {
                    DeveloperConsoleView()
                }
                #else
                DeveloperConsoleView()
                    .frame(minWidth: 800, idealWidth: 1000, minHeight: 500, idealHeight: 700)
                #endif
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            SettingsSection(title: "Debug Logging") {
                LogSettingsSection()
            }
        }
        .padding()
    }
    .background(AppColors.substratePrimary)
}
