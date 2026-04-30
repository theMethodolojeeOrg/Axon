//
//  SystemPromptSection.swift
//  Axon
//
//  Section for configuring custom system prompt suffix.
//

import SwiftUI

struct SystemPromptSection: View {
    @Binding var settings: ModelGenerationSettings
    
    var body: some View {
        Section {
            Toggle("Enable Custom Suffix", isOn: $settings.systemPromptSuffixEnabled)
            
            if settings.systemPromptSuffixEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt Suffix")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $settings.systemPromptSuffix)
                        .frame(minHeight: 80, maxHeight: 200)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(AppSurfaces.color(.controlMutedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        } header: {
            Text("System Prompt")
        } footer: {
            Text("Additional instructions appended to every conversation. Use for persistent personality traits, response formatting, or domain-specific guidance.")
        }
    }
}

#Preview {
    Form {
        SystemPromptSection(settings: .constant(ModelGenerationSettings()))
    }
}
