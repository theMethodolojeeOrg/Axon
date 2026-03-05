//
//  InternalThreadSection.swift
//  Axon
//
//  Internal thread settings section
//

import SwiftUI

struct InternalThreadSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Internal Thread") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    title: "Enable Internal Thread",
                    description: "Allow the agent to persist its internal thread across sessions",
                    isOn: Binding(
                        get: { viewModel.settings.internalThreadEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.internalThreadEnabled, newValue)
                            }
                        }
                    )
                )

                Divider()
                    .background(AppColors.divider)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Retention")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Text(retentionLabel(days: viewModel.settings.internalThreadRetentionDays))
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.settings.internalThreadRetentionDays) },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.internalThreadRetentionDays, Int(newValue))
                                }
                            }
                        ),
                        in: 0...365,
                        step: 1
                    )
                    .tint(AppColors.signalMercury)

                    Text("0 means keep indefinitely.")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }

    private func retentionLabel(days: Int) -> String {
        days == 0 ? "Never" : "\(days)d"
    }
}
