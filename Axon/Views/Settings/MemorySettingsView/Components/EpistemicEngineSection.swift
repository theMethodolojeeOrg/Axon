//
//  EpistemicEngineSection.swift
//  Axon
//
//  Epistemic engine settings section
//

import SwiftUI

struct EpistemicEngineSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Epistemic Engine") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    title: "Epistemic Grounding",
                    description: "Ground responses with verified facts and confidence metrics",
                    isOn: Binding(
                        get: { viewModel.settings.epistemicEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.epistemicEnabled, newValue)
                            }
                        }
                    )
                )

                if viewModel.settings.epistemicEnabled {
                    Divider()
                        .background(AppColors.divider)

                    SettingsToggleRow(
                        title: "Verbose Boundaries",
                        description: "Include detailed epistemic boundaries in prompts",
                        isOn: Binding(
                            get: { viewModel.settings.epistemicVerbose },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.epistemicVerbose, newValue)
                                }
                            }
                        )
                    )

                    Divider()
                        .background(AppColors.divider)

                    SettingsToggleRow(
                        title: "Learning Loop",
                        description: "Refine memory confidence when predictions don't match reality",
                        isOn: Binding(
                            get: { viewModel.settings.learningLoopEnabled },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.learningLoopEnabled, newValue)
                                }
                            }
                        )
                    )
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
}
