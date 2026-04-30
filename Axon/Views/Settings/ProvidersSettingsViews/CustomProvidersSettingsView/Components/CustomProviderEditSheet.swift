//
//  CustomProviderEditSheet.swift
//  Axon
//
//  Sheet for adding/editing custom providers
//

import SwiftUI

struct CustomProviderEditSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    let existingProvider: CustomProviderConfig?
    let onDismiss: () -> Void

    @State private var providerName: String = ""
    @State private var apiEndpoint: String = ""
    @State private var models: [CustomModelConfig] = []
    @State private var validationError: String?

    var isEditing: Bool { existingProvider != nil }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Provider Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Provider Information")
                            .font(AppTypography.headlineSmall())
                            .foregroundColor(AppColors.textPrimary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Provider Name")
                                .font(AppTypography.bodySmall(.medium))
                                .foregroundColor(AppColors.textSecondary)
                            TextField("e.g., LocalLM", text: $providerName)
                                .textFieldStyle(CustomTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Endpoint")
                                .font(AppTypography.bodySmall(.medium))
                                .foregroundColor(AppColors.textSecondary)
                            TextField("https://openrouter.ai/api/v1", text: $apiEndpoint)
                                .textFieldStyle(CustomTextFieldStyle())
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                            Text("Paste the full endpoint URL - /chat/completions will be handled automatically")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }

                    Divider()
                        .background(AppColors.divider)

                    // Models Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Models")
                                .font(AppTypography.headlineSmall())
                                .foregroundColor(AppColors.textPrimary)
                            Spacer()
                            Button(action: addModel) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Model")
                                }
                                .font(AppTypography.bodySmall(.medium))
                                .foregroundColor(AppColors.signalMercury)
                            }
                        }

                        if models.isEmpty {
                            Text("Add at least one model to continue")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(AppSurfaces.color(.cardBackground))
                                .cornerRadius(8)
                        } else {
                            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                                ModelEditRow(
                                    model: binding(for: model),
                                    onDelete: { deleteModel(at: index) }
                                )
                            }
                        }
                    }

                    if let error = validationError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.accentError)
                            Text(error)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.accentError)
                        }
                        .padding()
                        .background(AppColors.accentError.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .background(AppSurfaces.color(.contentBackground))
            .navigationTitle(isEditing ? "Edit Provider" : "Add Provider")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem {
                    Button("Save") {
                        saveProvider()
                    }
                    .disabled(!isValid)
                }
                #else
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveProvider()
                    }
                    .disabled(!isValid)
                }
                #endif
            }
        }
        #if os(macOS)
        // Prevent overly compact sheets on macOS.
        .frame(minWidth: 550, idealWidth: 650, minHeight: 600, idealHeight: 750)
        #endif
        .onAppear {
            if let provider = existingProvider {
                providerName = provider.providerName
                apiEndpoint = provider.apiEndpoint
                models = provider.models
            } else {
                // Start with one empty model
                models = [CustomModelConfig(modelCode: "")]
            }
        }
    }

    private func binding(for model: CustomModelConfig) -> Binding<CustomModelConfig> {
        guard let index = models.firstIndex(where: { $0.id == model.id }) else {
            fatalError("Model not found")
        }
        return Binding(
            get: { models[index] },
            set: { models[index] = $0 }
        )
    }

    private func addModel() {
        models.append(CustomModelConfig(modelCode: ""))
    }

    private func deleteModel(at index: Int) {
        models.remove(at: index)
    }

    private var isValid: Bool {
        !providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !models.isEmpty &&
        models.allSatisfy { !$0.modelCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } &&
        !hasInvalidMimePatterns
    }

    private var hasInvalidMimePatterns: Bool {
        models.contains {
            !AttachmentMimePolicyService.invalidMimePatterns($0.acceptedAttachmentMimeTypes ?? []).isEmpty
        }
    }

    private func saveProvider() {
        validationError = nil

        // Validate URL
        guard let url = URL(string: apiEndpoint), url.scheme == "https" else {
            validationError = "API endpoint must be a valid HTTPS URL"
            return
        }

        // Validate model codes are unique
        let modelCodes = models.map { $0.modelCode.trimmingCharacters(in: .whitespacesAndNewlines) }
        let uniqueCodes = Set(modelCodes)
        if modelCodes.count != uniqueCodes.count {
            validationError = "Model codes must be unique within this provider"
            return
        }

        // Validate configured MIME patterns
        for model in models {
            let invalid = AttachmentMimePolicyService.invalidMimePatterns(model.acceptedAttachmentMimeTypes ?? [])
            if !invalid.isEmpty {
                validationError = "Model '\(model.modelCode)' has invalid MIME pattern(s): \(invalid.joined(separator: ", "))"
                return
            }
        }

        let normalizedModels: [CustomModelConfig] = models.map { model in
            var normalized = model
            let patterns = AttachmentMimePolicyService.normalizeMimePatterns(model.acceptedAttachmentMimeTypes ?? [])
            normalized.acceptedAttachmentMimeTypes = patterns.isEmpty ? nil : patterns
            return normalized
        }

        // Create or update provider
        let config = CustomProviderConfig(
            id: existingProvider?.id ?? UUID(),
            providerName: providerName.trimmingCharacters(in: .whitespacesAndNewlines),
            apiEndpoint: apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            models: normalizedModels
        )

        // Persist colors to ModelColorRegistry for models that have custom colors
        for model in normalizedModels {
            let modelKey = "custom_\(model.id.uuidString)"
            if let colorHex = model.colorHex {
                // User selected a custom color - persist it
                ModelColorRegistry.shared.override(key: modelKey, with: colorHex)
            }
            // If no colorHex, the registry will auto-assign when the model is first used
        }

        Task {
            if isEditing {
                await viewModel.updateCustomProvider(config)
            } else {
                await viewModel.addCustomProvider(config)
            }
            onDismiss()
        }
    }
}
