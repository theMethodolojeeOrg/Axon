//
//  ProviderCompatibilitySection.swift
//  Axon
//
//  Section with button to display provider compatibility sheet.
//

import SwiftUI

struct ProviderCompatibilitySection: View {
    @State private var showingProviderInfo = false

    var body: some View {
        Section {
            Button {
                showingProviderInfo = true
            } label: {
                HStack {
                    Label("View Provider Compatibility", systemImage: "info.circle")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Information")
        }
        .sheet(isPresented: $showingProviderInfo) {
            Group {
            ProviderCompatibilitySheet()

            }
            .appSheetMaterial()
}
    }
}

#Preview {
    Form {
        ProviderCompatibilitySection()
    }
}
