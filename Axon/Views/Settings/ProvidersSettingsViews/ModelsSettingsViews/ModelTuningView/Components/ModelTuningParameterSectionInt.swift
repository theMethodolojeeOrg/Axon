//
//  ModelTuningParameterSectionInt.swift
//  Axon
//
//  Parameter section for Int values with enable toggle and slider.
//

import SwiftUI

struct ModelTuningParameterSectionInt: View {
    let title: String
    let description: String
    @Binding var value: Int?
    let range: ClosedRange<Int>

    private var isEnabled: Bool {
        value != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        if newValue && value == nil {
                            value = (range.lowerBound + range.upperBound) / 2
                        } else if !newValue {
                            value = nil
                        }
                    }
                ))
                .toggleStyle(.switch)
                .tint(AppColors.signalMercury)
                .labelsHidden()

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(description)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                if let val = value {
                    Text("\(val)")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.signalMercury)
                        .monospacedDigit()
                }
            }

            if isEnabled, value != nil {
                Slider(
                    value: Binding(
                        get: { Double(value ?? range.lowerBound) },
                        set: { value = Int($0) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .tint(AppColors.signalMercury)
            }
        }
        .padding()
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
}
