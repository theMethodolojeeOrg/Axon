//
//  LiveVoiceSettingsView.swift
//  Axon
//
//  Live Voice mode settings - Thin Orchestrator
//

import SwiftUI
import AVFoundation
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LiveVoiceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    // Local draft so we can persist changes through SettingsViewModel.updateSetting(...)
    @State private var draft: LiveSettings
    @State private var isHydratingDraft = true

    // Voice preview state (TTS playback)
    @StateObject private var voicePreviewController = VoicePreviewController()

    // Microphone preview state (live mic input visualization)
    @StateObject private var micPreviewController = MicrophonePreviewController()

    // Transcription test state
    @StateObject private var transcriptionTestController = TranscriptionTestController()

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.settings.liveSettings)
    }

    var body: some View {
        Form {
            // MARK: - Mode Selection
            ModeSelectionSection(useOnDeviceModels: $draft.useOnDeviceModels)

            // MARK: - Provider Configuration (Cloud Mode)
            if !draft.useOnDeviceModels {
                ProviderConfigurationSection(
                    defaultProvider: $draft.defaultProvider,
                    defaultModelId: $draft.defaultModelId
                )
            }

            // MARK: - On-Device Model Selection
            if draft.useOnDeviceModels {
                OnDeviceModelSection(
                    preferredMLXModel: $draft.preferredMLXModel,
                    availableMLXModels: availableMLXModels
                )
            }

            // MARK: - Voice Settings
            VoiceSettingsSection(
                useOnDeviceModels: $draft.useOnDeviceModels,
                defaultProvider: $draft.defaultProvider,
                openAIVoice: $draft.openAIVoice,
                geminiVoice: $draft.geminiVoice,
                fallbackTTSEngine: $draft.fallbackTTSEngine,
                defaultKokoroVoice: $draft.defaultKokoroVoice,
                popularKokoroVoices: popularKokoroVoices
            )

            // MARK: - Voice Preview
            VoicePreviewSection(
                voicePreviewController: voicePreviewController,
                defaultKokoroVoice: $draft.defaultKokoroVoice,
                fallbackTTSEngine: $draft.fallbackTTSEngine
            )

            // MARK: - Microphone Preview
            MicrophonePreviewSection(
                micPreviewController: micPreviewController,
                noiseGateEnabled: $draft.noiseGateEnabled,
                noiseGateThreshold: $draft.noiseGateThreshold
            )

            // MARK: - Voice Activity Detection
            VoiceActivityDetectionSection(
                useLocalVAD: $draft.useLocalVAD,
                vadSensitivity: $draft.vadSensitivity
            )

            // MARK: - Noise Gate
            NoiseGateSection(
                noiseGateEnabled: $draft.noiseGateEnabled,
                noiseGateThreshold: $draft.noiseGateThreshold,
                noiseGateHoldMs: $draft.noiseGateHoldMs
            )

            // MARK: - Test Transcription
            TranscriptionTestSection(
                transcriptionTestController: transcriptionTestController
            )

            // MARK: - Speech Recognition
            SpeechRecognitionSection(useOnDeviceSTT: $draft.useOnDeviceSTT)

            // MARK: - Performance
            PerformanceSection(
                latencyMode: $draft.latencyMode,
                preferRealtime: $draft.preferRealtime
            )
        }
        .navigationTitle("Live Voice")
        // Keep draft in sync with viewModel (e.g., iCloud sync updates settings)
        .onAppear {
            // Avoid treating initial hydration as a user edit
            isHydratingDraft = true
            draft = viewModel.settings.liveSettings
            DispatchQueue.main.async { isHydratingDraft = false }
        }
        // Persist edits (debounced)
        .onChange(of: draft) { _, newValue in
            guard !isHydratingDraft else { return }
            persistDebounced(newValue)
        }
        .onDisappear {
            voicePreviewController.stop()
            micPreviewController.stopListening()
            transcriptionTestController.stopListening()
        }
        #if os(macOS)
        .formStyle(.grouped)
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Helpers

    private var popularKokoroVoices: [KokoroTTSVoice] {
        [.af_heart, .af_bella, .af_nova, .am_echo, .am_adam, .bf_emma, .bm_george]
    }

    private var availableMLXModels: [String] {
        // Return available downloaded models from settings
        viewModel.settings.userMLXModels
            .filter { $0.downloadStatus == .downloaded }
            .map { $0.repoId }
    }

    // MARK: - Persistence

    /// Simple debounce so slider drags don't spam disk/iCloud writes.
    private func persistDebounced(_ newValue: LiveSettings) {
        let token = UUID()
        pendingPersistToken = token

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms
            guard pendingPersistToken == token else { return }
            await viewModel.updateSetting(\.liveSettings, newValue)
        }
    }

    @State private var pendingPersistToken: UUID?
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LiveVoiceSettingsView(viewModel: SettingsViewModel.shared)
    }
}
