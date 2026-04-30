//
//  ExportButtonRow.swift
//  Axon
//
//  Reusable export button row component
//

import SwiftUI

struct ExportButtonRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isExporting: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.signalMercury)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodySmall(.medium))
                        .foregroundColor(AppColors.textPrimary)
                    
                    Text(subtitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppSurfaces.color(.cardBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isExporting)
    }
}

#Preview {
    VStack(spacing: 12) {
        ExportButtonRow(
            title: "Export JSON",
            subtitle: "Full thread + metadata",
            systemImage: "doc.text",
            isExporting: false,
            action: {}
        )
        
        ExportButtonRow(
            title: "Export Markdown",
            subtitle: "Readable transcript",
            systemImage: "doc.plaintext",
            isExporting: true,
            action: {}
        )
    }
    .padding()
    .background(AppSurfaces.color(.contentBackground))
}
