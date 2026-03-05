//
//  TTSVoicePicker.swift
//  Axon
//
//  Compact voice picker with gender filtering and pinned voices
//

import SwiftUI
import Combine

/// Compact voice picker for TTS settings with gender filter and pinned voices support
struct TTSVoicePicker<Voice: Hashable & Identifiable>: View {
    let voices: [Voice]
    let pinnedVoiceIds: [String]
    @Binding var selectedVoice: Voice
    @Binding var genderFilter: VoiceGender?

    // Closures to extract voice properties
    var getVoiceId: (Voice) -> String
    var getVoiceName: (Voice) -> String
    var getVoiceGender: (Voice) -> VoiceGender?

    // Optional: destination for "Manage Voices" link
    var manageVoicesDestination: AnyView?

    private var filteredVoices: [Voice] {
        let filtered = voices.filter { voice in
            guard let filter = genderFilter else { return true }
            return getVoiceGender(voice) == filter
        }
        // Sort with pinned first
        return filtered.sorted { v1, v2 in
            let id1 = getVoiceId(v1)
            let id2 = getVoiceId(v2)
            let pinned1 = pinnedVoiceIds.contains(id1)
            let pinned2 = pinnedVoiceIds.contains(id2)
            if pinned1 && !pinned2 { return true }
            if !pinned1 && pinned2 { return false }
            return getVoiceName(v1) < getVoiceName(v2)
        }
    }

    var body: some View {
        SettingsCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                // Header with gender filter
                HStack {
                    Text("Voice")
                        .font(AppTypography.labelMedium())
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()

                    // Gender filter buttons
                    HStack(spacing: 4) {
                        GenderFilterButton(
                            label: "All",
                            isSelected: genderFilter == nil,
                            action: { genderFilter = nil }
                        )
                        GenderFilterButton(
                            label: "♀",
                            isSelected: genderFilter == .female,
                            action: { genderFilter = .female }
                        )
                        GenderFilterButton(
                            label: "♂",
                            isSelected: genderFilter == .male,
                            action: { genderFilter = .male }
                        )
                    }
                }

                // Voice picker
                StyledMenuPicker(
                    icon: "waveform",
                    title: getVoiceName(selectedVoice) + (pinnedVoiceIds.contains(getVoiceId(selectedVoice)) ? " ⭐" : ""),
                    selection: Binding(
                        get: { getVoiceId(selectedVoice) },
                        set: { newId in
                            if let voice = voices.first(where: { getVoiceId($0) == newId }) {
                                selectedVoice = voice
                            }
                        }
                    )
                ) {
                    #if os(macOS)
                    // Pinned voices section
                    let pinned = filteredVoices.filter { pinnedVoiceIds.contains(getVoiceId($0)) }
                    if !pinned.isEmpty {
                        Section("⭐ Pinned") {
                            ForEach(pinned, id: \.id) { voice in
                                MenuButtonItem(
                                    id: getVoiceId(voice),
                                    label: getVoiceName(voice),
                                    isSelected: getVoiceId(selectedVoice) == getVoiceId(voice)
                                ) {
                                    selectedVoice = voice
                                }
                            }
                        }
                    }

                    // Other voices
                    let others = filteredVoices.filter { !pinnedVoiceIds.contains(getVoiceId($0)) }
                    Section("All Voices") {
                        ForEach(others, id: \.id) { voice in
                            MenuButtonItem(
                                id: getVoiceId(voice),
                                label: getVoiceName(voice),
                                isSelected: getVoiceId(selectedVoice) == getVoiceId(voice)
                            ) {
                                selectedVoice = voice
                            }
                        }
                    }
                    #else
                    // Pinned voices section
                    let pinned = filteredVoices.filter { pinnedVoiceIds.contains(getVoiceId($0)) }
                    if !pinned.isEmpty {
                        Section("⭐ Pinned") {
                            ForEach(pinned, id: \.id) { voice in
                                Text(getVoiceName(voice)).tag(getVoiceId(voice))
                            }
                        }
                    }

                    // Other voices
                    let others = filteredVoices.filter { !pinnedVoiceIds.contains(getVoiceId($0)) }
                    Section("All Voices") {
                        ForEach(others, id: \.id) { voice in
                            Text(getVoiceName(voice)).tag(getVoiceId(voice))
                        }
                    }
                    #endif
                }

                // Manage Voices link
                if let destination = manageVoicesDestination {
                    NavigationLink {
                        destination
                    } label: {
                        HStack {
                            Spacer()
                            Text("Manage Voices")
                                .font(AppTypography.labelSmall())
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppColors.signalMercury)
                    }
                }
            }
        }
    }
}

// MARK: - Convenience Extensions

extension TTSVoicePicker where Voice == GeminiTTSVoice {
    init(
        selectedVoice: Binding<GeminiTTSVoice>,
        genderFilter: Binding<VoiceGender?>,
        pinnedVoiceIds: [String],
        manageVoicesDestination: AnyView? = nil
    ) {
        self.voices = GeminiTTSVoice.allCases
        self.pinnedVoiceIds = pinnedVoiceIds
        self._selectedVoice = selectedVoice
        self._genderFilter = genderFilter
        self.getVoiceId = { $0.rawValue }
        self.getVoiceName = { $0.displayName }
        self.getVoiceGender = { $0.gender }
        self.manageVoicesDestination = manageVoicesDestination
    }
}

extension TTSVoicePicker where Voice == OpenAITTSVoice {
    init(
        selectedVoice: Binding<OpenAITTSVoice>,
        genderFilter: Binding<VoiceGender?>,
        pinnedVoiceIds: [String],
        manageVoicesDestination: AnyView? = nil
    ) {
        self.voices = OpenAITTSVoice.allCases
        self.pinnedVoiceIds = pinnedVoiceIds
        self._selectedVoice = selectedVoice
        self._genderFilter = genderFilter
        self.getVoiceId = { $0.rawValue }
        self.getVoiceName = { $0.displayName }
        self.getVoiceGender = { $0.gender }
        self.manageVoicesDestination = manageVoicesDestination
    }
}

extension TTSVoicePicker where Voice == AppleTTSVoice {
    init(
        selectedVoice: Binding<AppleTTSVoice>,
        genderFilter: Binding<VoiceGender?>,
        pinnedVoiceIds: [String],
        manageVoicesDestination: AnyView? = nil
    ) {
        self.voices = AppleTTSVoice.allCases
        self.pinnedVoiceIds = pinnedVoiceIds
        self._selectedVoice = selectedVoice
        self._genderFilter = genderFilter
        self.getVoiceId = { $0.rawValue }
        self.getVoiceName = { $0.displayName }
        self.getVoiceGender = { $0.gender }
        self.manageVoicesDestination = manageVoicesDestination
    }
}

extension TTSVoicePicker where Voice == KokoroTTSVoice {
    init(
        selectedVoice: Binding<KokoroTTSVoice>,
        genderFilter: Binding<VoiceGender?>,
        pinnedVoiceIds: [String],
        manageVoicesDestination: AnyView? = nil
    ) {
        self.voices = KokoroTTSVoice.allCases
        self.pinnedVoiceIds = pinnedVoiceIds
        self._selectedVoice = selectedVoice
        self._genderFilter = genderFilter
        self.getVoiceId = { $0.rawValue }
        self.getVoiceName = { $0.registryDisplayName }
        self.getVoiceGender = { $0.gender }
        self.manageVoicesDestination = manageVoicesDestination
    }
}
