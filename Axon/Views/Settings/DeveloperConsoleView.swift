//
//  DeveloperConsoleView.swift
//  Axon
//
//  In-app developer console showing filtered debug logs.
//  Accessible from Developer Settings and Chat Info when enabled.
//

import SwiftUI

struct DeveloperConsoleView: View {
    @StateObject private var logger = DebugLogger.shared
    @Environment(\.dismiss) private var dismiss

    @State private var filterCategory: LogCategory? = nil
    @State private var searchText = ""
    @State private var isAutoScrollEnabled = true
    @State private var showCopiedToast = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            consoleToolbar

            Divider()
                .background(AppColors.divider)

            // Filter bar
            filterBar

            Divider()
                .background(AppColors.divider)

            // Log list
            if filteredEntries.isEmpty {
                emptyState
            } else {
                logList
            }

            // Status bar
            statusBar
        }
        .background(Color.black)
        #if os(iOS)
        .navigationTitle("Developer Console")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(AppColors.signalMercury)
            }
        }
        #endif
        .overlay(copiedToast)
    }

    // MARK: - Toolbar

    private var consoleToolbar: some View {
        HStack(spacing: 16) {
            #if os(macOS)
            Text("Developer Console")
                .font(AppTypography.titleSmall())
                .foregroundColor(.white)
            #endif

            Spacer()

            // Auto-scroll toggle
            Button {
                isAutoScrollEnabled.toggle()
            } label: {
                Image(systemName: isAutoScrollEnabled ? "arrow.down.to.line.compact" : "arrow.down.to.line")
                    .foregroundColor(isAutoScrollEnabled ? AppColors.signalLichen : .gray)
            }
            .buttonStyle(.plain)
            .help("Auto-scroll to new logs")

            // Copy all
            Button {
                copyLogsToClipboard()
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help("Copy all logs")

            // Clear
            Button {
                logger.clearLogs()
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(AppColors.accentError)
            }
            .buttonStyle(.plain)
            .help("Clear logs")

            #if os(macOS)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.1))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 12))

                TextField("Filter logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(white: 0.15))
            .cornerRadius(6)

            // Category filter
            Menu {
                Button("All Categories") {
                    filterCategory = nil
                }
                Divider()
                ForEach(LogCategoryGroup.allCases) { group in
                    Section(group.displayName) {
                        ForEach(group.categories) { category in
                            Button {
                                filterCategory = category
                            } label: {
                                HStack {
                                    Image(systemName: category.icon)
                                    Text(category.displayName)
                                    if filterCategory == category {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: filterCategory?.icon ?? "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12))
                    Text(filterCategory?.displayName ?? "All")
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(filterCategory != nil ? AppColors.signalMercury : .gray)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.15))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.08))
    }

    // MARK: - Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        DebugLogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: logger.logEntries.count) { _ in
                if isAutoScrollEnabled, let lastId = filteredEntries.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text(logger.logEntries.isEmpty ? "No logs yet" : "No matching logs")
                .font(AppTypography.bodySmall())
                .foregroundColor(.gray)

            if !logger.loggingEnabled {
                Text("Enable logging in Developer Settings")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalMercury)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            // Log count
            Text("\(filteredEntries.count) of \(logger.logEntries.count) logs")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            Spacer()

            // Enabled categories
            Text("\(logger.enabledCount)/\(logger.totalCount) categories")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)

            // Logging status
            Circle()
                .fill(logger.loggingEnabled ? AppColors.signalLichen : AppColors.accentError)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.1))
    }

    // MARK: - Copied Toast

    private var copiedToast: some View {
        Group {
            if showCopiedToast {
                VStack {
                    Spacer()
                    Text("Copied to clipboard")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(AppColors.signalLichen)
                        .cornerRadius(8)
                        .padding(.bottom, 60)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showCopiedToast)
    }

    // MARK: - Helpers

    private var filteredEntries: [DebugLogEntry] {
        var entries = logger.logEntries

        // Filter by category
        if let category = filterCategory {
            entries = entries.filter { $0.category == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            entries = entries.filter {
                $0.message.lowercased().contains(query) ||
                $0.category.rawValue.lowercased().contains(query)
            }
        }

        return entries
    }

    private func copyLogsToClipboard() {
        let text = logger.exportLogsAsText()
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif

        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedToast = false
        }
    }
}

// MARK: - Debug Log Entry Row

private struct DebugLogEntryRow: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.formattedTimestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 85, alignment: .leading)

            // Category badge
            Text(entry.category.rawValue)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(categoryColor(for: entry.category))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(categoryColor(for: entry.category).opacity(0.2))
                .cornerRadius(4)
                .frame(width: 140, alignment: .leading)

            // Message
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func categoryColor(for category: LogCategory) -> Color {
        switch category.group {
        case .security: return .orange
        case .data: return .blue
        case .sync: return .cyan
        case .config: return .purple
        case .services: return .green
        case .media: return .pink
        case .tools: return .yellow
        case .developer: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    DeveloperConsoleView()
}
