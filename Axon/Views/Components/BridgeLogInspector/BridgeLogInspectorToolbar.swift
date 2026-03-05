import SwiftUI

struct BridgeLogInspectorToolbar: View {
    @ObservedObject var logService: BridgeLogService
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppColors.textTertiary)
                    TextField("Filter logs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(AppTypography.bodyMedium())

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            logService.filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
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
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(activeFilterCount > 0 ? AppColors.accentPrimary : AppColors.textSecondary)
                            .padding(8)
                            .background(AppColors.substrateTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(AppTypography.labelSmall(.bold))
                                .foregroundColor(AppColors.substratePrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppColors.accentPrimary)
                                .clipShape(Capsule())
                                .offset(x: 7, y: -6)
                        }
                    }
                }

                Button(action: { logService.clear() }) {
                    Image(systemName: "trash")
                        .foregroundColor(logService.entries.isEmpty ? AppColors.textTertiary : AppColors.textSecondary)
                        .padding(8)
                        .background(AppColors.substrateTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(logService.entries.isEmpty)
            }

            HStack(spacing: 8) {
                Text("\(logService.filteredEntries.count) of \(logService.entries.count)")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)

                if logService.errorCount > 0 {
                    statChip(
                        title: "\(logService.errorCount) errors",
                        color: AppColors.accentError
                    )
                }

                if logService.invalidCount > 0 {
                    statChip(
                        title: "\(logService.invalidCount) invalid",
                        color: AppColors.accentWarning
                    )
                }

                Spacer()

                if activeFilterCount > 0 {
                    Button("Reset filters") {
                        resetFilters()
                    }
                    .buttonStyle(.plain)
                    .font(AppTypography.labelSmall(.semibold))
                    .foregroundColor(AppColors.accentPrimary)
                }
            }
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .onChange(of: searchText) { _, newValue in
            logService.filterText = newValue
        }
        .onAppear {
            searchText = logService.filterText
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if !searchText.isEmpty { count += 1 }
        if !logService.showIncoming { count += 1 }
        if !logService.showOutgoing { count += 1 }
        if !logService.showRequests { count += 1 }
        if !logService.showResponses { count += 1 }
        if !logService.showNotifications { count += 1 }
        if !logService.showErrors { count += 1 }
        if logService.onlyShowInvalid { count += 1 }
        return count
    }

    @ViewBuilder
    private func statChip(title: String, color: Color) -> some View {
        Text(title)
            .font(AppTypography.labelSmall(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func resetFilters() {
        logService.showIncoming = true
        logService.showOutgoing = true
        logService.showRequests = true
        logService.showResponses = true
        logService.showNotifications = true
        logService.showErrors = true
        logService.onlyShowInvalid = false
        searchText = ""
        logService.filterText = ""
    }
}
