import SwiftUI

struct CostsBreakdownView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var costService = CostService.shared

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("This Month")) {
                    ForEach(Array(costService.monthlyTotalsUSD.keys), id: \.self) { provider in
                        let monthTotal = costService.monthlyTotalsUSD[provider] ?? 0
                        let todayTotal = costService.todaysTotalsUSD[provider] ?? 0
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(provider.displayName)
                                    .font(AppTypography.titleSmall())
                                    .foregroundColor(AppColors.textPrimary)
                                if todayTotal > 0 {
                                    Text("Today: $" + String(format: "%.2f", todayTotal))
                                        .font(AppTypography.bodySmall())
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                            Spacer()
                            Text("$" + String(format: "%.2f", monthTotal))
                                .font(AppTypography.titleSmall())
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Costs")
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
    }
}

#Preview {
    CostsBreakdownView()
}
