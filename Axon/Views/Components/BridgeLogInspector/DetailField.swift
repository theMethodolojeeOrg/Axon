import SwiftUI

struct DetailField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)
        }
    }
}
