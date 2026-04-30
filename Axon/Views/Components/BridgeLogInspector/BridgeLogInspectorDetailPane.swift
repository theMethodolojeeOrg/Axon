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
                    Image(systemName: logService.entries.isEmpty ? "waveform.path.ecg" : "arrow.left.arrow.right.circle")
                        .font(.system(size: 48))
                        .foregroundColor(AppSurfaces.color(.controlBackground))

                    Text(logService.entries.isEmpty ? "Waiting for bridge traffic" : "Select a log entry to view details")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textSecondary)

                    if logService.entries.isEmpty {
                        Text("Bridge request/response payloads will appear here as they are captured.")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 260)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppSurfaces.color(.contentBackground))
            }
        }
        .background(AppSurfaces.color(.contentBackground))
    }
}
