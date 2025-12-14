//
//  BridgeLogInspector.swift
//  Axon
//
//  Inspector view for VS Code Bridge WebSocket traffic logs.
//  Shows live traffic with JSON validation and pretty printing.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)

struct BridgeLogInspectorView: View {
    @ObservedObject var logService = BridgeLogService.shared
    @ObservedObject var bridgeServer = BridgeServer.shared

    @State private var selectedEntry: BridgeLogEntry?
    @State private var showFilters = false

    var body: some View {
        VStack(spacing: 0) {
            // Connection status bar
            connectionStatusBar

            Divider()
                .overlay(AppColors.glassBorder.opacity(0.4))

            // Filter bar (collapsible)
            if showFilters {
                filterBar
                    .transition(.move(edge: .top).combined(with: .opacity))

                Divider()
                    .overlay(AppColors.glassBorder.opacity(0.4))
            }

            // Main content
            if logService.entries.isEmpty {
                emptyState
            } else {
                HSplitView {
                    // Log list
                    logList
                        .frame(minWidth: 200)

                    // Detail view
                    if let entry = selectedEntry {
                        logDetailView(entry: entry)
                            .frame(minWidth: 200)
                    }
                }
            }

            Divider()
                .overlay(AppColors.glassBorder.opacity(0.4))

            // Bottom toolbar
            bottomToolbar
        }
        .background(AppColors.substratePrimary)
    }

    // MARK: - Connection Status Bar

    private var connectionStatusBar: some View {
        HStack(spacing: 10) {
            // Connection indicator
            Circle()
                .fill(bridgeServer.isConnected ? AppColors.signalLichen : (bridgeServer.isRunning ? AppColors.accentWarning : AppColors.textTertiary))
                .frame(width: 8, height: 8)

            if let session = bridgeServer.connectedSession {
                Text(session.displayName)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textPrimary)

                Text("•")
                    .foregroundColor(AppColors.textTertiary)

                Text(session.workspaceRoot)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if bridgeServer.isRunning {
                Text("Waiting for connection...")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
            } else {
                Text("Bridge not running")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            // Filter toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFilters.toggle()
                }
            } label: {
                Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14))
                    .foregroundColor(showFilters ? AppColors.signalMercury : AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Filters")

            // Stats
            HStack(spacing: 8) {
                StatBadge(icon: "arrow.up.arrow.down", count: logService.entries.count, color: AppColors.textSecondary)
                if logService.errorCount > 0 {
                    StatBadge(icon: "exclamationmark.triangle", count: logService.errorCount, color: AppColors.accentError)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.substrateElevated.opacity(0.3))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textTertiary)
                TextField("Filter by method, id, or content...", text: $logService.filterText)
                    .textFieldStyle(.plain)
                    .font(AppTypography.bodySmall())

                if !logService.filterText.isEmpty {
                    Button {
                        logService.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)

            // Filter toggles
            HStack(spacing: 12) {
                FilterToggle(label: "Incoming", isOn: $logService.showIncoming, color: AppColors.signalLichen)
                FilterToggle(label: "Outgoing", isOn: $logService.showOutgoing, color: AppColors.signalMercury)

                Divider().frame(height: 16)

                FilterToggle(label: "Requests", isOn: $logService.showRequests)
                FilterToggle(label: "Responses", isOn: $logService.showResponses)
                FilterToggle(label: "Errors", isOn: $logService.showErrors)

                Divider().frame(height: 16)

                FilterToggle(label: "Invalid Only", isOn: $logService.onlyShowInvalid, color: AppColors.accentError)

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.substratePrimary)
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(logService.filteredEntries) { entry in
                    LogEntryRow(entry: entry, isSelected: selectedEntry?.id == entry.id)
                        .onTapGesture {
                            selectedEntry = entry
                        }
                }
            }
            .padding(8)
        }
        .background(AppColors.substratePrimary)
    }

    // MARK: - Log Detail View

    private func logDetailView(entry: BridgeLogEntry) -> some View {
        VStack(spacing: 0) {
            // Detail header
            HStack(spacing: 10) {
                Image(systemName: entry.direction.icon)
                    .foregroundColor(entry.direction == .incoming ? AppColors.signalLichen : AppColors.signalMercury)

                Text(entry.summary)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(entry.formattedTimestamp)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)

                // Copy button
                Button {
                    AppClipboard.copy(entry.prettyJSON)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Copy JSON")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppColors.substrateElevated.opacity(0.3))

            Divider()
                .overlay(AppColors.glassBorder.opacity(0.4))

            // Validation errors if any
            if !entry.isValid {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.accentError)
                        Text("Validation Errors")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.accentError)
                    }

                    ForEach(entry.validationErrors, id: \.self) { error in
                        Text("• \(error)")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.accentError.opacity(0.1))

                Divider()
                    .overlay(AppColors.glassBorder.opacity(0.4))
            }

            // JSON content
            ScrollView([.vertical, .horizontal]) {
                Text(entry.prettyJSON)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.substratePrimary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundColor(AppColors.textTertiary)

            Text("No WebSocket traffic yet")
                .font(AppTypography.titleSmall())
                .foregroundColor(AppColors.textPrimary)

            Text("Messages between Axon and VS Code will appear here when the bridge is connected.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if !bridgeServer.isRunning {
                Button("Start Bridge") {
                    Task {
                        await bridgeServer.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.signalMercury)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.substratePrimary)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            // Logging toggle
            Toggle(isOn: $logService.isLoggingEnabled) {
                Image(systemName: logService.isLoggingEnabled ? "record.circle" : "record.circle.fill")
                    .foregroundColor(logService.isLoggingEnabled ? AppColors.accentError : AppColors.textTertiary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(logService.isLoggingEnabled ? "Logging enabled" : "Logging paused")

            Spacer()

            // Export button
            Button {
                exportLogs()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(logService.entries.isEmpty)
            .help("Export Logs")

            // Clear button
            Button {
                logService.clear()
                selectedEntry = nil
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(logService.entries.isEmpty)
            .help("Clear Logs")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.substratePrimary)
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "bridge-logs-\(ISO8601DateFormatter().string(from: Date())).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try logService.export().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[BridgeLogInspector] Failed to export: \(error)")
            }
        }
    }
}

// MARK: - Helper Views

private struct LogEntryRow: View {
    let entry: BridgeLogEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Direction indicator
            Image(systemName: entry.direction.icon)
                .font(.system(size: 12))
                .foregroundColor(entry.direction == .incoming ? AppColors.signalLichen : AppColors.signalMercury)
                .frame(width: 16)

            // Method/Summary
            Text(entry.summary)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)

            Spacer()

            // Validation indicator
            if !entry.isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.accentError)
            }

            // Timestamp
            Text(entry.formattedTimestamp)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

private struct StatBadge: View {
    let icon: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text("\(count)")
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(color.opacity(0.1))
        )
    }
}

private struct FilterToggle: View {
    let label: String
    @Binding var isOn: Bool
    var color: Color = AppColors.textSecondary

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(isOn ? color : AppColors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isOn ? color.opacity(0.15) : AppColors.substrateSecondary)
                )
        }
        .buttonStyle(.plain)
    }
}

#endif
