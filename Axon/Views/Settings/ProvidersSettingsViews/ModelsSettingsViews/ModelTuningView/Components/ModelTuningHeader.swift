//
//  ModelTuningHeader.swift
//  Axon
//
//  Header section for the Model Tuning view.
//

import SwiftUI

struct ModelTuningHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per-Model Overrides")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)

            Text("Fine-tune generation parameters for specific models. Overrides take precedence over global defaults.")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
    }
}
