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
            ConsoleToolbar(
                isAutoScrollEnabled: $isAutoScrollEnabled,
                onCopy: { copyLogsToClipboard() },
                onClear: { logger.clearLogs() },
                onClose: { dismiss() }
            )

            Divider()
                .background(AppColors.divider)

            // Filter bar
            ConsoleFilterBar(
                filterCategory: $filterCategory,
                searchText: $searchText
            )

            Divider()
                .background(AppColors.divider)

            // Log list
            if filteredEntries.isEmpty {
                ConsoleEmptyState(
                    logEntries: logger.logEntries,
                    loggingEnabled: logger.loggingEnabled
                )
            } else {
                ConsoleLogList(
                    entries: filteredEntries,
                    logEntriesCount: logger.logEntries.count,
                    isAutoScrollEnabled: isAutoScrollEnabled
                )
            }

            // Status bar
            ConsoleStatusBar(
                filteredCount: filteredEntries.count,
                totalCount: logger.logEntries.count,
                enabledCount: logger.enabledCount,
                totalCategories: logger.totalCount,
                loggingEnabled: logger.loggingEnabled
            )
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
        .overlay(ConsoleCopiedToast(isVisible: $showCopiedToast))
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

// MARK: - Preview

#Preview {
    DeveloperConsoleView()
}
