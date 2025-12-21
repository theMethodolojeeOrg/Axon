//
//  CreateImageSheet.swift
//  Axon
//
//  Sheet for generating images via OpenAI GPT-Image.
//

import SwiftUI

struct CreateImageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var creationService = DirectMediaCreationService.shared
    
    @State private var prompt = ""
    @State private var selectedSize: ImageSize = .square1024
    @State private var selectedQuality: ImageQuality = .auto
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedItem: CreativeItem?
    @State private var showDetailSheet = false
    
    private var estimatedCost: Double {
        MediaCostEstimator.estimateImageCost(quality: selectedQuality, size: selectedSize)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Prompt input
                        promptSection
                        
                        // Options
                        optionsSection
                        
                        // Generate button
                        generateButton
                        
                        // Error display
                        if let error = errorMessage {
                            errorView(error)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Generate Image")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.textSecondary)
                }
            }
            .sheet(isPresented: $showDetailSheet) {
                if let item = generatedItem {
                    CreativeItemDetailView(item: item)
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 40))
                .foregroundColor(AppColors.signalMercury)
            
            Text("Create with ChatGPT Image")
                .font(AppTypography.titleMedium())
                .foregroundColor(AppColors.textPrimary)
            
            Text("Describe what you want to create")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.top)
    }
    
    // MARK: - Prompt Section
    
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(AppTypography.labelMedium())
                .foregroundColor(AppColors.textSecondary)
            
            TextEditor(text: $prompt)
                .font(AppTypography.bodyMedium())
                .foregroundColor(AppColors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 100)
                .padding(12)
                .background(AppColors.substrateSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
        }
    }
    
    // MARK: - Options Section
    
    private var optionsSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 16) {
                // Size picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Size")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textSecondary)
                    
                    VStack(spacing: 8) {
                        OptionRow(
                            title: "Square",
                            subtitle: "1024 × 1024",
                            isSelected: selectedSize == .square1024
                        ) { selectedSize = .square1024 }
                        
                        OptionRow(
                            title: "Landscape",
                            subtitle: "1536 × 1024",
                            isSelected: selectedSize == .landscape1536
                        ) { selectedSize = .landscape1536 }
                        
                        OptionRow(
                            title: "Portrait",
                            subtitle: "1024 × 1536",
                            isSelected: selectedSize == .portrait1536
                        ) { selectedSize = .portrait1536 }
                    }
                }
                
                Divider()
                    .background(AppColors.glassBorder)
                
                // Quality picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quality")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textSecondary)
                    
                    VStack(spacing: 8) {
                        OptionRow(
                            title: "Auto",
                            subtitle: "Balanced quality & speed",
                            isSelected: selectedQuality == .auto
                        ) { selectedQuality = .auto }
                        
                        OptionRow(
                            title: "Low",
                            subtitle: "Fastest, lower detail",
                            isSelected: selectedQuality == .low
                        ) { selectedQuality = .low }
                        
                        OptionRow(
                            title: "Medium",
                            subtitle: "Good balance",
                            isSelected: selectedQuality == .medium
                        ) { selectedQuality = .medium }
                        
                        OptionRow(
                            title: "High",
                            subtitle: "Best quality, slower",
                            isSelected: selectedQuality == .high
                        ) { selectedQuality = .high }
                    }
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)
            .cornerRadius(12)
            
            // Cost estimate
            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundColor(AppColors.textTertiary)
                Text("Estimated cost: \(MediaCostEstimator.formattedCost(estimatedCost))")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button {
            generateImage()
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                }
                
                Text(isGenerating ? "Generating..." : "Generate Image")
                    .font(AppTypography.bodyMedium(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(prompt.isEmpty || isGenerating ? AppColors.textTertiary : AppColors.signalMercury)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(prompt.isEmpty || isGenerating)
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)
            
            Text(error)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.accentError)
        }
        .padding()
        .background(AppColors.accentError.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func generateImage() {
        errorMessage = nil
        isGenerating = true
        
        Task {
            do {
                let item = try await creationService.generateImage(
                    prompt: prompt,
                    size: selectedSize,
                    quality: selectedQuality
                )
                
                await MainActor.run {
                    // Record cost
                    CostService.shared.recordImageGeneration(quality: selectedQuality, size: selectedSize)
                    generatedItem = item
                    isGenerating = false
                    // Automatically show the detail view
                    showDetailSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}

// MARK: - Option Row

private struct OptionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)
                    
                    Text(subtitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? AppColors.signalMercury.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreateImageSheet()
}
