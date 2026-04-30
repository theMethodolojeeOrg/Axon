//
//  ContextUsageSection.swift
//  Axon
//
//  Displays context window usage for the current conversation
//

import SwiftUI
import Combine

struct ContextUsageSection: View {
    let model: UnifiedModel?
    let estimatedTokens: Int
    
    var body: some View {
        ChatInfoSection(title: "Context Usage") {
            if let model = model {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("This Conversation")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                        
                        Spacer()
                        
                        Text("\(ProviderModelHelpers.formatNumber(estimatedTokens)) / \(ProviderModelHelpers.formatNumber(model.contextWindow))")
                            .font(AppTypography.bodySmall(.medium))
                            .foregroundColor(AppColors.textPrimary)
                    }
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppSurfaces.color(.controlBackground))
                                .frame(height: 12)
                            
                            // Fill
                            RoundedRectangle(cornerRadius: 8)
                                .fill(progressColor)
                                .frame(width: geometry.size.width * progressPercentage, height: 12)
                        }
                    }
                    .frame(height: 12)
                    
                    Text("\(formattedProgressPercentage) of context window used")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding()
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var progressPercentage: Double {
        guard let model = model else { return 0 }
        guard model.contextWindow > 0 else { return 0 }
        return min(Double(estimatedTokens) / Double(model.contextWindow), 1.0)
    }
    
    private var formattedProgressPercentage: String {
        let percent = progressPercentage * 100
        if percent == 0 {
            return "0%"
        } else if percent < 1 {
            return "<1%"
        } else {
            return "\(Int(round(percent)))%"
        }
    }
    
    private var progressColor: Color {
        let percentage = progressPercentage
        if percentage < 0.5 {
            return AppColors.accentSuccess
        } else if percentage < 0.8 {
            return AppColors.accentWarning
        } else {
            return AppColors.accentError
        }
    }
}
