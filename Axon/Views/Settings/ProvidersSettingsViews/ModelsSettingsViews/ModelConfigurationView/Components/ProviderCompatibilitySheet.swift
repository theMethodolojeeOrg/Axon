//
//  ProviderCompatibilitySheet.swift
//  Axon
//
//  Sheet displaying provider compatibility with model parameters.
//

import SwiftUI

struct ProviderCompatibilitySheet: View {
    @Environment(\.dismiss) private var dismiss
    
    private let providers = [
        ("OpenAI", true, true, false),
        ("Anthropic", true, true, true),
        ("Gemini", true, true, true),
        ("Grok", true, true, false),
        ("DeepSeek", true, true, false),
        ("Mistral", true, true, false),
        ("MiniMax", true, true, false),
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(providers, id: \.0) { provider in
                        HStack {
                            Text(provider.0)
                                .fontWeight(.medium)
                            Spacer()
                            parameterIndicator("T", supported: provider.1)
                            parameterIndicator("P", supported: provider.2)
                            parameterIndicator("K", supported: provider.3)
                        }
                    }
                } header: {
                    HStack {
                        Text("Provider")
                        Spacer()
                        Text("T")
                            .frame(width: 30)
                        Text("P")
                            .frame(width: 30)
                        Text("K")
                            .frame(width: 30)
                    }
                    .font(.caption)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("T = Temperature")
                        Text("P = Top-P (Nucleus Sampling)")
                        Text("K = Top-K")
                    }
                    .font(.caption2)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Provider Compatibility")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func parameterIndicator(_ label: String, supported: Bool) -> some View {
        Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle")
            .foregroundStyle(supported ? .green : .secondary)
            .frame(width: 30)
    }
}

#Preview {
    ProviderCompatibilitySheet()
}
