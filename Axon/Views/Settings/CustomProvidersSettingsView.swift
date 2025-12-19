//
//  CustomProvidersSettingsView.swift
//  Axon
//
//  Custom provider configuration view for OpenAI-compatible endpoints
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct CustomProvidersSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingProviderSheet = false
    @State private var editingProvider: CustomProviderConfig?
    @State private var showingDeleteAlert = false
    @State private var providerToDelete: CustomProviderConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // MARK: - Info Banner

            InfoBanner(
                icon: "info.circle.fill",
                title: "Custom Providers",
                message: "Add OpenAI-compatible endpoints like Deepseek, local LLMs, or other providers. Configure API keys in the API Keys tab after adding a provider."
            )

            // MARK: - Provider List

            GeneralSettingsSection(title: "Configured Providers") {
                if viewModel.settings.customProviders.isEmpty {
                    EmptyStateView(
                        icon: "server.rack",
                        title: "No Custom Providers",
                        message: "Add a custom provider to get started"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(viewModel.settings.customProviders.enumerated()), id: \.element.id) { index, provider in
                            CustomProviderCard(
                                provider: provider,
                                providerIndex: index + 1,
                                onEdit: {
                                    editingProvider = provider
                                    showingProviderSheet = true
                                },
                                onDelete: {
                                    providerToDelete = provider
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
            }

            // MARK: - Add Provider Button

            Button(action: {
                editingProvider = nil
                showingProviderSheet = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)

                    Text("Add Custom Provider")
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AppColors.substrateSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppColors.signalMercury.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .sheet(isPresented: $showingProviderSheet) {
            CustomProviderEditSheet(
                viewModel: viewModel,
                existingProvider: editingProvider,
                onDismiss: {
                    showingProviderSheet = false
                    editingProvider = nil
                }
            )
        }
        .alert("Delete Provider", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let provider = providerToDelete {
                    Task {
                        await viewModel.deleteCustomProvider(id: provider.id)
                    }
                }
            }
        } message: {
            if let provider = providerToDelete {
                Text("Are you sure you want to delete '\(provider.providerName)'? This action cannot be undone and will also remove the associated API key.")
            }
        }
    }
}

// MARK: - Custom Provider Card

struct CustomProviderCard: View {
    let provider: CustomProviderConfig
    let providerIndex: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.providerName)
                        .font(AppTypography.bodyMedium(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text(provider.apiEndpoint)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Model count badge
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12))
                    Text("\(provider.models.count)")
                        .font(AppTypography.labelSmall())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.signalMercury.opacity(0.2))
                .cornerRadius(12)
                .foregroundColor(AppColors.signalMercury)

                // Actions menu
                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            // Expand/Collapse models
            if !provider.models.isEmpty {
                Button {
                    withAnimation {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text(isExpanded ? "Hide Models" : "Show Models")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.signalMercury)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    VStack(spacing: 8) {
                        ForEach(Array(provider.models.enumerated()), id: \.element.id) { modelIndex, model in
                            ModelInfoRow(
                                model: model,
                                providerIndex: providerIndex,
                                modelIndex: modelIndex + 1,
                                providerName: provider.providerName
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.substrateSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Model Info Row

struct ModelInfoRow: View {
    let model: CustomModelConfig
    let providerIndex: Int
    let modelIndex: Int
    let providerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.displayName(providerName: providerName))
                .font(AppTypography.bodySmall(.medium))
                .foregroundColor(AppColors.textPrimary)

            Text(model.modelCode)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

            Text(model.displayDescription(providerIndex: providerIndex, modelIndex: modelIndex))
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(
                    String(format: "%.0fK context", Double(model.contextWindow) / 1000),
                    systemImage: "brain.head.profile"
                )
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

                if let pricing = model.pricing {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                    Text(pricing.formattedPricing())
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(AppColors.substratePrimary)
        .cornerRadius(6)
    }
}

// MARK: - Info Banner

struct InfoBanner: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(AppColors.signalMercury)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(message)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(AppColors.signalMercury.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)

            Text(title)
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.textPrimary)

            Text(message)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}

// MARK: - Custom Provider Edit Sheet

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
                            TextField("https://api.example.com", text: $apiEndpoint)
                                .textFieldStyle(CustomTextFieldStyle())
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                            Text("Must be a valid HTTPS URL")
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
                                .background(AppColors.substrateSecondary)
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
            .background(AppColors.substratePrimary)
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
        .frame(minWidth: 500, idealWidth: 550, minHeight: 550, idealHeight: 650)
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
        models.allSatisfy { !$0.modelCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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

        // Create or update provider
        let config = CustomProviderConfig(
            id: existingProvider?.id ?? UUID(),
            providerName: providerName.trimmingCharacters(in: .whitespacesAndNewlines),
            apiEndpoint: apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            models: models
        )

        // Persist colors to ModelColorRegistry for models that have custom colors
        for model in models {
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

// MARK: - Model Edit Row

struct ModelEditRow: View {
    @Binding var model: CustomModelConfig
    let onDelete: () -> Void

    @State private var showAdvancedPricing = false
    @State private var selectedColor: Color = .gray
    @State private var showColorPicker = false
    @State private var colorValidationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with delete button
            HStack {
                Text("Model")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(AppColors.accentError)
                }
            }

            // Model Code (Required)
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Code *")
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textSecondary)
                TextField("e.g., llama-3.1-70b", text: $model.modelCode)
                    .textFieldStyle(CustomTextFieldStyle())
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            // Friendly Name (Optional)
            VStack(alignment: .leading, spacing: 6) {
                Text("Friendly Name (Optional)")
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textSecondary)
                TextField("e.g., Llama 3.1 70B", text: Binding(
                    get: { model.friendlyName ?? "" },
                    set: { model.friendlyName = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(CustomTextFieldStyle())
            }

            // Color Picker (Optional)
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Color (Optional)")
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textSecondary)
                
                HStack(spacing: 12) {
                    // Color preview circle
                    Circle()
                        .fill(currentColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .stroke(AppColors.glassBorder, lineWidth: 1)
                        )
                    
                    // Color picker button
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .onChange(of: selectedColor) { oldColor, newColor in
                            updateModelColor(newColor)
                        }
                    
                    Spacer()
                    
                    // Clear color button
                    if model.colorHex != nil {
                        Button(action: clearColor) {
                            Text("Auto-assign")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.signalMercury)
                        }
                    }
                }
                .padding(12)
                .background(AppColors.substratePrimary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
                
                if let error = colorValidationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(error)
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.accentWarning)
                }
                
                Text("Leave unset to auto-assign a unique color")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            // Context Window
            VStack(alignment: .leading, spacing: 6) {
                Text("Context Window (tokens)")
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textSecondary)
                TextField("128000", value: $model.contextWindow, format: .number)
                    .textFieldStyle(CustomTextFieldStyle())
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            // Description (Optional)
            VStack(alignment: .leading, spacing: 6) {
                Text("Description (Optional)")
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textSecondary)
                TextField("Brief description of this model", text: Binding(
                    get: { model.description ?? "" },
                    set: { model.description = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(CustomTextFieldStyle())
            }

            // Advanced Pricing (Collapsible)
            DisclosureGroup(
                isExpanded: $showAdvancedPricing,
                content: {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Input Price")
                                    .font(AppTypography.labelSmall(.medium))
                                    .foregroundColor(AppColors.textSecondary)
                                TextField("0.00", value: Binding(
                                    get: { model.pricing?.inputPerMTok ?? 0 },
                                    set: { newValue in
                                        if model.pricing == nil {
                                            model.pricing = CustomModelPricing(inputPerMTok: newValue, outputPerMTok: 0)
                                        } else {
                                            model.pricing?.inputPerMTok = newValue
                                        }
                                    }
                                ), format: .number)
                                .textFieldStyle(CustomTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Output Price")
                                    .font(AppTypography.labelSmall(.medium))
                                    .foregroundColor(AppColors.textSecondary)
                                TextField("0.00", value: Binding(
                                    get: { model.pricing?.outputPerMTok ?? 0 },
                                    set: { newValue in
                                        if model.pricing == nil {
                                            model.pricing = CustomModelPricing(inputPerMTok: 0, outputPerMTok: newValue)
                                        } else {
                                            model.pricing?.outputPerMTok = newValue
                                        }
                                    }
                                ), format: .number)
                                .textFieldStyle(CustomTextFieldStyle())
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cached Input Price (Optional)")
                                .font(AppTypography.labelSmall(.medium))
                                .foregroundColor(AppColors.textSecondary)
                            TextField("0.00", value: Binding(
                                get: { model.pricing?.cachedInputPerMTok ?? 0 },
                                set: { newValue in
                                    if model.pricing == nil {
                                        model.pricing = CustomModelPricing(inputPerMTok: 0, outputPerMTok: 0, cachedInputPerMTok: newValue)
                                    } else {
                                        model.pricing?.cachedInputPerMTok = newValue > 0 ? newValue : nil
                                    }
                                }
                            ), format: .number)
                            .textFieldStyle(CustomTextFieldStyle())
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        }

                        Text("Prices per 1M tokens in USD")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.top, 8)
                },
                label: {
                    Text("Advanced Pricing")
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.signalMercury)
                }
            )
            .accentColor(AppColors.signalMercury)
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
        .onAppear {
            initializeColor()
        }
    }
    
    // MARK: - Color Helpers
    
    private var currentColor: Color {
        if let hex = model.colorHex {
            return ModelColorRegistry.color(fromHex: hex)
        }
        return selectedColor
    }
    
    private func initializeColor() {
        if let hex = model.colorHex {
            selectedColor = ModelColorRegistry.color(fromHex: hex)
        } else {
            // Generate a preview color for display (muted pastel)
            selectedColor = Color(
                hue: Double.random(in: 0...1),
                saturation: Double.random(in: 0.3...0.6),
                brightness: Double.random(in: 0.4...0.7)
            )
        }
    }
    
    private func updateModelColor(_ color: Color) {
        colorValidationError = nil
        
        // Convert Color to hex
        let hex = colorToHex(color)
        
        // Validate the color isn't already taken
        if isColorTaken(hex) {
            colorValidationError = "This color is already used by another model"
            return
        }
        
        // Update model
        model.colorHex = hex
    }
    
    private func clearColor() {
        model.colorHex = nil
        colorValidationError = nil
        // Generate new preview color
        selectedColor = Color(
            hue: Double.random(in: 0...1),
            saturation: Double.random(in: 0.3...0.6),
            brightness: Double.random(in: 0.4...0.7)
        )
    }
    
    private func colorToHex(_ color: Color) -> String {
        // Convert SwiftUI Color to hex string (RRGGBB format)
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let r = UInt8(max(0, min(255, red * 255)))
        let g = UInt8(max(0, min(255, green * 255)))
        let b = UInt8(max(0, min(255, blue * 255)))

        return String(format: "%02X%02X%02X", r, g, b)
        #else
        // Fallback (macOS): Color-to-hex conversion is best-effort.
        // If we can't convert, return a safe default.
        return "808080"
        #endif
    }
    
    private func isColorTaken(_ hex: String) -> Bool {
        // Check if this hex is already assigned to a different model
        //let registry = ModelColorRegistry.shared
        
        // Get all existing color assignments
        // We can't directly access the registry's internal state, but we can check
        // by attempting to get colors for known model keys
        
        // For now, we'll do a simple check - in a production app, you might want
        // to expose a method in ModelColorRegistry to check if a color is taken
        
        // Check against reserved colors
        let reservedColors = ["0065FF", "10A37F"] // Anthropic blue, OpenAI green
        if reservedColors.contains(hex.uppercased()) {
            return true
        }
        
        return false
    }
}

// MARK: - Custom Text Field Style

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(AppColors.substratePrimary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.glassBorder, lineWidth: 1)
            )
            .font(AppTypography.bodyMedium())
            .foregroundColor(AppColors.textPrimary)
    }
}

// MARK: - Preview

#Preview {
    CustomProvidersSettingsView(viewModel: SettingsViewModel())
        .background(AppColors.substratePrimary)
}
