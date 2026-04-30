//
//  SettingsView.swift
//  Axon
//
//  Main settings view with tabbed interface
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel.shared

    var body: some View {
        ZStack {
            AppSurfaces.color(.contentBackground)
                .ignoresSafeArea()

            SettingsTabView()
                .environmentObject(viewModel)
        }
        // Success/Error Messages
        .overlay(alignment: .top) {
            if let successMessage = viewModel.successMessage {
                SuccessToast(message: successMessage) {
                    viewModel.successMessage = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let errorMessage = viewModel.error {
                ErrorToast(message: errorMessage) {
                    viewModel.error = nil
                }
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
    let onDismiss: () -> Void

    @State private var offset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.accentSuccess)

            Text(message)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(3)

            Spacer()

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(6)
                    .background(Circle().fill(AppSurfaces.color(.controlBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppSurfaces.color(.cardBackground))
                .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        )
        .padding()
        .offset(x: offset + dragOffset)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 100
                    if abs(value.translation.width) > threshold {
                        withAnimation(.easeOut(duration: 0.2)) {
                            offset = value.translation.width > 0 ? 500 : -500
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
                    } else {
                        withAnimation(.spring()) {
                            offset = 0
                        }
                    }
                }
        )
    }
}

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    @State private var offset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)

            Text(message)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(3)

            Spacer()

            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(6)
                    .background(Circle().fill(AppSurfaces.color(.controlBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppSurfaces.color(.cardBackground))
                .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        )
        .padding()
        .offset(x: offset + dragOffset)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    let threshold: CGFloat = 100
                    if abs(value.translation.width) > threshold {
                        withAnimation(.easeOut(duration: 0.2)) {
                            offset = value.translation.width > 0 ? 500 : -500
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onDismiss()
                        }
                    } else {
                        withAnimation(.spring()) {
                            offset = 0
                        }
                    }
                }
        )
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
