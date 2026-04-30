//
//  GlassCard.swift
//  Axon
//
//  Glass Morphism Card Component
//

import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content
    let padding: CGFloat
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let shadowRadius: CGFloat

    init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        borderWidth: CGFloat = 1,
        shadowRadius: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.shadowRadius = shadowRadius
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppSurfaces.color(.cardBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(AppColors.glassOverlay)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(AppSurfaces.color(.cardBorder), lineWidth: borderWidth)
                    )
                    .shadow(color: AppColors.shadow, radius: shadowRadius, x: 0, y: 4)
            )
            .background(.ultraThinMaterial.opacity(0.3))
            .cornerRadius(cornerRadius)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        AppSurfaces.color(.contentBackground)
            .ignoresSafeArea()

        VStack(spacing: 20) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Glass Card Title")
                        .appStyle(AppTypography.titleLarge(), color: AppColors.textPrimary)
                    Text("This is a glass morphism card with backdrop blur and subtle borders.")
                        .appStyle(AppTypography.bodyMedium(), color: AppColors.textSecondary)
                }
            }

            GlassCard(padding: 20, cornerRadius: 16) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(AppColors.signalMercury)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text("AI Response")
                            .appStyle(AppTypography.titleMedium(), color: AppColors.textPrimary)
                        Text("With custom padding")
                            .appStyle(AppTypography.bodySmall(), color: AppColors.textSecondary)
                    }
                    Spacer()
                }
            }
        }
        .padding()
    }
}
