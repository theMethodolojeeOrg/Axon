//
//  MemoryTypeInfo.swift
//  Axon
//
//  Memory type info row component
//

import SwiftUI

struct MemoryTypeInfo: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(AppColors.substrateSecondary)
        .cornerRadius(8)
    }
}
