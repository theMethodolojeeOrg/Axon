//
//  RealtimeVoiceSection.swift
//  Axon
//
//  Realtime voice provider and voice selection section
//

import SwiftUI

struct RealtimeVoiceSection: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    
    @Binding var selectedLiveProvider: String?
    @Binding var selectedLiveVoice: String?
    
    let onSave: () -> Void
    
    var body: some View {
        ChatInfoSection(title: "Realtime Voice") {
            VStack(spacing: 16) {
                // Live Provider Selection
                providerMenu
                
                // Voice Selection (only for native real-time providers)
                if selectedLiveProvider == nil || selectedLiveProvider == "openai" || selectedLiveProvider == "gemini" {
                    voiceMenu
                } else {
                    // HTTP streaming or MLX providers use Kokoro TTS
                    kokoroTTSNote
                }
            }
        }
    }
    
    // MARK: - Provider Menu
    
    private var providerMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
            
            Menu {
                Button("Default (\(LiveProviderHelpers.displayName(for: settingsViewModel.settings.liveSettings.defaultProvider)))") {
                    selectedLiveProvider = nil
                    selectedLiveVoice = nil
                    onSave()
                }
                Divider()
                
                // Native real-time providers (WebSocket)
                Section("Native Real-time") {
                    Button("Gemini Live") {
                        selectedLiveProvider = "gemini"
                        onSave()
                    }
                    Button("OpenAI Realtime") {
                        selectedLiveProvider = "openai"
                        onSave()
                    }
                }
                
                // HTTP streaming providers (STT + API + TTS)
                Section("HTTP Streaming") {
                    Button("Anthropic (Claude)") {
                        selectedLiveProvider = "anthropic"
                        onSave()
                    }
                    Button("xAI (Grok)") {
                        selectedLiveProvider = "xai"
                        onSave()
                    }
                    Button("Perplexity") {
                        selectedLiveProvider = "perplexity"
                        onSave()
                    }
                    Button("DeepSeek") {
                        selectedLiveProvider = "deepseek"
                        onSave()
                    }
                }
                
                // On-device
                Section("On-Device") {
                    Button("MLX (Offline)") {
                        selectedLiveProvider = "mlx"
                        onSave()
                    }
                }
            } label: {
                HStack {
                    Text(LiveProviderHelpers.selectedProviderLabel(
                        selectedProvider: selectedLiveProvider,
                        defaultProvider: settingsViewModel.settings.liveSettings.defaultProvider
                    ))
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    // Execution mode badge
                    LiveExecutionModeBadge(mode: effectiveLiveExecutionMode)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(12)
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Voice Menu
    
    private var voiceMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textSecondary)
            
            Menu {
                Button("Default") {
                    selectedLiveVoice = nil
                    onSave()
                }
                Divider()
                if isOpenAIVoice {
                    openAIVoices
                } else {
                    geminiVoices
                }
            } label: {
                HStack {
                    Text(selectedLiveVoice ?? "Default")
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(12)
                .background(AppSurfaces.color(.cardBackground))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var isOpenAIVoice: Bool {
        (selectedLiveProvider == "openai") ||
        (selectedLiveProvider == nil && settingsViewModel.settings.liveSettings.defaultProvider == .openai)
    }
    
    @ViewBuilder
    private var openAIVoices: some View {
        Button("Alloy") { selectedLiveVoice = "alloy"; onSave() }
        Button("Ash") { selectedLiveVoice = "ash"; onSave() }
        Button("Ballad") { selectedLiveVoice = "ballad"; onSave() }
        Button("Coral") { selectedLiveVoice = "coral"; onSave() }
        Button("Echo") { selectedLiveVoice = "echo"; onSave() }
        Button("Marin") { selectedLiveVoice = "marin"; onSave() }
        Button("Sage") { selectedLiveVoice = "sage"; onSave() }
        Button("Shimmer") { selectedLiveVoice = "shimmer"; onSave() }
        Button("Verse") { selectedLiveVoice = "verse"; onSave() }
    }
    
    @ViewBuilder
    private var geminiVoices: some View {
        Button("Aoede") { selectedLiveVoice = "Aoede"; onSave() }
        Button("Callirrhoe") { selectedLiveVoice = "Callirrhoe"; onSave() }
        Button("Charon") { selectedLiveVoice = "Charon"; onSave() }
        Button("Fenrir") { selectedLiveVoice = "Fenrir"; onSave() }
        Button("Kore") { selectedLiveVoice = "Kore"; onSave() }
        Button("Leda") { selectedLiveVoice = "Leda"; onSave() }
        Button("Orus") { selectedLiveVoice = "Orus"; onSave() }
        Button("Puck") { selectedLiveVoice = "Puck"; onSave() }
        Button("Zephyr") { selectedLiveVoice = "Zephyr"; onSave() }
    }
    
    // MARK: - Kokoro TTS Note
    
    private var kokoroTTSNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textTertiary)
            Text("Uses Kokoro TTS for voice output")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppSurfaces.color(.cardBackground))
        .cornerRadius(8)
    }
    
    // MARK: - Helpers
    
    private var effectiveLiveExecutionMode: ExecutionMode {
        LiveProviderHelpers.executionMode(
            for: selectedLiveProvider,
            defaultProvider: settingsViewModel.settings.liveSettings.defaultProvider,
            defaultModelId: settingsViewModel.settings.liveSettings.defaultModelId,
            settingsViewModel: settingsViewModel
        )
    }
}

#Preview {
    RealtimeVoiceSection(
        settingsViewModel: SettingsViewModel(),
        selectedLiveProvider: .constant(nil),
        selectedLiveVoice: .constant(nil),
        onSave: {}
    )
    .padding()
    .background(AppSurfaces.color(.contentBackground))
}
