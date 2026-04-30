//
//  ChatDebugSection.swift
//  Axon
//
//  Toggle for context debug mode in chat.
//

import SwiftUI

struct ChatDebugSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Chat Debug Toggle
            HStack {
                Image(systemName: viewModel.settings.toolSettings.chatDebugEnabled ? "ant.fill" : "ant")
                    .foregroundColor(viewModel.settings.toolSettings.chatDebugEnabled ? AppColors.signalMercury : AppColors.textSecondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Context Debug Mode")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(viewModel.settings.toolSettings.chatDebugEnabled ? "Showing token breakdown in chat" : "Show detailed context info per message")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(viewModel.settings.toolSettings.chatDebugEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { viewModel.settings.toolSettings.chatDebugEnabled },
                    set: { newValue in
                        viewModel.settings.toolSettings.chatDebugEnabled = newValue
                        try? SettingsStorage.shared.saveSettings(viewModel.settings)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(AppColors.signalMercury)
            }
            .padding()

            Divider()
                .background(AppColors.divider)

            // Info about what debug mode shows
            VStack(alignment: .leading, spacing: 8) {
                Text("When enabled, each assistant message shows:")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    SettingsFeatureRow(icon: "doc.text", text: "System prompt size", iconColor: AppColors.signalMercury)
                    SettingsFeatureRow(icon: "brain.head.profile", text: "Injected memories count & tokens", iconColor: AppColors.signalMercury)
                    SettingsFeatureRow(icon: "clock.arrow.circlepath", text: "Conversation summary tokens", iconColor: AppColors.signalMercury)
                    SettingsFeatureRow(icon: "wrench.and.screwdriver", text: "Tool prompt tokens", iconColor: AppColors.signalMercury)
                    SettingsFeatureRow(icon: "sum", text: "Total context vs model limit", iconColor: AppColors.signalMercury)
                }
            }
            .padding()
        }
        .cornerRadius(8)
    }
}

#Preview {
    SettingsSection(title: "Chat Debug") {
        ChatDebugSection(viewModel: SettingsViewModel())
    }
    .background(AppSurfaces.color(.contentBackground))
}
