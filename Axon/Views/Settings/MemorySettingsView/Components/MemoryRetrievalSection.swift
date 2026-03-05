//
//  MemoryRetrievalSection.swift
//  Axon
//
//  Memory retrieval settings section
//

import SwiftUI

struct MemoryRetrievalSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Memory Retrieval") {
            VStack(spacing: 20) {
                // Confidence Threshold
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Confidence Threshold")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Text("\(Int(viewModel.settings.memoryConfidenceThreshold * 100))%")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)
                    }

                    Slider(
                        value: Binding(
                            get: { viewModel.settings.memoryConfidenceThreshold },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.memoryConfidenceThreshold, newValue)
                                }
                            }
                        ),
                        in: 0...1,
                        step: 0.05
                    )
                    .tint(AppColors.signalMercury)

                    Text("Only memories with confidence above this threshold will be used. Higher values mean stricter filtering.")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                Divider()
                    .background(AppColors.divider)

                // Max Memories Per Request
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Memories Per Request")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Text("\(viewModel.settings.maxMemoriesPerRequest)")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.signalMercury)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(viewModel.settings.maxMemoriesPerRequest) },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.maxMemoriesPerRequest, Int(newValue))
                                }
                            }
                        ),
                        in: 5...50,
                        step: 5
                    )
                    .tint(AppColors.signalMercury)

                    Text("Maximum number of memories to include in each request. Higher values use more tokens.")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
}
