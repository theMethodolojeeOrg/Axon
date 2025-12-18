//
//  MemorySettingsView.swift
//  Axon
//
//  Memory system configuration and preferences
//

import SwiftUI

struct MemorySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Memory System Toggle
            SettingsSection(title: "Memory System") {
                VStack(spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.memoryEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.memoryEnabled, newValue)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Memory")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Allow the Axon to remember facts about you and learn about itself in your context across conversations")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .tint(AppColors.signalMercury)

                    if viewModel.settings.memoryEnabled {
                        Divider()
                            .background(AppColors.divider)

                        Toggle(isOn: Binding(
                            get: { viewModel.settings.memoryAutoInject },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.memoryAutoInject, newValue)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-Inject Memories")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Automatically include relevant memories in conversations")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .tint(AppColors.signalMercury)
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // Confidence Threshold
            if viewModel.settings.memoryEnabled {
                SettingsSection(title: "Memory Retrieval") {
                    VStack(spacing: 20) {
                        // Confidence Threshold
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Confidence Threshold")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)

                                Spacer()

                                Text("\(Int(viewModel.settings.memoryConfidenceThreshold * 100))%")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.signalMercury)
                            }

                            Slider(
                                value: Binding(
                                    get: { viewModel.settings.memoryConfidenceThreshold },
                                    set: { newValue in
                                        Task {
                                            await viewModel.updateSetting(\.memoryConfidenceThreshold, newValue)
                                        }
                                    }
                                ),
                                in: 0...1,
                                step: 0.05
                            )
                            .tint(AppColors.signalMercury)

                            Text("Only memories with confidence above this threshold will be used. Higher values mean stricter filtering.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        Divider()
                            .background(AppColors.divider)

                        // Max Memories Per Request
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Max Memories Per Request")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)

                                Spacer()

                                Text("\(viewModel.settings.maxMemoriesPerRequest)")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.signalMercury)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.settings.maxMemoriesPerRequest) },
                                    set: { newValue in
                                        Task {
                                            await viewModel.updateSetting(\.maxMemoriesPerRequest, Int(newValue))
                                        }
                                    }
                                ),
                                in: 5...50,
                                step: 5
                            )
                            .tint(AppColors.signalMercury)

                            Text("Maximum number of memories to include in each request. Higher values use more tokens.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }
            }

            // Memory Types Info
            SettingsSection(title: "Memory Types") {
                VStack(spacing: 12) {
                    MemoryTypeInfo(
                        icon: "brain.head.profile",
                        title: "Allocentric",
                        description: "Knowledge about you: preferences, facts, relationships, context",
                        color: AppColors.signalMercury
                    )

                    MemoryTypeInfo(
                        icon: "person.fill",
                        title: "Egoic",
                        description: "What works for the AI: procedures, insights, learnings",
                        color: AppColors.signalLichen
                    )
                }
            }

            // Epistemic Engine Section
            if viewModel.settings.memoryEnabled {
                SettingsSection(title: "Epistemic Engine") {
                    VStack(spacing: 16) {
                        // Epistemic Grounding Toggle
                        Toggle(isOn: Binding(
                            get: { viewModel.settings.epistemicEnabled },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.epistemicEnabled, newValue)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Epistemic Grounding")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Ground responses with verified facts and confidence metrics")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .tint(AppColors.signalMercury)

                        if viewModel.settings.epistemicEnabled {
                            Divider()
                                .background(AppColors.divider)

                            // Verbose Mode Toggle
                            Toggle(isOn: Binding(
                                get: { viewModel.settings.epistemicVerbose },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSetting(\.epistemicVerbose, newValue)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Verbose Boundaries")
                                        .font(AppTypography.bodyMedium(.medium))
                                        .foregroundColor(AppColors.textPrimary)

                                    Text("Include detailed epistemic boundaries in prompts")
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                            .tint(AppColors.signalMercury)

                            Divider()
                                .background(AppColors.divider)

                            // Learning Loop Toggle
                            Toggle(isOn: Binding(
                                get: { viewModel.settings.learningLoopEnabled },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSetting(\.learningLoopEnabled, newValue)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Learning Loop")
                                        .font(AppTypography.bodyMedium(.medium))
                                        .foregroundColor(AppColors.textPrimary)

                                    Text("Refine memory confidence when predictions don't match reality")
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                            .tint(AppColors.signalMercury)
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }

                // Predicate Logging Section
                SettingsSection(title: "Debugging") {
                    VStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { viewModel.settings.predicateLoggingEnabled },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSetting(\.predicateLoggingEnabled, newValue)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Predicate Logging")
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Text("Log formal proof trees for debugging and verification")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                        .tint(AppColors.signalMercury)

                        if viewModel.settings.predicateLoggingEnabled {
                            Divider()
                                .background(AppColors.divider)

                            // Verbosity Picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Verbosity Level")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)

                                Picker("Verbosity", selection: Binding(
                                    get: { viewModel.settings.predicateLoggingVerbosity },
                                    set: { newValue in
                                        Task {
                                            await viewModel.updateSetting(\.predicateLoggingVerbosity, newValue)
                                        }
                                    }
                                )) {
                                    ForEach(PredicateVerbosity.allCases, id: \.self) { level in
                                        Text(level.displayName).tag(level)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())

                                Text(viewModel.settings.predicateLoggingVerbosity.description)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                }
            }

            // Analytics Toggle
            SettingsSection(title: "Analytics") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.memoryAnalyticsEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.updateSetting(\.memoryAnalyticsEnabled, newValue)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Usage Analytics")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Help improve the app by sharing anonymous usage data")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.signalMercury)
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // Internal Thread
            SettingsSection(title: "Internal Thread") {
                VStack(spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.internalThreadEnabled },
                        set: { newValue in
                            Task {
                                await viewModel.updateSetting(\.internalThreadEnabled, newValue)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Internal Thread")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Allow the agent to persist its internal thread across sessions")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .tint(AppColors.signalMercury)

                    Divider()
                        .background(AppColors.divider)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Retention")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Text(retentionLabel(days: viewModel.settings.internalThreadRetentionDays))
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.signalMercury)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.internalThreadRetentionDays) },
                                set: { newValue in
                                    Task {
                                        await viewModel.updateSetting(\.internalThreadRetentionDays, Int(newValue))
                                    }
                                }
                            ),
                            in: 0...365,
                            step: 1
                        )
                        .tint(AppColors.signalMercury)

                        Text("0 means keep indefinitely.")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // Heartbeat
            SettingsSection(title: "Heartbeat") {
                VStack(spacing: 16) {
                    Toggle(isOn: Binding(
                        get: { viewModel.settings.heartbeatSettings.enabled },
                        set: { newValue in
                            Task {
                                var heartbeat = viewModel.settings.heartbeatSettings
                                heartbeat.enabled = newValue
                                await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Heartbeat")
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)

                            Text("Run periodic internal check-ins and update the internal thread")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .tint(AppColors.signalMercury)

                    if viewModel.settings.heartbeatSettings.enabled {
                        Divider()
                            .background(AppColors.divider)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Interval")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)

                                Spacer()

                                Text(intervalLabel(seconds: viewModel.settings.heartbeatSettings.intervalSeconds))
                                    .font(AppTypography.bodyMedium(.medium))
                                    .foregroundColor(AppColors.signalMercury)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.settings.heartbeatSettings.intervalSeconds) },
                                    set: { newValue in
                                        Task {
                                            var heartbeat = viewModel.settings.heartbeatSettings
                                            heartbeat.intervalSeconds = Int(newValue)
                                            await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                        }
                                    }
                                ),
                                in: 300...86400,
                                step: 300
                            )
                            .tint(AppColors.signalMercury)
                        }

                        Divider()
                            .background(AppColors.divider)

                        HStack {
                            Text("Delivery Profile")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Spacer()

                            Picker("", selection: Binding(
                                get: { viewModel.settings.heartbeatSettings.deliveryProfileId },
                                set: { newValue in
                                    Task {
                                        var heartbeat = viewModel.settings.heartbeatSettings
                                        heartbeat.deliveryProfileId = newValue
                                        await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                    }
                                }
                            )) {
                                ForEach(viewModel.settings.heartbeatSettings.deliveryProfiles, id: \.id) { profile in
                                    Text(profile.name).tag(profile.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Divider()
                            .background(AppColors.divider)

                        Toggle(isOn: Binding(
                            get: { viewModel.settings.heartbeatSettings.allowNotifications },
                            set: { newValue in
                                Task {
                                    var heartbeat = viewModel.settings.heartbeatSettings
                                    heartbeat.allowNotifications = newValue
                                    await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                }
                            }
                        )) {
                            Text("Allow Heartbeat Notifications")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .tint(AppColors.signalMercury)

                        Toggle(isOn: Binding(
                            get: { viewModel.settings.heartbeatSettings.allowBackground },
                            set: { newValue in
                                Task {
                                    var heartbeat = viewModel.settings.heartbeatSettings
                                    heartbeat.allowBackground = newValue
                                    await viewModel.updateSetting(\.heartbeatSettings, heartbeat)
                                }
                            }
                        )) {
                            Text("Allow Background Heartbeat")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)
                        }
                        .tint(AppColors.signalMercury)
                    }
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }

            // Notifications
            SettingsSection(title: "Notifications") {
                Toggle(isOn: Binding(
                    get: { viewModel.settings.notificationsEnabled },
                    set: { newValue in
                        Task {
                            await viewModel.updateSetting(\.notificationsEnabled, newValue)
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Notifications")
                            .font(AppTypography.bodyMedium(.medium))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Allow the agent to send local notifications")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .tint(AppColors.signalMercury)
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }
    }

    private func retentionLabel(days: Int) -> String {
        days == 0 ? "Never" : "\(days)d"
    }

    private func intervalLabel(seconds: Int) -> String {
        if seconds < 3600 {
            return "\(max(1, seconds / 60))m"
        }
        let hours = Double(seconds) / 3600.0
        return hours < 24 ? String(format: "%.1fh", hours) : String(format: "%.0fh", hours)
    }
}

// MARK: - Memory Type Info Row

struct MemoryTypeInfo: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MemorySettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
