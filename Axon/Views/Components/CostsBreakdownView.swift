import SwiftUI

struct CostsBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var costService = CostService.shared

    var body: some View {
        NavigationView {
            List {
                // Total Summary
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total This Month")
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                            Text(costService.totalThisMonthUSDFriendly)
                                .font(AppTypography.titleLarge())
                                .foregroundColor(AppColors.textPrimary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Chat/API Costs
                Section(header: Text("Chat & API")) {
                    ForEach(Array(costService.monthlyTotalsUSD.keys).filter { 
                        (costService.monthlyTotalsUSD[$0] ?? 0) > 0 
                    }, id: \.self) { provider in
                        let monthTotal = costService.monthlyTotalsUSD[provider] ?? 0
                        let todayTotal = costService.todaysTotalsUSD[provider] ?? 0
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName)
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                if todayTotal > 0 {
                                    Text("Today: $" + String(format: "%.2f", todayTotal))
                                        .font(AppTypography.labelSmall())
                                        .foregroundColor(AppColors.textTertiary)
                                }
                            }
                            Spacer()
                            Text("$" + String(format: "%.2f", monthTotal))
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }
                    
                    if costService.chatCostThisMonthUSD == 0 {
                        Text("No chat costs yet")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                
                // Image Generation
                Section(header: Text("Image Generation")) {
                    if costService.monthlyImageCount > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("OpenAI Images")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                Text("\(costService.monthlyImageCount) image\(costService.monthlyImageCount == 1 ? "" : "s") generated")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                            Spacer()
                            Text("$" + String(format: "%.2f", costService.monthlyImageCostUSD))
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    } else {
                        Text("No images generated yet")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
                
                // Audio Generation
                Section(header: Text("Audio Generation")) {
                    if costService.monthlyTTSCount > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Text-to-Speech")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColors.textPrimary)
                                Text("\(costService.monthlyTTSCount) audio\(costService.monthlyTTSCount == 1 ? "" : "s") generated")
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textTertiary)
                            }
                            Spacer()
                            Text("$" + String(format: "%.2f", costService.monthlyTTSCostUSD))
                                .font(AppTypography.bodyMedium(.medium))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    } else {
                        Text("No audio generated yet")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Cost Breakdown")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.signalMercury)
                }
                #else
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppColors.signalMercury)
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 450, minHeight: 350, idealHeight: 450)
        #endif
    }
}

#Preview {
    CostsBreakdownView()
}

