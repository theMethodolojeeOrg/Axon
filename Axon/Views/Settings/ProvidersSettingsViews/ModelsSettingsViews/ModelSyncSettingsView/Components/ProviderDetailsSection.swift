//
//  ProviderDetailsSection.swift
//  Axon
//
//  Section displaying detailed information for each provider.
//

import SwiftUI

struct ProviderDetailsSection: View {
    let configService: ModelConfigurationService

    var body: some View {
        UnifiedSettingsSection(title: "Provider Details") {
            if let catalog = configService.activeCatalog {
                VStack(spacing: 12) {
                    ForEach(catalog.providers) { provider in
                        ProviderSummaryRow(provider: provider)
                    }
                }
            }
        }
    }
}
