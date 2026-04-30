//
//  BridgeLogInspector.swift
//  Axon
//
//  Inspector view for viewing VS Code Bridge WebSocket traffic logs.
//

import SwiftUI

struct BridgeLogInspector: View {
    @ObservedObject var logService = BridgeLogService.shared
    @State private var searchText = ""
    @State private var selectedEntry: BridgeLogEntry?
    @State private var compactShowsDetail = false
    let availableWidth: CGFloat?

    init(availableWidth: CGFloat? = nil) {
        self.availableWidth = availableWidth
    }

    private var usesCompactLayout: Bool {
        guard let availableWidth else { return false }
        return availableWidth < 680
    }

    var body: some View {
        Group {
            if usesCompactLayout {
                compactLayout
            } else {
                regularLayout
            }
        }
        .background(AppSurfaces.color(.contentBackground))
        .onAppear {
            searchText = logService.filterText
            compactShowsDetail = usesCompactLayout && selectedEntry != nil
        }
        .onChange(of: selectedEntry) { _, newValue in
            guard usesCompactLayout else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                compactShowsDetail = newValue != nil
            }
        }
        .onChange(of: usesCompactLayout) { _, isCompact in
            guard isCompact else {
                compactShowsDetail = false
                return
            }
            compactShowsDetail = selectedEntry != nil
        }
    }

    private var regularLayout: some View {
        HStack(spacing: 0) {
            BridgeLogInspectorListPane(
                logService: logService,
                searchText: $searchText,
                selectedEntry: $selectedEntry
            )
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 430)

            Divider()

            BridgeLogInspectorDetailPane(selectedEntry: selectedEntry, logService: logService)
                .frame(minWidth: 280, maxWidth: .infinity)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            if compactShowsDetail, let selectedEntry {
                compactDetailHeader(for: selectedEntry)
                Divider()
                BridgeLogInspectorDetailPane(selectedEntry: selectedEntry, logService: logService)
            } else {
                BridgeLogInspectorListPane(
                    logService: logService,
                    searchText: $searchText,
                    selectedEntry: $selectedEntry
                )
            }
        }
    }

    private func compactDetailHeader(for entry: BridgeLogEntry) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    compactShowsDetail = false
                    selectedEntry = nil
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(AppTypography.labelSmall(.semibold))
                    .foregroundColor(AppColors.textSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.messageType.rawValue)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                Text(entry.summary)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            Text(entry.formattedTimestamp)
                .font(AppTypography.codeSmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppSurfaces.color(.cardBackground))
    }
}
