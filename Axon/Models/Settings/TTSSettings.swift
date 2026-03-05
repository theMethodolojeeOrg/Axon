//
//  TTSSettings.swift
//  Axon
//
//  Text-to-speech settings and related types
//

import Foundation

// MARK: - TTS Provider

/// TTS provider selection - mutually exclusive
enum TTSProvider: String, Codable, CaseIterable, Identifiable {
    case apple = "apple"          // Native Apple TTS (free, no API key required)
    case kokoro = "kokoro"        // On-device neural TTS via Kokoro (free, no API key required)
    case mlxAudio = "mlxAudio"    // On-device neural TTS via F5-TTS (free, no API key required) - DISABLED
    case elevenlabs = "elevenlabs"
    case gemini = "gemini"
    case openai = "openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple (Siri)"
        case .kokoro: return "Kokoro Neural"
        case .mlxAudio: return "F5 Neural"
        case .elevenlabs: return "ElevenLabs"
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        }
    }

    var description: String {
        switch self {
        case .apple: return "On-device Siri voices • Free • No API key"
        case .kokoro: return "On-device neural TTS • Free • ~600MB model"
        case .mlxAudio: return "On-device neural TTS • Free • ~300MB model"
        case .elevenlabs: return "High-quality voices with fine-tuned controls"
        case .gemini: return "Google's TTS with expressive voices"
        case .openai: return "Promptable TTS with natural voices"
        }
    }

    var icon: String {
        switch self {
        case .apple: return "apple.logo"
        case .kokoro: return "waveform.badge.magnifyingglass"
        case .mlxAudio: return "waveform.badge.mic"
        case .elevenlabs: return "waveform"
        case .gemini: return "sparkles"
        case .openai: return "brain.head.profile"
        }
    }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool {
        switch self {
        case .apple, .kokoro, .mlxAudio: return false
        case .elevenlabs, .gemini, .openai: return true
        }
    }
}

// MARK: - Voice Gender

/// Voice gender classification
enum VoiceGender: String, Codable, CaseIterable {
    case male
    case female

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }

    var icon: String {
        switch self {
        case .male: return "person.fill"
        case .female: return "person.fill"
        }
    }
}

// MARK: - Gemini TTS Voice

/// Gemini TTS voice options (all 30 available voices)
enum GeminiTTSVoice: String, Codable, CaseIterable, Identifiable {
    // Original voices
    case zephyr = "Zephyr"
    case puck = "Puck"
    case charon = "Charon"
    case kore = "Kore"
    case fenrir = "Fenrir"
    case leda = "Leda"
    case orus = "Orus"
    case aoede = "Aoede"
    // Additional voices
    case callirrhoe = "Callirrhoe"
    case autonoe = "Autonoe"
    case enceladus = "Enceladus"
    case iapetus = "Iapetus"
    case umbriel = "Umbriel"
    case algieba = "Algieba"
    case despina = "Despina"
    case erinome = "Erinome"
    case algenib = "Algenib"
    case rasalgethi = "Rasalgethi"
    case laomedeia = "Laomedeia"
    case achernar = "Achernar"
    case alnilam = "Alnilam"
    case schedar = "Schedar"
    case gacrux = "Gacrux"
    case pulcherrima = "Pulcherrima"
    case achird = "Achird"
    case zubenelgenubi = "Zubenelgenubi"
    case vindemiatrix = "Vindemiatrix"
    case sadachbia = "Sadachbia"
    case sadaltager = "Sadaltager"
    case sulafat = "Sulafat"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Voice gender based on the mythological/astronomical origin of the name
    var gender: VoiceGender {
        switch self {
        // Female voices (Greek goddesses, nymphs, muses, female figures)
        case .kore: return .female          // Persephone/maiden
        case .leda: return .female          // Queen of Sparta
        case .aoede: return .female         // Muse of song
        case .callirrhoe: return .female    // Ocean nymph
        case .autonoe: return .female       // Daughter of Cadmus
        case .despina: return .female       // Sea nymph
        case .erinome: return .female       // One of the Graces
        case .laomedeia: return .female     // Sea nymph
        case .pulcherrima: return .female   // Latin "most beautiful"
        case .vindemiatrix: return .female  // Latin "grape gatherer"
        // Male voices (Greek gods, titans, male figures, stars with male names)
        case .zephyr: return .male          // God of west wind
        case .puck: return .male            // Mischievous sprite
        case .charon: return .male          // Ferryman of Hades
        case .fenrir: return .male          // Norse wolf
        case .orus: return .male            // Variant of Horus
        case .enceladus: return .male       // Giant
        case .iapetus: return .male         // Titan
        case .umbriel: return .male         // Moon of Uranus (male spirit)
        case .algieba: return .male         // Star name
        case .algenib: return .male         // Star name
        case .rasalgethi: return .male      // "Head of the kneeler"
        case .achernar: return .male        // Star name
        case .alnilam: return .male         // Star name
        case .schedar: return .male         // Star name
        case .gacrux: return .male          // Star name
        case .achird: return .male          // Star name
        case .zubenelgenubi: return .male   // Star name
        case .sadachbia: return .male       // Star name
        case .sadaltager: return .male      // Star name
        case .sulafat: return .male         // Star name
        }
    }

    var toneDescription: String {
        switch self {
        case .zephyr: return "Bright"
        case .puck: return "Upbeat"
        case .charon: return "Informative"
        case .kore: return "Firm"
        case .fenrir: return "Excitable"
        case .leda: return "Youthful"
        case .orus: return "Firm"
        case .aoede: return "Breezy"
        case .callirrhoe: return "Easy-going"
        case .autonoe: return "Bright"
        case .enceladus: return "Breathy"
        case .iapetus: return "Clear"
        case .umbriel: return "Easy-going"
        case .algieba: return "Smooth"
        case .despina: return "Smooth"
        case .erinome: return "Clear"
        case .algenib: return "Gravelly"
        case .rasalgethi: return "Informative"
        case .laomedeia: return "Upbeat"
        case .achernar: return "Soft"
        case .alnilam: return "Firm"
        case .schedar: return "Even"
        case .gacrux: return "Mature"
        case .pulcherrima: return "Forward"
        case .achird: return "Friendly"
        case .zubenelgenubi: return "Casual"
        case .vindemiatrix: return "Gentle"
        case .sadachbia: return "Lively"
        case .sadaltager: return "Knowledgeable"
        case .sulafat: return "Warm"
        }
    }

    /// Get all voices filtered by gender
    static func voices(for gender: VoiceGender) -> [GeminiTTSVoice] {
        allCases.filter { $0.gender == gender }
    }

    // MARK: - Registry Bridge Properties

    /// Get voice config from registry (if available)
    var registryConfig: TTSVoiceConfig? {
        UnifiedModelRegistry.shared.voice(provider: .gemini, voiceId: rawValue)
    }

    /// Display name from registry, falling back to hardcoded value
    var registryDisplayName: String {
        registryConfig?.displayName ?? displayName
    }

    /// Tone description from registry, falling back to hardcoded value
    var registryToneDescription: String {
        registryConfig?.toneDescription ?? toneDescription
    }

    /// Whether this enum case exists in the JSON registry
    var isValidInRegistry: Bool {
        registryConfig != nil
    }
}

// MARK: - Gemini TTS Model

/// Gemini TTS model options
enum GeminiTTSModel: String, Codable, CaseIterable, Identifiable {
    case flash = "gemini-2.5-flash-preview-tts"
    case pro = "gemini-2.5-pro-preview-tts"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flash: return "Flash (Faster)"
        case .pro: return "Pro (Higher Quality)"
        }
    }

    var description: String {
        switch self {
        case .flash: return "Optimized for speed and cost efficiency"
        case .pro: return "Best quality, more expressive output"
        }
    }
}

// MARK: - OpenAI TTS Voice

/// OpenAI TTS voice options (10 built-in voices)
enum OpenAITTSVoice: String, Codable, CaseIterable, Identifiable {
    case alloy = "alloy"
    case ash = "ash"
    case ballad = "ballad"
    case coral = "coral"
    case echo = "echo"
    case fable = "fable"
    case nova = "nova"
    case onyx = "onyx"
    case sage = "sage"
    case shimmer = "shimmer"

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Voice gender based on OpenAI's documented voice characteristics
    var gender: VoiceGender {
        switch self {
        // Female voices
        case .alloy: return .female     // Neutral female
        case .coral: return .female     // Clear, friendly female
        case .nova: return .female      // Bright, upbeat female
        case .shimmer: return .female   // Light, airy female
        case .ballad: return .female    // Soft, expressive female
        // Male voices
        case .ash: return .male         // Warm, confident male
        case .echo: return .male        // Measured, composed male
        case .fable: return .male       // Expressive male (British)
        case .onyx: return .male        // Deep, authoritative male
        case .sage: return .male        // Calm, thoughtful male
        }
    }

    var toneDescription: String {
        switch self {
        case .alloy: return "Neutral, balanced"
        case .ash: return "Warm, confident"
        case .ballad: return "Soft, expressive"
        case .coral: return "Clear, friendly"
        case .echo: return "Measured, composed"
        case .fable: return "Expressive, storytelling"
        case .nova: return "Bright, upbeat"
        case .onyx: return "Deep, authoritative"
        case .sage: return "Calm, thoughtful"
        case .shimmer: return "Light, airy"
        }
    }

    /// Get all voices filtered by gender
    static func voices(for gender: VoiceGender) -> [OpenAITTSVoice] {
        allCases.filter { $0.gender == gender }
    }

    // MARK: - Registry Bridge Properties

    /// Get voice config from registry (if available)
    var registryConfig: TTSVoiceConfig? {
        UnifiedModelRegistry.shared.voice(provider: .openai, voiceId: rawValue)
    }

    /// Display name from registry, falling back to hardcoded value
    var registryDisplayName: String {
        registryConfig?.displayName ?? displayName
    }

    /// Tone description from registry, falling back to hardcoded value
    var registryToneDescription: String {
        registryConfig?.toneDescription ?? toneDescription
    }

    /// Whether this enum case exists in the JSON registry
    var isValidInRegistry: Bool {
        registryConfig != nil
    }
}

// MARK: - OpenAI TTS Model

/// OpenAI TTS model options
enum OpenAITTSModel: String, Codable, CaseIterable, Identifiable {
    case gpt4oMiniTTS = "gpt-4o-mini-tts"
    case tts1 = "tts-1"
    case tts1HD = "tts-1-hd"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt4oMiniTTS: return "GPT-4o Mini TTS"
        case .tts1: return "TTS-1"
        case .tts1HD: return "TTS-1 HD"
        }
    }

    var description: String {
        switch self {
        case .gpt4oMiniTTS: return "Newest, promptable voice control"
        case .tts1: return "Fast, lower latency"
        case .tts1HD: return "Higher quality audio"
        }
    }

    /// Whether this model supports the instructions parameter
    var supportsInstructions: Bool {
        switch self {
        case .gpt4oMiniTTS: return true
        case .tts1, .tts1HD: return false
        }
    }
}

// MARK: - TTS Quality Tier

/// Quality tier for cost optimization
enum TTSQualityTier: String, Codable, CaseIterable, Identifiable {
    case standard    // Lower cost, faster
    case high        // Best quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High Quality"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Faster, lower cost"
        case .high: return "Best quality audio"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "bolt"
        case .high: return "waveform"
        }
    }
}

// MARK: - TTS Settings

struct TTSSettings: Codable, Equatable {
    /// Active TTS provider (defaults to Apple TTS for zero-config experience)
    var provider: TTSProvider = .apple

    /// Quality tier - affects model selection per provider
    var qualityTier: TTSQualityTier = .high

    // MARK: - TTS Text Preprocessing

    /// Default behavior: convert Markdown to rendered plaintext before sending to TTS.
    /// This prevents voices from reading formatting symbols.
    var stripMarkdownBeforeTTS: Bool = true

    /// Optional second-pass normalization to make text more spoken-friendly.
    /// Off by default to preserve fidelity to displayed text.
    var spokenFriendlyTTS: Bool = false

    // MARK: - Voice Gender Filter
    /// Filter voices by gender (nil = show all)
    var voiceGenderFilter: VoiceGender? = nil

    // MARK: - Apple TTS Settings
    var appleVoice: AppleTTSVoice = .samantha
    /// Speech rate (0.0 to 1.0, where 0.5 is default/normal)
    var appleRate: Float = 0.5

    // MARK: - ElevenLabs Settings
    var model: TTSModel = .turboV25
    var outputFormat: TTSOutputFormat = .mp3128
    var voiceSettings: VoiceSettings = VoiceSettings()
    var selectedVoiceId: String? = nil
    var selectedVoiceName: String? = nil
    var cachedVoices: [ElevenLabsService.ELVoice] = []

    // MARK: - Gemini TTS Settings
    var geminiVoice: GeminiTTSVoice = .puck
    var geminiModel: GeminiTTSModel = .flash
    /// Voice direction/style instructions for Gemini TTS (e.g., "Speak in a cheerful, upbeat tone with a slight British accent")
    /// Gemini TTS supports natural language prompts to control style, accent, pace, and tone
    var geminiVoiceDirection: String = ""

    // MARK: - OpenAI TTS Settings
    var openaiVoice: OpenAITTSVoice = .alloy
    var openaiModel: OpenAITTSModel = .gpt4oMiniTTS
    /// Voice instructions for GPT-4o Mini TTS (e.g., "Speak in a cheerful tone")
    var openaiVoiceInstructions: String = ""
    /// Speed multiplier (0.25 to 4.0, default 1.0)
    var openaiSpeed: Double = 1.0

    // MARK: - F5-TTS Settings
    var mlxVoice: MLXTTSVoice = .defaultVoice
    /// Speech speed (0.5 to 2.0, default 1.0)
    var mlxSpeed: Float = 1.0

    // MARK: - Kokoro TTS Settings
    var kokoroVoice: KokoroTTSVoice = .af_heart
    /// Speech speed (0.5 to 2.0, default 1.0)
    var kokoroSpeed: Float = 1.0
    /// Set of downloaded voice IDs (for tracking which voices have been downloaded)
    var downloadedKokoroVoices: Set<String> = []

    // MARK: - Pinned Voices

    /// Pinned/favorite voices per provider (shown at top of picker)
    /// Key: provider rawValue (e.g., "gemini"), Value: array of voice IDs
    var pinnedVoices: [String: [String]] = [:]

    /// Check if a voice is pinned for a provider
    func isPinned(_ voiceId: String, for provider: TTSProvider) -> Bool {
        pinnedVoices[provider.rawValue]?.contains(voiceId) ?? false
    }

    /// Get pinned voice IDs for a provider
    func pinnedVoiceIds(for provider: TTSProvider) -> [String] {
        pinnedVoices[provider.rawValue] ?? []
    }

    /// Toggle pinned state for a voice
    mutating func togglePinnedVoice(_ voiceId: String, for provider: TTSProvider) {
        var voiceIds = pinnedVoices[provider.rawValue] ?? []
        if let index = voiceIds.firstIndex(of: voiceId) {
            voiceIds.remove(at: index)
        } else {
            voiceIds.append(voiceId)
        }
        pinnedVoices[provider.rawValue] = voiceIds
    }

    // MARK: - Computed Properties for Quality Tier

    /// Get the appropriate ElevenLabs model based on quality tier
    var effectiveElevenLabsModel: TTSModel {
        switch qualityTier {
        case .standard: return .flashV25
        case .high: return model
        }
    }

    /// Get the appropriate Gemini model based on quality tier
    var effectiveGeminiModel: GeminiTTSModel {
        switch qualityTier {
        case .standard: return .flash
        case .high: return geminiModel
        }
    }

    /// Get the appropriate OpenAI model based on quality tier
    var effectiveOpenAIModel: OpenAITTSModel {
        switch qualityTier {
        case .standard: return .tts1
        case .high: return openaiModel
        }
    }
}

// MARK: - ElevenLabs TTS Model

enum TTSModel: String, Codable, CaseIterable, Identifiable {
    case turboV25 = "eleven_turbo_v2_5"
    case multilingualV2 = "eleven_multilingual_v2"
    case flashV25 = "eleven_flash_v2_5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .turboV25: return "Turbo v2.5"
        case .multilingualV2: return "Multilingual v2"
        case .flashV25: return "Flash v2.5"
        }
    }

    var description: String {
        switch self {
        case .turboV25: return "Fastest, most natural"
        case .multilingualV2: return "Supports 29 languages"
        case .flashV25: return "Latest flash model"
        }
    }
}

// MARK: - TTS Output Format

enum TTSOutputFormat: String, Codable, CaseIterable, Identifiable {
    case mp3128 = "mp3_44100_128"
    case mp364 = "mp3_44100_64"
    case mp332 = "mp3_22050_32"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mp3128: return "MP3 128kbps"
        case .mp364: return "MP3 64kbps"
        case .mp332: return "MP3 32kbps"
        }
    }

    var description: String {
        switch self {
        case .mp3128: return "Highest quality"
        case .mp364: return "Balanced"
        case .mp332: return "Smallest size"
        }
    }
}

// MARK: - Voice Settings (ElevenLabs)

struct VoiceSettings: Codable, Equatable {
    var stability: Double = 0.5
    var similarityBoost: Double = 0.75
    var style: Double = 0.0
    var useSpeakerBoost: Bool = false
}
