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
        case apiKeys = "API Keys"
        case models = "Models"
        case custom = "Custom"
        case tools = "Tools"
        case dynamicTools = "Pipelines"
        case intents = "Intents"
        case memory = "Memory"
        case sovereignty = "Consent"
        case security = "Security"
        case devices = "Devices"
        case server = "API Server"
        case backend = "Backend"
        case tts = "TTS"
        case archived = "Archived"
        case developer = "Developer"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .apiKeys: return "key.fill"
            case .models: return "cpu"
            case .custom: return "slider.horizontal.3"
            case .tools: return "wrench.and.screwdriver.fill"
            case .dynamicTools: return "arrow.triangle.branch"
            case .intents: return "app.connected.to.app.below.fill"
            case .memory: return "AxonLogoTemplate"
            case .sovereignty: return "shield.checkered"
            case .security: return "lock.shield.fill"
            case .devices: return "laptopcomputer.and.iphone"
            case .server: return "network"
            case .backend: return "server.rack"
            case .tts: return "waveform.circle.fill"
            case .archived: return "archivebox.fill"
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
                        case .apiKeys:
                            APIKeysSettingsView(viewModel: viewModel)
                        case .models:
                            ModelSyncSettingsView(viewModel: viewModel)
                        case .custom:
                            CustomProvidersSettingsView(viewModel: viewModel)
                        case .tools:
                            ToolSettingsView(viewModel: viewModel)
                        case .dynamicTools:
                            DynamicToolsSettingsView(viewModel: viewModel)
                        case .intents:
                            IntentsSettingsView()
                        case .memory:
                            MemorySettingsView(viewModel: viewModel)
                        case .sovereignty:
                            SovereigntySettingsView(viewModel: viewModel)
                        case .security:
                            SecuritySettingsView(viewModel: viewModel)
                        case .devices:
                            DevicesSettingsView(viewModel: viewModel)
                        case .server:
                            ServerSettingsView(viewModel: viewModel)
                        case .backend:
                            BackendSettingsView(viewModel: viewModel)
                        case .tts:
                            TTSSettingsView(viewModel: viewModel)
                        case .archived:
                            ArchivedConversationsSettingsView(viewModel: viewModel)
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
