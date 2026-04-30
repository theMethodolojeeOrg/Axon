//
//  LogCategoryRow.swift
//  Axon
//
//  Individual category toggle row for log settings.
//

import SwiftUI

struct LogCategoryRow: View {
    let category: LogCategory
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            Image(systemName: category.icon)
                .font(.system(size: 16))
                .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                .frame(width: 24)

            Text(category.displayName)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            Text("[\(category.rawValue)]")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#Preview {
    LogCategoryRow(
        category: .developerSettings,
        isEnabled: true,
        onToggle: {}
    )
    .background(AppSurfaces.color(.contentBackground))
}
