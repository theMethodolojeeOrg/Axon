//
//  ProviderSelectionSection.swift
//  Axon
//
//  Provider selection section for ChatInfoSettingsView
//

import SwiftUI

struct ChatProviderSelectionSection: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @ObservedObject var sovereigntyService = SovereigntyService.shared
    
    @Binding var selectedProvider: UnifiedProvider?
    @Binding var showingNegotiationSheet: Bool
    
    let onProviderSelected: (UnifiedProvider?) -> Void
    
    var body: some View {
        ChatInfoSection(title: "AI Provider") {
            let allProviders = settingsViewModel.selectableUnifiedProviders()
            let currentProvider = resolveCurrentProvider(from: allProviders)
            let isProviderChangeAllowed = sovereigntyService.isProviderChangeAllowed()
            let providerRestrictionReason = sovereigntyService.providerChangeRestrictionReason()
            
            // Show restriction banner if provider changes are restricted by covenant
            if !isProviderChangeAllowed, let reason = providerRestrictionReason {
                CovenantRestrictionBanner(
                    icon: "lock.shield",
                    message: reason,
                    actionLabel: "Renegotiate",
                    action: {
                        showingNegotiationSheet = true
                    }
                )
            }
            
            StyledMenuPicker(
                icon: currentProvider?.isCustom == true ? "server.rack" : "cpu.fill",
                title: currentProvider?.displayName ?? "Select Provider",
                selection: Binding(
                    get: { currentProvider?.id ?? "builtin_anthropic" },
                    set: { newProviderId in
                        if let provider = allProviders.first(where: { $0.id == newProviderId }) {
                            onProviderSelected(provider)
                        }
                    }
                )
            ) {
                #if os(macOS)
                macOSProviderMenu(allProviders: allProviders, currentProvider: currentProvider)
                #else
                iOSProviderMenu(allProviders: allProviders)
                #endif
            }
            .disabled(!isProviderChangeAllowed)
            .opacity(isProviderChangeAllowed ?1.0 : 0.6)
        }
    }
    
    // MARK: - Helpers
    
    private func resolveCurrentProvider(from allProviders: [UnifiedProvider]) -> UnifiedProvider? {
        let provider = selectedProvider ?? settingsViewModel.currentUnifiedProvider()
        
        return provider.flatMap { p in
            if allProviders.contains(where: { $0.id == p.id }) {
                return p
            }
            return settingsViewModel.fallbackUnifiedProvider()
        } ?? settingsViewModel.fallbackUnifiedProvider()
    }
    
    // MARK: - macOS Menu
    
    #if os(macOS)
    @ViewBuilder
    private func macOSProviderMenu(allProviders: [UnifiedProvider], currentProvider: UnifiedProvider?) -> some View {
        Section("Built-in Providers") {
            ForEach(AIProvider.allCases.filter { settingsViewModel.isBuiltInProviderSelectable($0) }) { provider in
                MenuButtonItem(
                    id: "builtin_\(provider.rawValue)",
                    label: provider.displayName,
                    isSelected: currentProvider?.id == "builtin_\(provider.rawValue)"
                ) {
                    if let unified = allProviders.first(where: { $0.id == "builtin_\(provider.rawValue)" }) {
                        onProviderSelected(unified)
                    }
                }
            }
        }
        
        let selectableCustomProviders = settingsViewModel.settings.customProviders.filter {
            settingsViewModel.isCustomProviderSelectable($0.id)
        }
        if !selectableCustomProviders.isEmpty {
            Section("Custom Providers") {
                ForEach(selectableCustomProviders) { provider in
                    MenuButtonItem(
                        id: "custom_\(provider.id.uuidString)",
                        label: provider.providerName,
                        isSelected: currentProvider?.id == "custom_\(provider.id.uuidString)"
                    ) {
                        if let unified = allProviders.first(where: { $0.id == "custom_\(provider.id.uuidString)" }) {
                            onProviderSelected(unified)
                        }
                    }
                }
            }
        }
    }
    #endif
    
    // MARK: - iOS Menu
    
    #if !os(macOS)
    @ViewBuilder
    private func iOSProviderMenu(allProviders: [UnifiedProvider]) -> some View {
        Section("Built-in Providers") {
            ForEach(AIProvider.allCases.filter { settingsViewModel.isBuiltInProviderSelectable($0) }) { provider in
                Text(provider.displayName).tag("builtin_\(provider.rawValue)")
            }
        }
        
        let selectableCustomProviders = settingsViewModel.settings.customProviders.filter {
            settingsViewModel.isCustomProviderSelectable($0.id)
        }
        if !selectableCustomProviders.isEmpty {
            Section("Custom Providers") {
                ForEach(selectableCustomProviders) { provider in
                    Text(provider.providerName).tag("custom_\(provider.id.uuidString)")
                }
            }
        }
    }
    #endif
}

#Preview {
    ChatProviderSelectionSection(
        settingsViewModel: SettingsViewModel(),
        selectedProvider: .constant(nil),
        showingNegotiationSheet: .constant(false),
        onProviderSelected: { _ in }
    )
    .padding()
    .background(AppSurfaces.color(.contentBackground))
}
