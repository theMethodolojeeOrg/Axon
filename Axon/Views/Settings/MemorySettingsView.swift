//
//  MemorySettingsView.swift
//  Axon
//
//  Memory system configuration and preferences
//

import SwiftUI

struct MemorySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Memory System Toggle
            SettingsSection(title: "Memory System") {
                VStack(spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.memoryEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.memoryEnabled, newValue)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Memory")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Allow the AI to remember facts and preferences across conversations")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .tint(AppColors.signalMercury)

                    if viewModel.settings.memoryEnabled {
                        Divider()
                            .background(AppColors.divider)

                        Toggle(isOn: Binding(
                            get: { viewModel.settings.memoryAutoInject },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.memoryAutoInject, newValue)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-Inject Memories")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Automatically include relevant memories in conversations")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .tint(AppColors.signalMercury)
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // Confidence Threshold
            if viewModel.settings.memoryEnabled {
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

            // Memory Types Info
            SettingsSection(title: "Memory Types") {
                VStack(spacing: 12) {
                    MemoryTypeInfo(
                        icon: "lightbulb.fill",
                        title: "Facts",
                        description: "Specific information and data points",
                        color: AppColors.signalMercury
                    )

                    MemoryTypeInfo(
                        icon: "gearshape.fill",
                        title: "Procedures",
                        description: "Step-by-step processes and how-to information",
                        color: AppColors.signalLichen
                    )

                    MemoryTypeInfo(
                        icon: "text.quote",
                        title: "Context",
                        description: "Background information and situational awareness",
                        color: AppColors.signalCopper
                    )

                    MemoryTypeInfo(
                        icon: "arrow.triangle.branch",
                        title: "Relationships",
                        description: "Connections between concepts and entities",
                        color: AppColors.signalHematite
                    )
                }
            }

            // Analytics Toggle
            SettingsSection(title: "Analytics") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.memoryAnalyticsEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.updateSetting(\.memoryAnalyticsEnabled, newValue)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Usage Analytics")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Help improve the app by sharing anonymous usage data")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.signalMercury)
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }
    }
}

// MARK: - Memory Type Info Row

struct MemoryTypeInfo: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MemorySettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
