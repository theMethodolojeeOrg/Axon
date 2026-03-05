//
//  SettingsTabView.swift
//  Axon
//
//  Main settings view with tabs for different sections
//

import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var selectedTab: SettingsTab = .general

    /// Available tabs - developer tab available to everyone in local-first mode
    private var availableTabs: [SettingsTab] {
        SettingsTab.allCases
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case account = "Account"
        case providers = "Providers"
        case automation = "Automation"
        case memory = "Memory"
        case privacy = "Privacy"
        case connectivity = "Connectivity"
        case developer = "Developer"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .account: return "person.crop.circle.fill"
            case .providers: return "key.fill"
            case .automation: return "wrench.and.screwdriver.fill"
            case .memory: return "AxonLogoTemplate"
            case .privacy: return "shield.checkered"
            case .connectivity: return "network"
            case .developer: return "hammer.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableTabs) { tab in
                        SettingsTabButton(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab
                        ) {
                            withAnimation {
                                selectedTab = tab
                            }
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.substrateSecondary)

            Divider()
                .background(AppColors.divider)

            // Tab content - wrapped in NavigationStack for sub-navigation (e.g., DataManagementView)
            NavigationStack {
                ScrollView {
                    Group {
                        switch selectedTab {
                        case .general:
                            GeneralSettingsView(viewModel: viewModel)
                        case .account:
                            AccountSettingsView(viewModel: viewModel)
                        case .providers:
                            ProvidersSettingsView(viewModel: viewModel)
                        case .automation:
                            AutomationSettingsView(viewModel: viewModel)
                        case .memory:
                            MemorySettingsView(viewModel: viewModel)
                        case .privacy:
                            PrivacySettingsView(viewModel: viewModel)
                        case .connectivity:
                            ConnectivitySettingsView(viewModel: viewModel)
                        case .developer:
                            DeveloperSettingsView(viewModel: viewModel)
                        }
                    }
                    .padding()
                }
                .background(AppColors.substratePrimary)
            }

            // Success/Error messages
            if let successMessage = viewModel.successMessage {
                DismissableBanner(
                    message: successMessage,
                    icon: "checkmark.circle.fill",
                    color: AppColors.accentSuccess,
                    onDismiss: { viewModel.successMessage = nil }
                )
            }

            if let error = viewModel.error {
                DismissableBanner(
                    message: error,
                    icon: "exclamationmark.triangle.fill",
                    color: AppColors.accentError,
                    onDismiss: { viewModel.error = nil }
                )
            }
        }
        .background(AppColors.substratePrimary)
    }
}

// MARK: - Dismissable Banner

struct DismissableBanner: View {
    let message: String
    let icon: String
    let color: Color
    let onDismiss: () -> Void

    @State private var offset: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(message)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(3)

            Spacer()

            // Dismiss button (X) for Mac/pointer devices
            Button(action: {
                withAnimation(.easeOut(duration: 0.2)) {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(6)
                    .background(Circle().fill(AppColors.substrateTertiary))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(color.opacity(0.2))
        .cornerRadius(8)
        .padding()
        .offset(x: offset + dragOffset)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    // Allow dragging in either direction
                    state = value.translation.width
                }
                .onEnded { value in
                    // Dismiss if dragged far enough in either direction
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Tab Button

struct SettingsTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if icon == "AxonLogoTemplate" || icon == "AxonMercuryVector" {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(.white) // will tint template images; AxonLogoTemplate is white template
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }
                Text(title)
                    .font(AppTypography.titleSmall())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? AppColors.signalMercury : AppColors.substrateTertiary)
            )
            .foregroundColor(isSelected ? .white : AppColors.textSecondary)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsTabView()
        .environmentObject(SettingsViewModel.shared)
}
