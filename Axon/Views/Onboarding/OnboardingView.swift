//
//  OnboardingView.swift
//  Axon
//
//  Onboarding flow - punchy, assertive, reframes AI around the user
//

import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared
    @State private var currentPage = 0
    let onComplete: () -> Void

    private let totalPages = 4

    var body: some View {
        ZStack {
            // Background
            AppColors.substratePrimary
                .ignoresSafeArea()

            // Page content
            TabView(selection: $currentPage) {
                // Page 1: The Reframe
                OnboardingPageView(
                    headline: "AI that actually knows you.",
                    subtext: "No more re-explaining. No more starting over. I remember."
                )
                .tag(0)

                // Page 2: Memory (Core Differentiator)
                OnboardingPageView(
                    iconName: "brain.head.profile",
                    headline: "Your context. Preserved.",
                    subtext: "Every conversation makes me better at helping you. Not someone else's model—yours."
                )
                .tag(1)

                // Page 3: Model Agnostic
                OnboardingPageView(
                    iconName: "arrow.triangle.swap",
                    headline: "Any AI. Your memories.",
                    subtext: "Claude, GPT, Gemini, that model the kids are using, whatever—switch anytime. Your context travels with you."
                )
                .tag(2)

                // Page 4: Get Started
                OnboardingPageView(
                    iconName: "sparkles",
                    headline: "Let's begin.",
                    isLastPage: true,
                    ctaText: "Start Chatting",
                    onComplete: completeOnboarding
                )
                .tag(3)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif

            // Skip button (top-right)
            VStack {
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                    }
                }
                Spacer()
            }
        }
    }

    private func completeOnboarding() {
        Task {
            await settingsViewModel.updateSetting(\.hasCompletedOnboarding, true)
            onComplete()
        }
    }
}

#Preview {
    OnboardingView {
        print("Onboarding complete!")
    }
}
