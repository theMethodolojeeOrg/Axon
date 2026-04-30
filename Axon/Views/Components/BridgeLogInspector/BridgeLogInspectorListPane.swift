import SwiftUI

struct BridgeLogInspectorListPane: View {
    @ObservedObject var logService: BridgeLogService
    @Binding var searchText: String
    @Binding var selectedEntry: BridgeLogEntry?

    var body: some View {
        VStack(spacing: 0) {
            BridgeLogInspectorToolbar(logService: logService, searchText: $searchText)

            Divider()

            if logService.filteredEntries.isEmpty {
                emptyState
            } else {
                List(selection: $selectedEntry) {
                    ForEach(logService.filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                            .tag(entry)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(selectedEntry == entry ? AppSurfaces.color(.controlBackground) : Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(AppSurfaces.color(.contentBackground))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: logService.entries.isEmpty ? "waveform.path.ecg" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 28))
                .foregroundColor(AppColors.textTertiary)

            Text(logService.entries.isEmpty ? "No bridge logs yet" : "No logs match this filter")
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.textPrimary)

            Text(logService.entries.isEmpty
                 ? "Send or receive a bridge message to populate this list."
                 : "Try clearing search or adjusting your filter toggles.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaces.color(.contentBackground))
    }
}
