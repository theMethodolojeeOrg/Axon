//
//  TemporalStatusBar.swift
//  Axon
//
//  A compact status bar showing temporal symmetry information:
//  - Turn count (lifetime)
//  - Context saturation percentage
//  - Current mode (sync/drift)
//
//  Philosophy: Both parties see temporal metadata for mutual observability.
//

import SwiftUI

struct TemporalStatusBar: View {
    @ObservedObject var temporalService = TemporalContextService.shared
    @ObservedObject var settingsViewModel = SettingsViewModel.shared

    /// Current context saturation (0.0 to 1.0)
    var contextSaturation: Double = 0.0

    /// Context window limit for the current model
    var contextLimit: Int = 128_000

    var body: some View {
        // Only show if enabled in settings
        if settingsViewModel.settings.temporalSettings.showStatusBar {
            HStack(spacing: 12) {
                // Mode indicator
                modeIndicator

                Divider()
                    .frame(height: 12)
                    .background(AppColors.divider)

                // Turn count
                turnCountView

                Divider()
                    .frame(height: 12)
                    .background(AppColors.divider)

                // Context saturation
                contextSaturationView

                // Session duration (if in sync mode and tracking)
                if temporalService.currentMode == .sync,
                   let startTime = temporalService.sessionStartedAt {
                    Divider()
                        .frame(height: 12)
                        .background(AppColors.divider)

                    sessionDurationView(startTime: startTime)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppSurfaces.color(.transientBackground).opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppSurfaces.color(.cardBorder).opacity(0.5), lineWidth: 0.5)
                    )
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Mode Indicator

    private var modeIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: temporalService.currentMode.icon)
                .font(.system(size: 10))

            Text(temporalService.currentMode.displayName)
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(temporalService.currentMode == .sync ? AppColors.signalMercury : AppColors.textTertiary)
    }

    // MARK: - Turn Count

    private var turnCountView: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 10))

            Text("Turn \(temporalService.lifetimeTurnCount)")
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(AppColors.textSecondary)
    }

    // MARK: - Context Saturation

    private var contextSaturationView: some View {
        let percent = contextSaturation * 100
        let saturationDisplay = percent == 0 ? "0%" : (percent < 1 ? "<1%" : "\(Int(round(percent)))%")

        return HStack(spacing: 6) {
            // Progress bar - expands to fill available space
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppSurfaces.color(.controlMutedBackground))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(saturationColor)
                        .frame(width: geometry.size.width * contextSaturation, height: 4)
                }
            }
            .frame(height: 4)
            .frame(minWidth: 40, maxWidth: 80)

            Text(saturationDisplay)
                .font(AppTypography.labelSmall())
                .foregroundColor(saturationColor)
                .fixedSize()
        }
    }

    private var saturationColor: Color {
        if contextSaturation >= 0.9 {
            return AppColors.accentError
        } else if contextSaturation >= 0.75 {
            return AppColors.accentWarning
        }
        return AppColors.signalMercury
    }

    // MARK: - Session Duration

    private func sessionDurationView(startTime: Date) -> some View {
        let duration = Date().timeIntervalSince(startTime)
        let formatted = formatDuration(duration)

        return HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.system(size: 10))

            Text(formatted)
                .font(AppTypography.labelSmall())
        }
        .foregroundColor(AppColors.textTertiary)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Sync mode
        TemporalStatusBar(contextSaturation: 0.45)

        // High saturation
        TemporalStatusBar(contextSaturation: 0.85)

        // Critical saturation
        TemporalStatusBar(contextSaturation: 0.95)
    }
    .padding()
    .appSurface(.contentBackground)
}
