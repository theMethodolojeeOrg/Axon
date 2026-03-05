//
//  HeuristicsSection.swift
//  Axon
//
//  Heuristics settings section
//

import SwiftUI

struct HeuristicsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        SettingsSection(title: "Heuristics") {
            VStack(spacing: 16) {
                SettingsToggleRow(
                    title: "Enable Heuristics",
                    description: "Compress memories into distilled insights for efficient context injection",
                    isOn: Binding(
                        get: { viewModel.settings.heuristicsSettings.enabled },
                        set: { newValue in
                            Task {
                                var heuristics = viewModel.settings.heuristicsSettings
                                heuristics.enabled = newValue
                                await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                            }
                        }
                    )
                )

                if viewModel.settings.heuristicsSettings.enabled {
                    Divider()
                        .background(AppColors.divider)

                    // Per-type synthesis intervals
                    ForEach(HeuristicType.allCases) { type in
                        heuristicIntervalSlider(for: type)
                    }

                    Divider()
                        .background(AppColors.divider)

                    // Meta-synthesis interval
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(AppColors.signalMercury)
                            Text("Meta-Synthesis Interval")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text(intervalLabelDays(seconds: viewModel.settings.heuristicsSettings.metaSynthesisIntervalSeconds))
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.heuristicsSettings.metaSynthesisIntervalSeconds) },
                                set: { newValue in
                                    Task {
                                        var heuristics = viewModel.settings.heuristicsSettings
                                        heuristics.metaSynthesisIntervalSeconds = Int(newValue)
                                        await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                                    }
                                }
                            ),
                            in: 86400...2592000,  // 1 day to 30 days
                            step: 86400
                        )
                        .tint(AppColors.signalMercury)

                        Text("Distill old heuristics into their cores and archive originals")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Divider()
                        .background(AppColors.divider)

                    // Context window threshold
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Context Window Threshold")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("\(viewModel.settings.heuristicsSettings.contextWindowThreshold) tokens")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.heuristicsSettings.contextWindowThreshold) },
                                set: { newValue in
                                    Task {
                                        var heuristics = viewModel.settings.heuristicsSettings
                                        heuristics.contextWindowThreshold = Int(newValue)
                                        await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                                    }
                                }
                            ),
                            in: 2000...32000,
                            step: 1000
                        )
                        .tint(AppColors.signalMercury)

                        Text("Inject heuristics when model context is below this threshold")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Divider()
                        .background(AppColors.divider)

                    // Heuristics:Memory ratio
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Heuristics : Memory Ratio")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text("\(Int(viewModel.settings.heuristicsSettings.heuristicsMemoryRatio * 100))% : \(Int((1 - viewModel.settings.heuristicsSettings.heuristicsMemoryRatio) * 100))%")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { viewModel.settings.heuristicsSettings.heuristicsMemoryRatio },
                                set: { newValue in
                                    Task {
                                        var heuristics = viewModel.settings.heuristicsSettings
                                        heuristics.heuristicsMemoryRatio = newValue
                                        await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                                    }
                                }
                            ),
                            in: 0...1,
                            step: 0.1
                        )
                        .tint(AppColors.signalMercury)

                        Text("Balance between heuristics and raw memories when injecting context")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }

    // MARK: - Heuristic Interval Slider

    @ViewBuilder
    private func heuristicIntervalSlider(for type: HeuristicType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: type.icon)
                    .foregroundColor(heuristicTypeColor(type))
                Text("\(type.displayName) Interval")
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(intervalLabelHeuristic(for: type))
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.signalMercury)
            }

            Slider(
                value: heuristicIntervalBinding(for: type),
                in: heuristicIntervalRange(for: type),
                step: heuristicIntervalStep(for: type)
            )
            .tint(AppColors.signalMercury)

            Text(type.description)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
    }

    private func heuristicIntervalBinding(for type: HeuristicType) -> Binding<Double> {
        Binding(
            get: { Double(viewModel.settings.heuristicsSettings.interval(for: type)) },
            set: { newValue in
                Task {
                    var heuristics = viewModel.settings.heuristicsSettings
                    heuristics.setInterval(Int(newValue), for: type)
                    await viewModel.updateSetting(\.heuristicsSettings, heuristics)
                }
            }
        )
    }

    private func heuristicIntervalRange(for type: HeuristicType) -> ClosedRange<Double> {
        switch type {
        case .recency:
            return 3600...86400       // 1 hour to 1 day
        case .frequency, .curiosity:
            return 14400...604800     // 4 hours to 1 week
        case .interest:
            return 86400...2592000    // 1 day to 30 days
        }
    }

    private func heuristicIntervalStep(for type: HeuristicType) -> Double {
        switch type {
        case .recency:
            return 3600       // 1 hour steps
        case .frequency, .curiosity:
            return 14400      // 4 hour steps
        case .interest:
            return 86400      // 1 day steps
        }
    }

    private func intervalLabelHeuristic(for type: HeuristicType) -> String {
        let seconds = viewModel.settings.heuristicsSettings.interval(for: type)
        return intervalLabelDays(seconds: seconds)
    }

    private func intervalLabelDays(seconds: Int) -> String {
        if seconds < 3600 {
            return "\(max(1, seconds / 60))m"
        } else if seconds < 86400 {
            let hours = Double(seconds) / 3600.0
            return String(format: "%.0fh", hours)
        } else {
            let days = Double(seconds) / 86400.0
            if days == 1 {
                return "1 day"
            } else if days < 7 {
                return String(format: "%.0f days", days)
            } else {
                let weeks = days / 7
                return String(format: "%.0f week%@", weeks, weeks == 1 ? "" : "s")
            }
        }
    }

    private func heuristicTypeColor(_ type: HeuristicType) -> Color {
        switch type {
        case .frequency: return AppColors.signalMercury
        case .recency: return .orange
        case .curiosity: return .purple
        case .interest: return .pink
        }
    }
}
