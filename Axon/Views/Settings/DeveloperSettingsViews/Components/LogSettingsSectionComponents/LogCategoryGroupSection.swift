//
//  LogCategoryGroupSection.swift
//  Axon
//
//  Expandable section for a log category group with individual category toggles.
//

import SwiftUI

struct LogCategoryGroupSection: View {
    let group: LogCategoryGroup
    @ObservedObject var logger: DebugLogger

    @State private var isExpanded = false

    private var state: LogCategoryToggleState {
        logger.groupState(for: group)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Group header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    // 3-state toggle
                    LogCategoryToggleButton(
                        state: state,
                        onToggle: { logger.toggleGroup(group) }
                    )

                    Image(systemName: group.icon)
                        .font(.system(size: 16))
                        .foregroundColor(state != .allDisabled ? AppColors.signalMercury : AppColors.textTertiary)
                        .frame(width: 24)

                    Text(group.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text("\(logger.enabledCount(for: group))/\(group.categories.count)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Individual categories
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.categories) { category in
                        LogCategoryRow(
                            category: category,
                            isEnabled: logger.enabledCategories.contains(category),
                            onToggle: { logger.toggleCategory(category) }
                        )

                        if category != group.categories.last {
                            Divider()
                                .background(AppColors.divider)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(AppColors.substrateTertiary.opacity(0.5))
            }
        }
    }
}

#Preview {
    VStack {
        LogCategoryGroupSection(
            group: .security,
            logger: DebugLogger.shared
        )
    }
    .background(AppColors.substratePrimary)
}
