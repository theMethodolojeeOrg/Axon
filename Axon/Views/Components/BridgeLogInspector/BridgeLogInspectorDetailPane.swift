import SwiftUI

struct BridgeLogInspectorDetailPane: View {
    let selectedEntry: BridgeLogEntry?
    @ObservedObject var logService: BridgeLogService

    var body: some View {
        Group {
            if let entry = selectedEntry {
                LogDetailView(entry: entry)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right.circle")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.substrateTertiary)
                    Text("Select a log entry to view details")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.substratePrimary)
            }
        }
        .background(AppColors.substratePrimary)
    }
}
