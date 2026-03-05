import SwiftUI

struct LogEntryRow: View {
    let entry: BridgeLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                eventChip(
                    title: entry.direction == .outgoing ? "To VS Code" : "From VS Code",
                    icon: entry.direction.icon,
                    color: AppColors.textSecondary
                )

                eventChip(
                    title: entry.messageType.rawValue,
                    icon: entry.messageType.icon,
                    color: statusColor
                )

                if !entry.isValid {
                    eventChip(
                        title: "Invalid",
                        icon: "exclamationmark.triangle.fill",
                        color: AppColors.accentError
                    )
                }

                Spacer(minLength: 8)

                Text(entry.formattedTimestamp)
                    .font(AppTypography.codeSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Text(entry.summary)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let requestId = entry.requestId, !requestId.isEmpty {
                Text("id: \(requestId)")
                    .font(AppTypography.codeSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

    @ViewBuilder
    private func eventChip(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(AppTypography.labelSmall(.semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
    }
}
