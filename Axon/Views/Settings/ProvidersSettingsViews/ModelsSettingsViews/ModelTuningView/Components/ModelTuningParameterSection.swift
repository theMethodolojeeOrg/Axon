//
//  ModelTuningParameterSection.swift
//  Axon
//
//  Parameter section for Double values with enable toggle and slider.
//

import SwiftUI

struct ModelTuningParameterSection: View {
    let title: String
    let description: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let format: String

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
                    Text(String(format: format, val))
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.signalMercury)
                        .monospacedDigit()
                }
            }

            if isEnabled, value != nil {
                Slider(
                    value: Binding(
                        get: { value ?? range.lowerBound },
                        set: { value = $0 }
                    ),
                    in: range,
                    step: step
                )
                .tint(AppColors.signalMercury)
            }
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}
