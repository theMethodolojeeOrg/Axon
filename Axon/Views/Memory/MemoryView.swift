//
//  MemoryView.swift
//  Axon
//
//  Main memory view wrapper with toast overlays
//

import SwiftUI

struct MemoryView: View {
    @ObservedObject var viewModel = MemoryViewModel.shared

    var body: some View {
        ZStack {
            AppSurfaces.color(.contentBackground)
                .ignoresSafeArea()

            MemoryContentView()
                .environmentObject(viewModel)
        }
        // Success/Error Messages
        .overlay(alignment: .top) {
            if let successMessage = viewModel.successMessage {
                MemorySuccessToast(message: successMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let errorMessage = viewModel.error {
                MemoryErrorToast(message: errorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppAnimations.standardEasing, value: viewModel.successMessage != nil)
        .animation(AppAnimations.standardEasing, value: viewModel.error != nil)
    }
}

// MARK: - Toast Messages

struct MemorySuccessToast: View {
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
                .fill(AppSurfaces.color(.transientBackground))
                .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        )
        .padding()
    }
}

struct MemoryErrorToast: View {
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
                .fill(AppSurfaces.color(.transientBackground))
                .shadow(color: AppColors.shadowStrong, radius: 8, x: 0, y: 4)
        )
        .padding()
    }
}

// MARK: - Preview

#Preview {
    MemoryView()
}
