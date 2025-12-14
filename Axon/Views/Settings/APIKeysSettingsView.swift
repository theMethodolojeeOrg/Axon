//
//  APIKeysSettingsView.swift
//  Axon
//
//  API Keys configuration with secure storage
//

import SwiftUI

struct APIKeysSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var selectedProvider: APIProvider? = nil
    @State private var selectedCustomProvider: CustomProviderConfig? = nil
    @State private var editingKeyValue = ""
    @State private var isSavingKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Info banner
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(AppColors.signalMercury)
                Text("API keys are encrypted and stored securely in your device's Keychain.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding()
            .background(AppColors.signalMercury.opacity(0.1))
            .cornerRadius(8)

            // AI Provider Keys Section
            SettingsSection(title: "AI Provider Keys") {
                VStack(spacing: 12) {
                    ForEach(APIProvider.allCases.filter { $0 != APIProvider.elevenlabs }) { provider in
                        APIKeyRow(
                            provider: provider,
                            isConfigured: viewModel.isAPIKeyConfigured(provider),
                            onEdit: {
                                editingKeyValue = viewModel.getAPIKey(provider) ?? ""
                                selectedProvider = provider
                            },
                            onClear: {
                                Task {
                                    await viewModel.clearAPIKey(provider)
                                }
                            },
                            onGetKey: {
                                if let url = provider.infoURL {
                                    AppURLRouter.open(url)
                                }
                            }
                        )
                    }
                }
            }

            // ElevenLabs Section
            SettingsSection(title: "Text-to-Speech") {
                VStack(spacing: 12) {
                    APIKeyRow(
                        provider: .elevenlabs,
                        isConfigured: viewModel.isAPIKeyConfigured(.elevenlabs),
                        onEdit: {
                            editingKeyValue = viewModel.getAPIKey(.elevenlabs) ?? ""
                            selectedProvider = .elevenlabs
                        },
                        onClear: {
                            Task {
                                await viewModel.clearAPIKey(.elevenlabs)
                            }
                        },
                        onGetKey: {
                            if let url = APIProvider.elevenlabs.infoURL {
                                AppURLRouter.open(url)
                            }
                        }
                    )
                }
            }

            // Custom Provider Keys Section
            if !viewModel.settings.customProviders.isEmpty {
                SettingsSection(title: "Custom Provider Keys") {
                    VStack(spacing: 12) {
                        ForEach(viewModel.settings.customProviders) { provider in
                            CustomProviderAPIKeyRow(
                                provider: provider,
                                isConfigured: viewModel.isCustomProviderConfigured(provider.id),
                                onEdit: {
                                    editingKeyValue = viewModel.getCustomProviderAPIKey(providerId: provider.id) ?? ""
                                    selectedCustomProvider = provider
                                },
                                onClear: {
                                    Task {
                                        await viewModel.clearCustomProviderAPIKey(providerId: provider.id, providerName: provider.providerName)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedProvider) { provider in
            APIKeyInputSheet(
                provider: provider,
                keyValue: $editingKeyValue,
                isSaving: isSavingKey,
                onSave: {
                    isSavingKey = true
                    Task {
                        await viewModel.saveAPIKey(editingKeyValue, for: provider)
                        isSavingKey = false
                        selectedProvider = nil
                    }
                },
                onCancel: {
                    selectedProvider = nil
                }
            )
        }
        .sheet(item: $selectedCustomProvider) { customProvider in
            CustomProviderAPIKeyInputSheet(
                provider: customProvider,
                keyValue: $editingKeyValue,
                onSave: {
                    Task {
                        await viewModel.saveCustomProviderAPIKey(editingKeyValue, providerId: customProvider.id, providerName: customProvider.providerName)
                        selectedCustomProvider = nil
                    }
                },
                onCancel: {
                    selectedCustomProvider = nil
                }
            )
        }
    }
}

// MARK: - API Key Row

struct APIKeyRow: View {
    let provider: APIProvider
    let isConfigured: Bool
    var isAdminKey: Bool = false
    let onEdit: () -> Void
    let onClear: () -> Void
    let onGetKey: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isAdminKey ? "key.fill" : "key.fill")
                    .foregroundColor(isAdminKey ? AppColors.signalCopper : AppColors.signalMercury)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.displayName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(provider.description)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.accentSuccess)
                            Text("Configured")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentSuccess)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(isAdminKey ? AppColors.accentError : AppColors.accentWarning)
                            Text(isAdminKey ? "Required" : "Not Configured")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(isAdminKey ? AppColors.accentError : AppColors.accentWarning)
                        }
                    }
                }

                Spacer()

                Menu {
                    Button(action: onEdit) {
                        Label(isConfigured ? "Edit Key" : "Add Key", systemImage: "pencil")
                    }

                    if isConfigured {
                        Button(role: .destructive, action: onClear) {
                            Label("Remove Key", systemImage: "trash")
                        }
                    }

                    Divider()

                    Button(action: onGetKey) {
                        Label("Get API Key", systemImage: "link")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(isAdminKey ? AppColors.signalCopper.opacity(0.05) : AppColors.substrateSecondary)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isAdminKey ? AppColors.signalCopper.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
    }
}

// MARK: - API Key Input Sheet

struct APIKeyInputSheet: View {
    let provider: APIProvider
    @Binding var keyValue: String
    var isSaving: Bool = false
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var isShowingKey = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter your \(provider.displayName) API key")
                                .font(AppTypography.headlineSmall())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Your API key will be encrypted and stored securely.")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        // Key Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            HStack {
                                if isShowingKey {
                                    TextField("Paste your API key", text: $keyValue)
                                        #if os(iOS)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        #endif
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(AppColors.textPrimary)
                                        .disabled(isSaving)
                                } else {
                                    SecureField("Paste your API key", text: $keyValue)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(AppColors.textPrimary)
                                        .disabled(isSaving)
                                }

                                Button(action: { isShowingKey.toggle() }) {
                                    Image(systemName: isShowingKey ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isSaving)
                            }
                            .padding()
                            .background(AppColors.substrateSecondary)
                            .cornerRadius(8)

                            Text("Expected format: \(provider.apiKeyPlaceholder)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }

                        // Saving indicator (sync destination depends on settings)
                        if isSaving {
                            let syncProvider = SettingsViewModel.shared.settings.deviceModeConfig.cloudSyncProvider
                            let destination: String = {
                                switch syncProvider {
                                case .iCloud: return "iCloud Keychain"
                                case .firestore: return "Custom Server"
                                case .none: return "device"
                                }
                            }()

                            HStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                                Text("Saving key to \(destination)...")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textSecondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(AppColors.signalMercury.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // Get Key Link
                        if let url = provider.infoURL {
                            Link(destination: url) {
                                HStack {
                                    Image(systemName: "link")
                                    Text("Get API key from \(provider.displayName)")
                                        .font(AppTypography.bodyMedium())
                                }
                                .foregroundColor(AppColors.signalMercury)
                            }
                            .disabled(isSaving)
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(provider.displayName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(AppColors.textSecondary)
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: AppColors.signalMercury))
                    } else {
                        Button("Save") {
                            onSave()
                        }
                        .disabled(keyValue.isEmpty)
                        .foregroundColor(keyValue.isEmpty ? AppColors.textDisabled : AppColors.signalMercury)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }
}

// MARK: - Custom Provider API Key Row

struct CustomProviderAPIKeyRow: View {
    let provider: CustomProviderConfig
    let isConfigured: Bool
    let onEdit: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.providerName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(provider.apiEndpoint)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.accentSuccess)
                            Text("Configured")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentSuccess)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(AppColors.accentWarning)
                            Text("Not Configured")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.accentWarning)
                        }
                    }
                }

                Spacer()

                Menu {
                    Button(action: onEdit) {
                        Label(isConfigured ? "Edit Key" : "Add Key", systemImage: "pencil")
                    }

                    if isConfigured {
                        Button(role: .destructive, action: onClear) {
                            Label("Remove Key", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
    }
}

// MARK: - Custom Provider API Key Input Sheet

struct CustomProviderAPIKeyInputSheet: View {
    let provider: CustomProviderConfig
    @Binding var keyValue: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var isShowingKey = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter your \(provider.providerName) API key")
                                .font(AppTypography.headlineSmall())
                                .foregroundColor(AppColors.textPrimary)

                            Text("Your API key will be encrypted and stored securely.")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }

                        // Provider Info Card
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "server.rack")
                                    .foregroundColor(AppColors.signalMercury)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Endpoint")
                                        .font(AppTypography.labelSmall(.medium))
                                        .foregroundColor(AppColors.textSecondary)
                                    Text(provider.apiEndpoint)
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textPrimary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding()
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(8)

                        // Key Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(AppTypography.labelMedium())
                                .foregroundColor(AppColors.textSecondary)

                            HStack {
                                if isShowingKey {
                                    TextField("Paste your API key", text: $keyValue)
                                        #if os(iOS)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        #endif
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(AppColors.textPrimary)
                                } else {
                                    SecureField("Paste your API key", text: $keyValue)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(AppColors.textPrimary)
                                }

                                Button(action: { isShowingKey.toggle() }) {
                                    Image(systemName: isShowingKey ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .padding()
                            .background(AppColors.substrateSecondary)
                            .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding()
                }
            }
            .navigationTitle(provider.providerName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(keyValue.isEmpty)
                    .foregroundColor(keyValue.isEmpty ? AppColors.textDisabled : AppColors.signalMercury)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        APIKeysSettingsView(viewModel: SettingsViewModel())
            .padding()
    }
    .background(AppColors.substratePrimary)
}
