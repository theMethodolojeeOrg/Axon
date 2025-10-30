//
//  SettingsView.swift
//  Axon
//
//  Main settings view with tabbed interface
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()

            SettingsTabView()
                .environmentObject(viewModel)
        }
        // Success/Error Messages
        .overlay(alignment: .top) {
            if let successMessage = viewModel.successMessage {
                SuccessToast(message: successMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let errorMessage = viewModel.error {
                ErrorToast(message: errorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppAnimations.standardEasing, value: viewModel.successMessage != nil)
        .animation(AppAnimations.standardEasing, value: viewModel.error != nil)
    }
}

// MARK: - Toast Messages

struct SuccessToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.accentSuccess)

            Text(message)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
                .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        )
        .padding()
    }
}

struct ErrorToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)

            Text(message)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.substrateSecondary)
                .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        )
        .padding()
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let iconColor: Color
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor)
                }

                // Title and subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                // Chevron
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)
                }
            }
            .padding(16)
        }
        .disabled(action == nil)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}

