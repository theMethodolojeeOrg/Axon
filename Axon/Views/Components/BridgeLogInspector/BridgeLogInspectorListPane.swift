import SwiftUI

struct BridgeLogInspectorListPane: View {
    @ObservedObject var logService: BridgeLogService
    @Binding var searchText: String
    @Binding var selectedEntry: BridgeLogEntry?

    var body: some View {
        VStack(spacing: 0) {
            BridgeLogInspectorToolbar(logService: logService, searchText: $searchText)

            Divider()

            List(selection: $selectedEntry) {
                ForEach(logService.filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                        .tag(entry)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(selectedEntry == entry ? AppColors.substrateTertiary : Color.clear)
                }
            }
            .listStyle(.plain)
        }
    }
}
