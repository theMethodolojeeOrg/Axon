//
//  OnboardingPageView.swift
//  Axon
//
//  Reusable page component for onboarding flow
//

import SwiftUI

struct OnboardingPageView: View {
    let iconName: String?       // SF Symbol name, or nil to show Axon logo
    let headline: String
    let subtext: String?
    let isLastPage: Bool
    let ctaText: String?
    let onComplete: (() -> Void)?

    init(
        iconName: String? = nil,
        headline: String,
        subtext: String? = nil,
        isLastPage: Bool = false,
        ctaText: String? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.iconName = iconName
        self.headline = headline
        self.subtext = subtext
        self.isLastPage = isLastPage
        self.ctaText = ctaText
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon or Logo
            Group {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 72, weight: .light))
                        .foregroundColor(AppColors.signalMercury)
                } else {
                    Image("AxonMercury")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                }
            }
            .padding(.bottom, 40)

            // Headline
            Text(headline)
                .font(AppTypography.displaySmall())
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Subtext
            if let subtext = subtext {
                Text(subtext)
                    .font(AppTypography.bodyLarge())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 16)
            }

            Spacer()

            // CTA Button (only on last page)
            if isLastPage, let onComplete = onComplete {
                Button(action: onComplete) {
                    Text(ctaText ?? "Get Started")
                        .font(AppTypography.labelLarge())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.signalMercury)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            } else {
                // Spacer for non-CTA pages to keep consistent layout
                Spacer()
                    .frame(height: 120)
            }
        }
    }
}

#Preview("Page 1 - Logo") {
    OnboardingPageView(
        headline: "AI that actually knows you.",
        subtext: "No more re-explaining. No more starting over. I remember."
    )
    .background(AppColors.substratePrimary)
}

#Preview("Page 4 - CTA") {
    OnboardingPageView(
        iconName: "sparkles",
        headline: "Let's begin.",
        isLastPage: true,
        ctaText: "Start Chatting",
        onComplete: {}
    )
    .background(AppColors.substratePrimary)
}
