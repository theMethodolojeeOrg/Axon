import SwiftUI

struct BridgeLogInspectorToolbar: View {
    @ObservedObject var logService: BridgeLogService
    @Binding var searchText: String

    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textTertiary)
                TextField("Filter logs...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTypography.bodyMedium())
            }
            .padding(8)
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)

            Menu {
                Toggle("Incoming", isOn: $logService.showIncoming)
                Toggle("Outgoing", isOn: $logService.showOutgoing)
                Divider()
                Toggle("Requests", isOn: $logService.showRequests)
                Toggle("Responses", isOn: $logService.showResponses)
                Toggle("Notifications", isOn: $logService.showNotifications)
                Toggle("Errors", isOn: $logService.showErrors)
                Divider()
                Toggle("Only Invalid", isOn: $logService.onlyShowInvalid)
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(
                        logService.filteredEntries.count != logService.entries.count
                            ? AppColors.accentPrimary
                            : AppColors.textSecondary
                    )
            }

            Button(action: { logService.clear() }) {
                Image(systemName: "trash")
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .onChange(of: searchText) { _, newValue in
            logService.filterText = newValue
        }
    }
}
