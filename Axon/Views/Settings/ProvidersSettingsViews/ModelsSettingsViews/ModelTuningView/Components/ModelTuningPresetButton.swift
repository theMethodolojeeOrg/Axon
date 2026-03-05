//
//  ModelTuningPresetButton.swift
//  Axon
//
//  Button component for applying preset configurations.
//

import SwiftUI

struct ModelTuningPresetButton: View {
    let preset: ModelOverridePreset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(preset.displayName)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.substrateTertiary)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}
