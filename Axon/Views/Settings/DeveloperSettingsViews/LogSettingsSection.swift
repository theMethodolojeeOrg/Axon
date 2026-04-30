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
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
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
                    .background(AppSurfaces.color(.cardBackground))
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
    .background(AppSurfaces.color(.contentBackground))
}
