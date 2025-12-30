//
//  ModelConfigurationView.swift
//  Axon
//
//  Settings view for configuring AI model generation parameters
//  (temperature, top-p, top-k) and custom system prompt suffix.
//

import SwiftUI

struct ModelConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    @State private var showingProviderInfo = false
    
    private var settings: Binding<ModelGenerationSettings> {
        $viewModel.settings.modelGenerationSettings
    }
    
    var body: some View {
        Form {
            // MARK: - System Prompt Section
            Section {
                Toggle("Enable Custom Suffix", isOn: settings.systemPromptSuffixEnabled)
                
                if viewModel.settings.modelGenerationSettings.systemPromptSuffixEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("System Prompt Suffix")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: settings.systemPromptSuffix)
                            .frame(minHeight: 80, maxHeight: 200)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(AppColors.substrateTertiary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            } header: {
                Text("System Prompt")
            } footer: {
                Text("Additional instructions appended to every conversation. Use for persistent personality traits, response formatting, or domain-specific guidance.")
            }
            
            // MARK: - Temperature Section
            Section {
                Toggle("Enable Custom Temperature", isOn: settings.temperatureEnabled)
                
                if viewModel.settings.modelGenerationSettings.temperatureEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.1f", viewModel.settings.modelGenerationSettings.temperature))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: settings.temperature,
                            in: 0...1,
                            step: 0.1
                        ) {
                            Text("Temperature")
                        } minimumValueLabel: {
                            Text("0")
                                .font(.caption2)
                        } maximumValueLabel: {
                            Text("1")
                                .font(.caption2)
                        }
                        
                        HStack {
                            Label("Deterministic", systemImage: "target")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label("Creative", systemImage: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Temperature")
            } footer: {
                Text("Controls randomness. Lower values (0.0-0.3) for factual tasks, higher values (0.7-1.0) for creative writing.")
            }
            
            // MARK: - Sampling Parameters Section
            Section {
                // Top-P
                Toggle("Enable Top-P (Nucleus Sampling)", isOn: settings.topPEnabled)
                
                if viewModel.settings.modelGenerationSettings.topPEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top-P")
                            Spacer()
                            Text(String(format: "%.2f", viewModel.settings.modelGenerationSettings.topP))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: settings.topP,
                            in: 0...1,
                            step: 0.05
                        )
                    }
                }
                
                // Top-K
                Toggle("Enable Top-K", isOn: settings.topKEnabled)
                
                if viewModel.settings.modelGenerationSettings.topKEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top-K")
                            Spacer()
                            Text("\(viewModel.settings.modelGenerationSettings.topK)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.modelGenerationSettings.topK) },
                                set: { viewModel.settings.modelGenerationSettings.topK = Int($0) }
                            ),
                            in: 1...100,
                            step: 1
                        )
                        
                        Text("Only supported by Anthropic and Gemini")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Sampling Parameters")
            } footer: {
                Text("Advanced controls for token selection. Top-P limits choices to a cumulative probability threshold. Top-K limits to the K most likely tokens.")
            }
            
            // MARK: - Repetition Penalty Section (Local MLX Models)
            Section {
                Toggle("Enable Repetition Penalty", isOn: settings.repetitionPenaltyEnabled)

                if viewModel.settings.modelGenerationSettings.repetitionPenaltyEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Penalty Strength")
                            Spacer()
                            Text(String(format: "%.1f", viewModel.settings.modelGenerationSettings.repetitionPenalty))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: settings.repetitionPenalty,
                            in: 1.0...2.0,
                            step: 0.1
                        ) {
                            Text("Repetition Penalty")
                        } minimumValueLabel: {
                            Text("1.0")
                                .font(.caption2)
                        } maximumValueLabel: {
                            Text("2.0")
                                .font(.caption2)
                        }

                        HStack {
                            Label("No penalty", systemImage: "arrow.trianglehead.counterclockwise")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label("Strong penalty", systemImage: "xmark.circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Context Window")
                            Spacer()
                            Text("\(viewModel.settings.modelGenerationSettings.repetitionContextSize) tokens")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.modelGenerationSettings.repetitionContextSize) },
                                set: { viewModel.settings.modelGenerationSettings.repetitionContextSize = Int($0) }
                            ),
                            in: 16...256,
                            step: 16
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Repetition Penalty")
                    Spacer()
                    Text("Local MLX Only")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Prevents repetitive loops in local model output. Higher values (1.3-1.5) more aggressively discourage repeated phrases. Context window determines how far back to check for repetition.")
            }

            // MARK: - Max Response Tokens Section (Local MLX Models)
            Section {
                Toggle("Limit Response Length", isOn: settings.maxResponseTokensEnabled)

                if viewModel.settings.modelGenerationSettings.maxResponseTokensEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(viewModel.settings.modelGenerationSettings.maxResponseTokens)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: Binding(
                                get: { Double(viewModel.settings.modelGenerationSettings.maxResponseTokens) },
                                set: { viewModel.settings.modelGenerationSettings.maxResponseTokens = Int($0) }
                            ),
                            in: 128...4096,
                            step: 128
                        ) {
                            Text("Max Response Tokens")
                        } minimumValueLabel: {
                            Text("128")
                                .font(.caption2)
                        } maximumValueLabel: {
                            Text("4096")
                                .font(.caption2)
                        }

                        HStack {
                            Label("Short", systemImage: "text.alignleft")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label("Long", systemImage: "text.justify")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Response Length")
                    Spacer()
                    Text("Local MLX Only")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Limits how many tokens the model can generate. Lower values produce shorter, more concise responses. 1 token ≈ 0.75 words.")
            }

            // MARK: - Provider Compatibility Section
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
            
            // MARK: - Reset Section
            Section {
                Button(role: .destructive) {
                    resetToDefaults()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Model Tuning")
        .sheet(isPresented: $showingProviderInfo) {
            ProviderCompatibilitySheet()
        }
    }
    
    private func resetToDefaults() {
        viewModel.settings.modelGenerationSettings = ModelGenerationSettings()
    }
}

// MARK: - Provider Compatibility Sheet

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
    NavigationStack {
        ModelConfigurationView(viewModel: SettingsViewModel.shared)
    }
}
