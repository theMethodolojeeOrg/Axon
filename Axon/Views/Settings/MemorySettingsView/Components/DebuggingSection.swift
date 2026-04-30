//
//  DebuggingSection.swift
//  Axon
//
//  Debugging settings section
//

import SwiftUI

struct DebuggingSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Debugging") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    title: "Predicate Logging",
                    description: "Log formal proof trees for debugging and verification",
                    isOn: Binding(
                        get: { viewModel.settings.predicateLoggingEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.predicateLoggingEnabled, newValue)
                            }
                        }
                    )
                )

                if viewModel.settings.predicateLoggingEnabled {
                    Divider()
                        .background(AppColors.divider)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Verbosity Level")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)

                        Picker("Verbosity", selection: Binding(
                            get: { viewModel.settings.predicateLoggingVerbosity },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.predicateLoggingVerbosity, newValue)
                                }
                            }
                        )) {
                            ForEach(PredicateVerbosity.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        Text(viewModel.settings.predicateLoggingVerbosity.description)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding()
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
    }
}
