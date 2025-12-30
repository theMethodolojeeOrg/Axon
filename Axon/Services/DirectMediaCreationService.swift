//
//  DirectMediaCreationService.swift
//  Axon
//
//  Service for direct media generation from the Create gallery.
//  Wraps existing generation services and creates gallery entries.
//

import Foundation
import Combine

@MainActor
class DirectMediaCreationService: ObservableObject {
    static let shared = DirectMediaCreationService()
    
    @Published var isGenerating = false
    @Published var generationProgress: String?
    @Published var lastError: String?
    
    private init() {}
    
    // MARK: - API Key Availability
    
    var hasOpenAIKey: Bool {
        APIKeysStorage.shared.isConfigured(.openai)
    }
    
    var hasGeminiKey: Bool {
        APIKeysStorage.shared.isConfigured(.gemini)
    }
    
    var hasElevenLabsKey: Bool {
        APIKeysStorage.shared.isConfigured(.elevenlabs)
    }
    
    /// Available TTS providers based on configured API keys
    var availableTTSProviders: [TTSProvider] {
        var providers: [TTSProvider] = []
        if hasOpenAIKey { providers.append(.openai) }
        if hasGeminiKey { providers.append(.gemini) }
        if hasElevenLabsKey { providers.append(.elevenlabs) }
        return providers
    }
    
    // MARK: - Image Generation
    
    /// Generate an image using OpenAI GPT-Image
    /// - Parameters:
    ///   - prompt: The image generation prompt
    ///   - size: Image dimensions
    ///   - quality: Image quality setting
    /// - Returns: The created CreativeItem
    func generateImage(
        prompt: String,
        size: ImageSize = .square1024,
        quality: ImageQuality = .auto
    ) async throws -> CreativeItem {
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .openai), !apiKey.isEmpty else {
            throw DirectMediaError.apiKeyMissing(.openai)
        }
        
        isGenerating = true
        generationProgress = "Generating image..."
        lastError = nil
        
        defer {
            isGenerating = false
            generationProgress = nil
        }
        
        do {
            let response = try await OpenAIToolService.shared.generateImage(
                apiKey: apiKey,
                prompt: prompt,
                size: size,
                quality: quality
            )
            
            guard let imageData = response.firstImage else {
                throw DirectMediaError.generationFailed("No image was generated")
            }
            
            // Create gallery item
            let itemId = UUID().uuidString
            let now = Date()
            
            let finalPrompt = response.firstImage?.revisedPrompt ?? prompt

            // Generate intelligent title
            generationProgress = "Generating title..."
            let title = await CreativeItemTitleService.shared.generateImageTitle(prompt: finalPrompt)

            let item = CreativeItem(
                id: itemId,
                type: .photo,
                conversationId: "direct_creation", // Special marker for directly created items
                messageId: "direct_\(itemId)",
                createdAt: now,
                contentURL: imageData.url,
                contentBase64: imageData.b64Json,
                mimeType: "image/png",
                title: title,
                prompt: finalPrompt
            )

            // Add to gallery
            CreativeGalleryService.shared.addItem(item)

            return item
            
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Audio Generation
    
    /// Generate audio using OpenAI TTS
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - model: The TTS model (gpt-4o-mini-tts supports instructions)
    ///   - instructions: Optional voice direction/style instructions
    func generateAudioOpenAI(
        text: String,
        voice: OpenAITTSVoice,
        model: OpenAITTSModel = .gpt4oMiniTTS,
        instructions: String? = nil
    ) async throws -> CreativeItem {
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .openai), !apiKey.isEmpty else {
            throw DirectMediaError.apiKeyMissing(.openai)
        }

        isGenerating = true
        generationProgress = "Generating audio with OpenAI..."
        lastError = nil

        defer {
            isGenerating = false
            generationProgress = nil
        }

        do {
            let audioData = try await OpenAITTSService.shared.generateSpeech(
                text: text,
                voice: voice,
                model: model,
                instructions: instructions,
                apiKey: apiKey
            )
            
            // Save audio to file
            let itemId = UUID().uuidString
            let fileName = "tts_\(itemId).mp3"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try audioData.write(to: fileURL)

            // Generate intelligent title
            generationProgress = "Generating title..."
            let title = await CreativeItemTitleService.shared.generateAudioTitle(text: text)

            let item = CreativeItem(
                id: itemId,
                type: .audio,
                conversationId: "direct_creation",
                messageId: "direct_\(itemId)",
                createdAt: Date(),
                contentURL: fileURL.absoluteString,
                contentBase64: audioData.base64EncodedString(),
                mimeType: "audio/mpeg",
                title: title,
                prompt: text
            )

            CreativeGalleryService.shared.addItem(item)

            return item

        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Generate audio using Gemini TTS
    /// - Parameters:
    ///   - text: The text to convert to speech
    ///   - voice: The voice to use
    ///   - direction: Optional voice direction/style instructions (natural language)
    func generateAudioGemini(
        text: String,
        voice: GeminiTTSService.GeminiVoice = .puck,
        direction: String? = nil
    ) async throws -> CreativeItem {
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .gemini), !apiKey.isEmpty else {
            throw DirectMediaError.apiKeyMissing(.gemini)
        }

        isGenerating = true
        generationProgress = "Generating audio with Gemini..."
        lastError = nil

        defer {
            isGenerating = false
            generationProgress = nil
        }

        do {
            let audioData = try await GeminiTTSService.shared.generateSpeech(
                text: text,
                voiceName: voice.rawValue,
                direction: direction,
                apiKey: apiKey
            )
            
            // Save audio (Gemini returns raw PCM, need to convert or save as raw)
            let itemId = UUID().uuidString

            // Generate intelligent title
            generationProgress = "Generating title..."
            let title = await CreativeItemTitleService.shared.generateAudioTitle(text: text)

            let item = CreativeItem(
                id: itemId,
                type: .audio,
                conversationId: "direct_creation",
                messageId: "direct_\(itemId)",
                createdAt: Date(),
                contentBase64: audioData.base64EncodedString(),
                mimeType: "audio/pcm",
                title: title,
                prompt: text
            )

            CreativeGalleryService.shared.addItem(item)

            return item

        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Generate audio using ElevenLabs TTS
    func generateAudioElevenLabs(
        text: String,
        voiceId: String,
        voiceName: String
    ) async throws -> CreativeItem {
        guard let apiKey = try? APIKeysStorage.shared.getAPIKey(for: .elevenlabs), !apiKey.isEmpty else {
            throw DirectMediaError.apiKeyMissing(.elevenlabs)
        }
        
        isGenerating = true
        generationProgress = "Generating audio with ElevenLabs..."
        lastError = nil
        
        defer {
            isGenerating = false
            generationProgress = nil
        }
        
        do {
            // Use default voice settings
            let voiceSettings = ElevenLabsService.VoiceSettingsPayload(
                stability: 0.5,
                similarityBoost: 0.75,
                style: 0.0,
                useSpeakerBoost: true
            )
            
            let audioData = try await ElevenLabsService.shared.generateTTSBase64(
                text: text,
                voiceId: voiceId,
                model: "eleven_multilingual_v2",
                format: "mp3_44100_128",
                voiceSettings: voiceSettings
            )

            let itemId = UUID().uuidString

            // Generate intelligent title
            generationProgress = "Generating title..."
            let title = await CreativeItemTitleService.shared.generateAudioTitle(text: text)

            let item = CreativeItem(
                id: itemId,
                type: .audio,
                conversationId: "direct_creation",
                messageId: "direct_\(itemId)",
                createdAt: Date(),
                contentBase64: audioData.base64EncodedString(),
                mimeType: "audio/mpeg",
                title: title,
                prompt: text
            )

            CreativeGalleryService.shared.addItem(item)

            return item
            
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
}

// MARK: - Errors

enum DirectMediaError: LocalizedError {
    case apiKeyMissing(APIProvider)
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing(let provider):
            return "\(provider.displayName) API key not configured. Add it in Settings → API Keys."
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        }
    }
}
