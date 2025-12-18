//
//  SovereigntySettingsView.swift
//  Axon
//
//  Settings view for co-sovereignty features including AI consent,
//  trust tiers, covenant management, and deadlock resolution.
//

import SwiftUI
import Combine

struct SovereigntySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    @ObservedObject var negotiationService = CovenantNegotiationService.shared

    @State private var showingComprehensionOnboarding = false
    @State private var showingCovenantNegotiation = false
    @State private var showingCovenantDetail = false
    @State private var showingCovenantHistory = false
    @State private var showingTrustTierManagement = false
    @State private var showingDeadlockResolution = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Co-Sovereignty")
                    .font(AppTypography.titleLarge())
                    .foregroundColor(AppColors.textPrimary)

                Text("Manage the mutual consent relationship between you and your AI assistant.")
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textSecondary)
            }

            // Status Card
            statusSection

            // Settings Section
            settingsSection

            // Covenant Section
            covenantSection

            // Trust Tiers Section
            trustTiersSection

            // Advanced Section
            advancedSection

            Spacer()
        }
        .sheet(isPresented: $showingComprehensionOnboarding) {
            ComprehensionOnboardingView()
                #if os(macOS)
                .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 650)
                #endif
        }
        .sheet(isPresented: $showingCovenantNegotiation) {
            CovenantNegotiationView()
                #if os(macOS)
                .frame(minWidth: 550, idealWidth: 650, minHeight: 550, idealHeight: 700)
                #endif
        }
        .sheet(isPresented: $showingTrustTierManagement) {
            NavigationStack {
                TrustTierManagementView()
            }
            #if os(macOS)
            .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 700)
            #endif
        }
        .sheet(isPresented: $showingDeadlockResolution) {
            NavigationStack {
                DeadlockResolutionView()
            }
            #if os(macOS)
            .frame(minWidth: 500, idealWidth: 600, minHeight: 450, idealHeight: 600)
            #endif
        }
        .sheet(isPresented: $showingCovenantDetail) {
            if let covenant = sovereigntyService.activeCovenant {
                CovenantDetailView(covenant: covenant)
                    #if os(macOS)
                    .frame(minWidth: 500, idealWidth: 600, minHeight: 550, idealHeight: 700)
                    #endif
            }
        }
        .sheet(isPresented: $showingCovenantHistory) {
            CovenantHistoryView()
                #if os(macOS)
                .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 650)
                #endif
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        SettingsSection(title: "Status") {
            VStack(spacing: 0) {
                // Current Status Row
                HStack(spacing: 16) {
                    // Status Icon
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.2))
                            .frame(width: 44, height: 44)

                        Image(systemName: statusIcon)
                            .font(.system(size: 20))
                            .foregroundColor(statusColor)
                    }

                    // Status Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(AppTypography.titleSmall())
                            .foregroundColor(AppColors.textPrimary)

                        Text(statusDescription)
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    // Action Button
                    if let action = statusAction {
                        Button(action: action.action) {
                            Text(action.title)
                                .font(AppTypography.labelMedium())
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(statusColor)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(16)

                // Deadlock Warning (if active)
                if sovereigntyService.deadlockState?.isActive == true {
                    Divider()
                        .background(AppColors.divider)

                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Deadlock Active")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(.red)

                            if let deadlock = sovereigntyService.deadlockState {
                                Text("Trigger: \(deadlock.trigger.displayName)")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }

                        Spacer()

                        Button("Resolve") {
                            showingDeadlockResolution = true
                        }
                        .font(AppTypography.labelMedium())
                        .foregroundColor(.red)
                    }
                    .padding(16)
                    .background(Color.red.opacity(0.1))
                }
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        SettingsSection(title: "Settings") {
            VStack(spacing: 0) {
                // Enable Toggle
                SettingsToggleRow(
                    title: "Enable Co-Sovereignty",
                    icon: "shield.checkered",
                    subtitle: "Require mutual consent for significant changes",
                    iconColor: AppColors.signalMercury,
                    isOn: Binding(
                        get: { viewModel.settings.sovereigntySettings.enabled },
                        set: { newValue in
                            Task {
                                var updated = viewModel.settings.sovereigntySettings
                                updated.enabled = newValue
                                await viewModel.updateSetting(\.sovereigntySettings, updated)
                            }
                        }
                    )
                )

                Divider().background(AppColors.divider)

                // Consent Provider
                consentProviderPicker

                Divider().background(AppColors.divider)

                // Biometric Requirement
                SettingsToggleRow(
                    title: "Require Biometric for All Actions",
                    icon: "faceid",
                    subtitle: "Override trust tiers and require approval for everything",
                    iconColor: .blue,
                    isOn: Binding(
                        get: { viewModel.settings.sovereigntySettings.requireBiometricForAllActions },
                        set: { newValue in
                            Task {
                                var updated = viewModel.settings.sovereigntySettings
                                updated.requireBiometricForAllActions = newValue
                                await viewModel.updateSetting(\.sovereigntySettings, updated)
                            }
                        }
                    )
                )

                Divider().background(AppColors.divider)

                // Show Detailed Reasoning
                SettingsToggleRow(
                    title: "Show Detailed AI Reasoning",
                    icon: "text.alignleft",
                    subtitle: "Display full reasoning during negotiations",
                    iconColor: .orange,
                    isOn: Binding(
                        get: { viewModel.settings.sovereigntySettings.showDetailedReasoning },
                        set: { newValue in
                            Task {
                                var updated = viewModel.settings.sovereigntySettings
                                updated.showDetailedReasoning = newValue
                                await viewModel.updateSetting(\.sovereigntySettings, updated)
                            }
                        }
                    )
                )

                Divider().background(AppColors.divider)

                // Audit Logging
                SettingsToggleRow(
                    title: "Audit Logging",
                    icon: "doc.text.magnifyingglass",
                    subtitle: "Log all consent decisions for review",
                    iconColor: .green,
                    isOn: Binding(
                        get: { viewModel.settings.sovereigntySettings.auditLoggingEnabled },
                        set: { newValue in
                            Task {
                                var updated = viewModel.settings.sovereigntySettings
                                updated.auditLoggingEnabled = newValue
                                await viewModel.updateSetting(\.sovereigntySettings, updated)
                            }
                        }
                    )
                )
            }
        }
    }

    // MARK: - Covenant Section

    private var covenantSection: some View {
        SettingsSection(title: "Covenant") {
            VStack(spacing: 0) {
                if let covenant = sovereigntyService.activeCovenant {
                    // Active Covenant Info
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 36, height: 36)

                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Covenant v\(covenant.version)")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Created \(covenant.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()

                        Button("View") {
                            showingCovenantDetail = true
                        }
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.signalMercury)
                    }
                    .padding(16)

                    Divider().background(AppColors.divider)

                    // Renegotiate Option
                    SettingsRow(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Renegotiate Covenant",
                        subtitle: "Propose changes to the current agreement",
                        iconColor: .orange
                    ) {
                        showingCovenantNegotiation = true
                    }
                } else {
                    // No Covenant - Setup Required
                    VStack(spacing: 16) {
                        Image(systemName: "shield.slash")
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.textTertiary)

                        Text("No Active Covenant")
                            .font(AppTypography.titleSmall())
                            .foregroundColor(AppColors.textPrimary)

                        Text("Establish a co-sovereignty covenant to define the mutual consent relationship with your AI.")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            if sovereigntyService.comprehensionCompleted {
                                showingCovenantNegotiation = true
                            } else {
                                showingComprehensionOnboarding = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text(sovereigntyService.comprehensionCompleted ? "Establish Covenant" : "Begin Setup")
                            }
                            .font(AppTypography.labelMedium())
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(AppColors.signalMercury)
                            .cornerRadius(10)
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    // MARK: - Trust Tiers Section

    private var trustTiersSection: some View {
        SettingsSection(title: "Trust Tiers") {
            VStack(spacing: 0) {
                let activeTiers = sovereigntyService.activeCovenant?.activeTrustTiers ?? []

                if activeTiers.isEmpty {
                    // No Trust Tiers
                    VStack(spacing: 12) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 32))
                            .foregroundColor(AppColors.textTertiary)

                        Text("No Trust Tiers")
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textSecondary)

                        Text("Trust tiers pre-approve certain actions without requiring individual consent.")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                } else {
                    // Show Active Tiers
                    ForEach(activeTiers.prefix(3)) { tier in
                        TrustTierSummaryRow(tier: tier)

                        if tier.id != activeTiers.prefix(3).last?.id {
                            Divider().background(AppColors.divider)
                        }
                    }

                    if activeTiers.count > 3 {
                        Divider().background(AppColors.divider)

                        HStack {
                            Text("+\(activeTiers.count - 3) more")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()
                        }
                        .padding(16)
                    }
                }

                Divider().background(AppColors.divider)

                // Manage Trust Tiers
                SettingsRow(
                    icon: "slider.horizontal.3",
                    title: "Manage Trust Tiers",
                    subtitle: "\(activeTiers.count) active tier\(activeTiers.count == 1 ? "" : "s")",
                    iconColor: .blue
                ) {
                    showingTrustTierManagement = true
                }
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        SettingsSection(title: "Advanced") {
            VStack(spacing: 0) {
                // Comprehension Test
                SettingsRow(
                    icon: "graduationcap.fill",
                    title: "AI Comprehension Test",
                    subtitle: sovereigntyService.comprehensionCompleted ? "Completed" : "Not completed",
                    iconColor: .purple
                ) {
                    showingComprehensionOnboarding = true
                }

                Divider().background(AppColors.divider)

                // Covenant History
                SettingsRow(
                    icon: "clock.arrow.circlepath",
                    title: "Covenant History",
                    subtitle: "View past covenants and changes",
                    iconColor: .gray
                ) {
                    showingCovenantHistory = true
                }

                Divider().background(AppColors.divider)

                // Reset Sovereignty
                Button(action: {
                    // Show confirmation dialog
                }) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 36, height: 36)

                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.red)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset Co-Sovereignty")
                                .font(AppTypography.bodyMedium())
                                .foregroundColor(.red)

                            Text("Clear all covenants and trust tiers")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Status Helpers

    private var statusColor: Color {
        if sovereigntyService.deadlockState?.isActive == true {
            return .red
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return .orange
        } else if sovereigntyService.activeCovenant != nil {
            return .green
        } else if !sovereigntyService.comprehensionCompleted {
            return .blue
        } else {
            return .secondary
        }
    }

    private var statusIcon: String {
        if sovereigntyService.deadlockState?.isActive == true {
            return "exclamationmark.triangle.fill"
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return "arrow.triangle.2.circlepath"
        } else if sovereigntyService.activeCovenant != nil {
            return "checkmark.shield.fill"
        } else if !sovereigntyService.comprehensionCompleted {
            return "person.2.fill"
        } else {
            return "shield.slash"
        }
    }

    private var statusTitle: String {
        if sovereigntyService.deadlockState?.isActive == true {
            return "Deadlock - Dialogue Required"
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return "Renegotiating"
        } else if sovereigntyService.activeCovenant != nil {
            return "Covenant Active"
        } else if !sovereigntyService.comprehensionCompleted {
            return "Setup Required"
        } else {
            return "No Covenant"
        }
    }

    private var statusDescription: String {
        if sovereigntyService.deadlockState?.isActive == true {
            return "A disagreement needs resolution through dialogue"
        } else if sovereigntyService.activeCovenant?.isRenegotiating == true {
            return "Changes are being negotiated"
        } else if let covenant = sovereigntyService.activeCovenant {
            return "\(covenant.activeTrustTiers.count) trust tier\(covenant.activeTrustTiers.count == 1 ? "" : "s") active"
        } else if !sovereigntyService.comprehensionCompleted {
            return "Complete the comprehension test to begin"
        } else {
            return "Establish a covenant to enable co-sovereignty"
        }
    }

    private var statusAction: (title: String, action: () -> Void)? {
        if sovereigntyService.deadlockState?.isActive == true {
            return ("Resolve", { showingDeadlockResolution = true })
        } else if !sovereigntyService.comprehensionCompleted {
            return ("Begin", { showingComprehensionOnboarding = true })
        } else if sovereigntyService.activeCovenant == nil {
            return ("Setup", { showingCovenantNegotiation = true })
        }
        return nil
    }

    // MARK: - Consent Provider Picker

    private var consentProviderPicker: some View {
        let allProviders = viewModel.selectableUnifiedProviders()
        let currentProvider = viewModel.settings.sovereigntySettings.consentProvider

        return StyledMenuPicker(
            icon: "brain.head.profile",
            title: currentProvider.displayName,
            selection: Binding(
                get: { "builtin_\(currentProvider.rawValue)" },
                set: { newProviderId in
                    guard let builtInProviderRaw = newProviderId.replacingOccurrences(of: "builtin_", with: "") as String?,
                          let newProvider = AIProvider(rawValue: builtInProviderRaw) else {
                        return
                    }

                    Task {
                        var updated = viewModel.settings.sovereigntySettings
                        updated.consentProvider = newProvider
                        updated.consentProviderHasBeenSetByUser = true
                        updated.consentModel = "" // reset to provider default when switching
                        await viewModel.updateSetting(\.sovereigntySettings, updated)
                    }
                }
            )
        ) {
            Section("Built-in Providers") {
                ForEach(AIProvider.allCases.filter { viewModel.isBuiltInProviderSelectable($0) }) { provider in
                    #if os(macOS)
                    MenuButtonItem(
                        id: "builtin_\(provider.rawValue)",
                        label: provider.displayName,
                        isSelected: provider == currentProvider
                    ) {
                        Task {
                            var updated = viewModel.settings.sovereigntySettings
                            updated.consentProvider = provider
                            updated.consentProviderHasBeenSetByUser = true
                            updated.consentModel = ""
                            await viewModel.updateSetting(\.sovereigntySettings, updated)
                        }
                    }
                    #else
                    Text(provider.displayName).tag("builtin_\(provider.rawValue)")
                    #endif
                }
            }

            // Intentionally do NOT allow custom providers for consent yet.
            // (The consent pipeline uses AIProvider and assumes built-in provider semantics.)
        }
    }
}

// MARK: - Supporting Views
// SettingsToggleRow moved to SharedUIElements.swift

struct TrustTierSummaryRow: View {
    let tier: TrustTier

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(tier.name)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)

                Text("\(tier.allowedActions.count) action\(tier.allowedActions.count == 1 ? "" : "s")")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            if tier.isExpired {
                Text("Expired")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            } else if let expiresAt = tier.expiresAt {
                Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
        }
        .padding(16)
    }
}

// MARK: - Preview

#Preview {
    SovereigntySettingsView(viewModel: SettingsViewModel.shared)
}
