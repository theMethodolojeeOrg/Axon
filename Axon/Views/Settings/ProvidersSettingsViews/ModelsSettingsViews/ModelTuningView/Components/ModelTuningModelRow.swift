//
//  ModelTuningModelRow.swift
//  Axon
//
//  Row component for individual model in provider accordion.
//

import SwiftUI

struct ModelTuningModelRow: View {
    let model: AIModel
    let override: ModelOverride?
    let onSelect: () -> Void
    let onToggle: (Bool) -> Void

    private var isOverridden: Bool {
        override?.enabled == true
    }

    private var hasCustomValues: Bool {
        guard let override = override else { return false }
        return override.hasOverrides
    }

    var body: some View {
        HStack(spacing: 12) {
            // Override toggle
            Toggle("", isOn: Binding(
                get: { isOverridden },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(AppColors.signalMercury)
            .labelsHidden()

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    if isOverridden && hasCustomValues {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.signalMercury)
                    }
                }

                Text(model.id)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Override count badge
            if let override = override, override.enabled, override.overrideCount > 0 {
                Text("\(override.overrideCount)")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.signalMercury)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.signalMercury.opacity(0.15))
                    .cornerRadius(4)
            }

            // Detail button
            Button(action: onSelect) {
                Image(systemName: "info.circle")
                    .foregroundColor(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
