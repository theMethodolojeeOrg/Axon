//
//  DraftPreviewSheet.swift
//  Axon
//
//  Sheet for previewing a pending model catalog draft.
//

import SwiftUI

struct DraftPreviewSheet: View {
    let catalog: ModelCatalog?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let catalog = catalog {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Version \(catalog.version)")
                                .font(AppTypography.titleMedium())
                            Spacer()
                            Text(catalog.lastUpdated.formatted())
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding()

                        ForEach(catalog.providers) { provider in
                            ProviderSummaryRow(provider: provider)
                        }
                    }
                    .padding()
                } else {
                    Text("No draft available")
                        .foregroundColor(AppColors.textSecondary)
                        .padding()
                }
            }
            .background(Color.clear)
            .navigationTitle("Draft Preview")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        // Prevent overly compact sheets on macOS.
        .frame(minWidth: 500, idealWidth: 600, minHeight: 450, idealHeight: 600)
        #endif
    }
}
