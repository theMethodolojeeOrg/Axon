//
//  CostInfoSection.swift
//  Axon
//
//  Displays cost information for the current month
//

import SwiftUI

struct CostInfoSection: View {
    @ObservedObject var costService = CostService.shared
    
    var body: some View {
        ChatInfoSection(title: "Costs") {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("This Month")
                            .font(AppTypography.bodySmall())
                            .foregroundColor(AppColors.textSecondary)
                        Text(costService.totalThisMonthUSDFriendly)
                            .font(AppTypography.titleMedium())
                            .foregroundColor(AppColors.textPrimary)
                    }
                    
                    Spacer()
                    
                    #if !os(macOS)
                    NavigationLink(destination: CostsBreakdownView()) {
                        HStack(spacing: 6) {
                            Text("View Details")
                                .font(AppTypography.bodySmall())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(AppColors.signalMercury)
                    }
                    #endif
                }
                .padding()
                .background(AppColors.substrateSecondary)
                .cornerRadius(8)
            }
        }
    }
}

#Preview {
    CostInfoSection()
        .padding()
        .background(AppColors.substratePrimary)
}
