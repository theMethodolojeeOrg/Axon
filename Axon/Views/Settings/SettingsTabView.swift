//
//  SettingsTabView.swift
//  Axon
//
//  Main settings view with tabs for different sections
//

import SwiftUI

struct SettingsTabView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case apiKeys = "API Keys"
        case custom = "Custom"
        case memory = "Memory"
        case server = "API Server"
        case tts = "TTS"
        case account = "Account"
        case archived = "Archived"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .apiKeys: return "key.fill"
            case .custom: return "slider.horizontal.3"
            case .memory: return "AxonLogoTemplate"
            case .server: return "network"
            case .tts: return "waveform.circle.fill"
            case .account: return "person.crop.circle.fill"
            case .archived: return "archivebox.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SettingsTab.allCases) { tab in
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

            // Tab content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView(viewModel: viewModel)
                    case .apiKeys:
                        APIKeysSettingsView(viewModel: viewModel)
                    case .custom:
                        CustomProvidersSettingsView(viewModel: viewModel)
                    case .memory:
                        MemorySettingsView(viewModel: viewModel)
                    case .server:
                        ServerSettingsView(viewModel: viewModel)
                    case .tts:
                        TTSSettingsView(viewModel: viewModel)
                    case .account:
                        AccountSettingsView(viewModel: viewModel)
                    case .archived:
                        ArchivedConversationsSettingsView(viewModel: viewModel)
                    }
                }
                .padding()
            }
            .background(AppColors.substratePrimary)

            // Success/Error messages
            if let successMessage = viewModel.successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.accentSuccess)
                    Text(successMessage)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding()
                .background(AppColors.accentSuccess.opacity(0.2))
                .cornerRadius(8)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.accentError)
                    Text(error)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding()
                .background(AppColors.accentError.opacity(0.2))
                .cornerRadius(8)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(AppColors.substratePrimary)
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
}

