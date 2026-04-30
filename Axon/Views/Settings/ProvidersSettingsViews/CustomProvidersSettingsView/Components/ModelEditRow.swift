//
//  ModelEditRow.swift
//  Axon
//
//  Model editing row with color picker and pricing options
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ModelEditRow: View {
    @Binding var model: CustomModelConfig
    let onDelete: () -> Void

    @State private var showAdvancedPricing = false
    @State private var selectedColor: Color = .gray
    @State private var showColorPicker = false
    @State private var colorValidationError: String?
    @State private var mimePatternsText: String = ""
    @State private var mimeValidationError: String?

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
                                .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
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
                .background(AppSurfaces.color(.contentBackground))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
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

            // MIME Types (Optional)
            VStack(alignment: .leading, spacing: 6) {
                Text("Accepted Attachment MIME Types (Optional)")
                    .font(AppTypography.labelSmall(.medium))
                    .foregroundColor(AppColors.textSecondary)

                TextEditor(text: $mimePatternsText)
                    .frame(minHeight: 74, maxHeight: 110)
                    .padding(8)
                    .background(AppSurfaces.color(.contentBackground))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppSurfaces.color(.cardBorder), lineWidth: 1)
                    )
                    .onChange(of: mimePatternsText) { _, newValue in
                        updateMimePatterns(from: newValue)
                    }

                if let error = mimeValidationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                        Text(error)
                            .font(AppTypography.labelSmall())
                    }
                    .foregroundColor(AppColors.accentWarning)
                }

                Text("Comma or newline separated. Examples: image/*, application/pdf, audio/mpeg")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
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
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
        .onAppear {
            initializeColor()
            initializeMimePatterns()
        }
        .onChange(of: model.acceptedAttachmentMimeTypes) { _, newValue in
            let normalizedText = (newValue ?? []).joined(separator: ", ")
            if normalizedText != mimePatternsText {
                mimePatternsText = normalizedText
            }
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

    private func initializeMimePatterns() {
        mimePatternsText = (model.acceptedAttachmentMimeTypes ?? []).joined(separator: ", ")
        updateMimePatterns(from: mimePatternsText)
    }

    private func updateMimePatterns(from text: String) {
        let patterns = AttachmentMimePolicyService.parseMimePatternInput(text)
        model.acceptedAttachmentMimeTypes = patterns.isEmpty ? nil : patterns

        let invalid = AttachmentMimePolicyService.invalidMimePatterns(patterns)
        if invalid.isEmpty {
            mimeValidationError = nil
        } else {
            mimeValidationError = "Invalid MIME pattern(s): \(invalid.joined(separator: ", "))"
        }
    }
}
