//
//  DeveloperHeaderSection.swift
//  Axon
//
//  Header section for Developer Tools settings.
//

import SwiftUI

struct DeveloperHeaderSection: View {
    var body: some View {
        HStack {
            Image(systemName: "hammer.fill")
                .foregroundColor(AppColors.signalMercury)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text("Developer Mode")
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)

                Text("Tools for testing and screenshots")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(AppColors.accentSuccess)
        }
        .padding()
    }
}

#Preview {
    SettingsSection(title: "Developer Tools") {
        DeveloperHeaderSection()
    }
    .background(AppSurfaces.color(.contentBackground))
}
