//
//  MasterLogToggle.swift
//  Axon
//
//  Master toggle for enabling/disabling debug logging.
//

import SwiftUI

struct MasterLogToggle: View {
    @Binding var isEnabled: Bool
    let enabledCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isEnabled ? "ant.fill" : "ant")
                .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textSecondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text("Debug Logging")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text(isEnabled ? "\(enabledCount)/\(totalCount) categories active" : "Enable to see detailed logs in console")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(isEnabled ? AppColors.signalMercury : AppColors.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(AppColors.signalMercury)
        }
        .padding()
    }
}

#Preview {
    MasterLogToggle(
        isEnabled: .constant(true),
        enabledCount: 8,
        totalCount: 12
    )
}
