//
//  CreateImageSheet.swift
//  Axon
//
//  Studio-style sheet for generating images via OpenAI GPT-Image.
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
        #if os(macOS)
        sheetContent
            .frame(minWidth: 520, idealWidth: 580, minHeight: 560, idealHeight: 680)
            .sheet(isPresented: $showDetailSheet) {
                Group {
                if let item = generatedItem { CreativeItemDetailView(item: item) }

                }
                .appSheetMaterial()
}
        #else
        sheetContent
            .navigationTitle("Image Studio")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDetailSheet) {
                Group {
                if let item = generatedItem { CreativeItemDetailView(item: item) }

                }
                .appSheetMaterial()
}
        #endif
    }

    private var sheetContent: some View {
        ZStack(alignment: .top) {
            AppColors.substratePrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Hero banner
                    heroBanner

                    // Form content
                    VStack(spacing: 20) {
                        #if os(macOS)
                        HStack {
                            Spacer()
                            Button("Cancel") { dismiss() }
                                .foregroundColor(AppColors.textSecondary)
                                .font(AppTypography.bodySmall())
                        }
                        .padding(.top, 4)
                        #endif

                        // Prompt field — the centerpiece
                        promptSection

                        // Size selector
                        sizeSection

                        // Quality selector
                        qualitySection

                        // Cost + Generate
                        bottomSection

                        // Error
                        if let error = errorMessage {
                            errorBanner(error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Hero Banner

    private var heroBanner: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient background
            LinearGradient(
                colors: [
                    AppColors.signalMercury.opacity(0.85),
                    AppColors.signalMercuryDark.opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 120)

            // Decorative orbs
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 140, height: 140)
                .offset(x: -30, y: -20)
            Circle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 90, height: 90)
                .offset(x: UIScreen_width - 60, y: 10)

            // Content
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                        Text("Image Studio")
                            .font(AppTypography.titleMedium(.semibold))
                            .foregroundColor(.white)
                    }
                    Text("Powered by ChatGPT Image")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()

                // Aspect ratio preview
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: aspectPreviewW, height: aspectPreviewH)
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selectedSize)
    }

    private var aspectPreviewW: CGFloat {
        switch selectedSize {
        case .landscape1536: return 52
        case .portrait1536:  return 36
        default:             return 44
        }
    }
    private var aspectPreviewH: CGFloat {
        switch selectedSize {
        case .landscape1536: return 36
        case .portrait1536:  return 52
        default:             return 44
        }
    }

    private var UIScreen_width: CGFloat {
        #if os(iOS)
        return UIScreen.main.bounds.width
        #else
        return 580
        #endif
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Prompt", systemImage: "text.cursor")
                    .font(AppTypography.labelMedium(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                if !prompt.isEmpty {
                    Text("\(prompt.count) chars")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            ZStack(alignment: .topLeading) {
                // Placeholder
                if prompt.isEmpty {
                    Text("Describe what you'd like to create…\ne.g. A misty mountain valley at dawn, cinematic light, photorealistic")
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $prompt)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(12)
            }
            .background(AppColors.substrateSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        prompt.isEmpty ? AppColors.glassBorder : AppColors.signalMercury.opacity(0.4),
                        lineWidth: 1.5
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: prompt.isEmpty)
        }
        .padding(.top, 20)
    }

    // MARK: - Size Section

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Aspect Ratio", systemImage: "aspectratio")
                .font(AppTypography.labelMedium(.semibold))
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 10) {
                AspectRatioTile(
                    label: "Square",
                    ratio: "1:1",
                    width: 1, height: 1,
                    isSelected: selectedSize == .square1024
                ) { selectedSize = .square1024 }

                AspectRatioTile(
                    label: "Landscape",
                    ratio: "3:2",
                    width: 3, height: 2,
                    isSelected: selectedSize == .landscape1536
                ) { selectedSize = .landscape1536 }

                AspectRatioTile(
                    label: "Portrait",
                    ratio: "2:3",
                    width: 2, height: 3,
                    isSelected: selectedSize == .portrait1536
                ) { selectedSize = .portrait1536 }
            }
        }
    }

    // MARK: - Quality Section

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quality", systemImage: "dial.high")
                .font(AppTypography.labelMedium(.semibold))
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 0) {
                ForEach([ImageQuality.auto, .low, .medium, .high], id: \.self) { q in
                    QualitySegment(
                        label: q.rawValue.capitalized,
                        isSelected: selectedQuality == q,
                        isFirst: q == .auto,
                        isLast: q == .high
                    ) { selectedQuality = q }
                }
            }
            .background(AppColors.substrateSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.glassBorder, lineWidth: 1)
            )

            // Quality description
            Text(qualityDescription)
                .font(.system(size: 11))
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 2)
                .animation(.none, value: selectedQuality)
        }
    }

    private var qualityDescription: String {
        switch selectedQuality {
        case .auto:   return "Automatically balances quality and generation speed."
        case .low:    return "Fastest generation, lower detail — good for quick previews."
        case .medium: return "Good balance of quality and speed for most uses."
        case .high:   return "Maximum detail and fidelity — takes slightly longer."
        }
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: 14) {
            // Cost pill
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textTertiary)
                Text("Est. \(MediaCostEstimator.formattedCost(estimatedCost))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Text("~10–30s")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 2)

            // Generate button
            Button { generateImage() } label: {
                HStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(isGenerating ? "Generating…" : "Generate Image")
                        .font(AppTypography.bodyMedium(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Group {
                        if prompt.isEmpty || isGenerating {
                            AnyView(AppColors.substrateTertiary)
                        } else {
                            AnyView(
                                LinearGradient(
                                    colors: [AppColors.signalMercury, AppColors.signalMercuryDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        }
                    }
                )
                .foregroundColor(prompt.isEmpty || isGenerating ? AppColors.textTertiary : .white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(
                    color: prompt.isEmpty ? .clear : AppColors.signalMercury.opacity(0.35),
                    radius: 10, x: 0, y: 5
                )
            }
            .disabled(prompt.isEmpty || isGenerating)
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: prompt.isEmpty)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.accentError)
                .font(.system(size: 14))
            Text(error)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.accentError)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentError.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.accentError.opacity(0.2), lineWidth: 1)
        )
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
                    CostService.shared.recordImageGeneration(quality: selectedQuality, size: selectedSize)
                    generatedItem = item
                    isGenerating = false
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

// MARK: - Aspect Ratio Tile

private struct AspectRatioTile: View {
    let label: String
    let ratio: String
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let action: () -> Void

    private var normalizedW: CGFloat {
        let max = Swift.max(width, height)
        return (width / max) * 36
    }
    private var normalizedH: CGFloat {
        let max = Swift.max(width, height)
        return (height / max) * 36
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Aspect ratio visual
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? AppColors.signalMercury.opacity(0.2) : AppColors.substrateTertiary)
                        .frame(width: normalizedW + 8, height: normalizedH + 8)
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isSelected ? AppColors.signalMercury : AppColors.textTertiary,
                            lineWidth: isSelected ? 2 : 1.5
                        )
                        .frame(width: normalizedW, height: normalizedH)
                }
                .frame(width: 52, height: 52)

                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                    Text(ratio)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? AppColors.signalMercury.opacity(0.8) : AppColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.08) : AppColors.substrateSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? AppColors.signalMercury.opacity(0.5) : AppColors.glassBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
    }
}

// MARK: - Quality Segment

private struct QualitySegment: View {
    let label: String
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? AppColors.signalMercury : Color.clear)
                        .padding(3)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
    }
}

#Preview {
    CreateImageSheet()
}
