//
//  ElevenLabsHandler.swift
//  Axon
//
//  V2 Handler for ElevenLabs provider-native tools.
//

import Foundation
import os.log

@MainActor
final class ElevenLabsHandler: ToolHandlerV2 {

    let handlerId = "elevenlabs"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "ElevenLabsHandler"
    )

    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id

        switch toolId {
        case "elevenlabs_text_to_speech":
            return await executeTextToSpeech(inputs: inputs, toolId: toolId)
        case "elevenlabs_speech_to_text":
            return await executeSpeechToText(inputs: inputs, toolId: toolId)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown ElevenLabs tool: \(toolId)")
        }
    }

    // MARK: - Text to Speech

    private func executeTextToSpeech(
        inputs: [String: Any],
        toolId: String
    ) async -> ToolResultV2 {
        let text = (inputs["text"] as? String) ?? ""
        let voiceId = (inputs["voice_id"] as? String) ?? ""
        let modelId = (inputs["model_id"] as? String) ?? "eleven_multilingual_v2"
        let outputFormat = (inputs["output_format"] as? String) ?? "mp3_22050_32"

        guard !text.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "Text is required for TTS")
        }
        guard !voiceId.isEmpty else {
            return ToolResultV2.failure(toolId: toolId, error: "voice_id is required for TTS")
        }

        var voiceSettings = ElevenLabsService.VoiceSettingsPayload(
            stability: 0.5,
            similarityBoost: 0.75,
            style: 0.0,
            useSpeakerBoost: true
        )

        if let vs = inputs["voice_settings"] as? [String: Any] {
            let stability = (vs["stability"] as? Double) ?? voiceSettings.stability
            let similarityBoost = (vs["similarity_boost"] as? Double) ?? voiceSettings.similarityBoost
            let style = (vs["style"] as? Double) ?? voiceSettings.style
            let useSpeakerBoost = (vs["use_speaker_boost"] as? Bool) ?? voiceSettings.useSpeakerBoost
            voiceSettings = ElevenLabsService.VoiceSettingsPayload(
                stability: stability,
                similarityBoost: similarityBoost,
                style: style,
                useSpeakerBoost: useSpeakerBoost
            )
        }

        let optimizeStreamingLatency = inputs["optimize_streaming_latency"] as? Int
        let seed = inputs["seed"] as? Int
        let previousText = inputs["previous_text"] as? String
        let nextText = inputs["next_text"] as? String

        logger.info("Executing ElevenLabs Text to Speech")

        do {
            let audioData = try await ElevenLabsService.shared.generateTTSBase64(
                text: text,
                voiceId: voiceId,
                model: modelId,
                format: outputFormat,
                voiceSettings: voiceSettings,
                optimizeStreamingLatency: optimizeStreamingLatency,
                seed: seed,
                previousText: previousText,
                nextText: nextText
            )

            let ext = outputFormat.split(separator: "_").first.map(String.init) ?? "mp3"
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "elevenlabs_tts_\(UUID().uuidString).\(ext)"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try audioData.write(to: fileURL)

            return ToolResultV2.success(
                toolId: toolId,
                output: "Speech generated successfully.\nFile: \(fileURL.path)",
                structured: [
                    "filePath": fileURL.path,
                    "voiceId": voiceId,
                    "model": modelId,
                    "format": outputFormat
                ]
            )
        } catch {
            logger.error("ElevenLabs TTS failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "ElevenLabs TTS failed: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Speech to Text

    private func executeSpeechToText(
        inputs: [String: Any],
        toolId: String
    ) async -> ToolResultV2 {
        let filePath = (inputs["file"] as? String) ?? ""
        let cloudStorageUrl = inputs["cloud_storage_url"] as? String
        let modelId = (inputs["model_id"] as? String) ?? "scribe_v1"
        let languageCode = inputs["language_code"] as? String
        let diarize = inputs["diarize"] as? Bool
        let tagAudioEvents = inputs["tag_audio_events"] as? Bool
        let numSpeakers = inputs["num_speakers"] as? Int
        let diarizationThreshold = inputs["diarization_threshold"] as? Double
        let useMultiChannel = inputs["use_multi_channel"] as? Bool
        let webhook = inputs["webhook"] as? Bool

        if filePath.isEmpty && cloudStorageUrl == nil {
            return ToolResultV2.failure(toolId: toolId, error: "file or cloud_storage_url is required")
        }

        logger.info("Executing ElevenLabs Speech to Text")

        do {
            let fileURL = filePath.isEmpty ? nil : URL(fileURLWithPath: filePath)
            let transcription = try await ElevenLabsService.shared.transcribeSpeech(
                fileURL: fileURL,
                cloudStorageUrl: cloudStorageUrl,
                modelId: modelId,
                languageCode: languageCode,
                diarize: diarize,
                tagAudioEvents: tagAudioEvents,
                numSpeakers: numSpeakers,
                diarizationThreshold: diarizationThreshold,
                useMultiChannel: useMultiChannel,
                webhook: webhook
            )

            return ToolResultV2.success(
                toolId: toolId,
                output: transcription,
                structured: [
                    "model": modelId,
                    "language": languageCode ?? "auto"
                ]
            )
        } catch {
            logger.error("ElevenLabs STT failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: toolId,
                error: "ElevenLabs STT failed: \(error.localizedDescription)"
            )
        }
    }
}
