import SwiftUI

struct LogEntryRow: View {
    let entry: BridgeLogEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 28, height: 28)

                Image(systemName: entry.messageType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.direction == .outgoing ? "To VS Code" : "From VS Code")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    Text(entry.formattedTimestamp)
                        .font(AppTypography.codeSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Text(entry.summary)
                    .font(AppTypography.bodySmall(.medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        if !entry.isValid || entry.messageType == .error {
            return AppColors.accentError
        }
        switch entry.messageType {
        case .request: return AppColors.accentPrimary
        case .response: return AppColors.accentSuccess
        case .notification: return AppColors.accentWarning
        default: return AppColors.textSecondary
        }
    }
}
