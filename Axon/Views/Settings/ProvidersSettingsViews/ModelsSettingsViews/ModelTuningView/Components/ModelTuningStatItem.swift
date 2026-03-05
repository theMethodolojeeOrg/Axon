//
//  ModelTuningStatItem.swift
//  Axon
//
//  Stat item component for displaying value and label.
//

import SwiftUI

struct ModelTuningStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.signalMercury)
            Text(label)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }
}
