import Foundation
import AVFoundation
import os.log

private let mlxLiveLog = Logger(subsystem: "com.axon.app", category: "MLXLive")

/// Live provider that uses on-device MLX models with STT/TTS
/// Enables fully offline Live mode
final class OnDeviceMLXProvider: LiveProviderProtocol {
    let id = "mlx-ondevice"
    weak var delegate: LiveProviderDelegate?

    /// On-device MLX capabilities
    var capabilities: LiveProviderCapabilities {
        .onDeviceMLX
    }

    // MARK: - Dependencies

    private let mlxService = MLXModelService.shared
    private let vad = VoiceActivityDetector.shared
    private let speechRecognition = SpeechRecognitionService.shared

    // MARK: - Configuration

    private var currentConfig: LiveSessionConfig?
    private var ttsService: KokoroTTSService?

    // MARK: - State

    private var conversationHistory: [LiveMessage] = []
    private var isProcessing = false
    private var isConnected = false

    // Simple message structure for Live conversation
    struct LiveMessage {
        let role: String  // "user" or "assistant" or "system"
        let content: String

        func toMLXMessage() -> MLXMessage {
            MLXMessage(role: role, content: content)
        }
    }

    // MLX message format
    struct MLXMessage {
        let role: String
        let content: String
    }

    // MARK: - Initialization

    init(capabilities: LiveProviderCapabilities) {
        // capabilities parameter reserved for future use
    }

    // MARK: - LiveProviderProtocol

    func connect(config: LiveSessionConfig) async throws {
        mlxLiveLog.info("Connecting MLX Live provider")
        self.currentConfig = config

        delegate?.onStatusChange(.connecting)

        // Load MLX model
        let modelId = config.mlxModelId ?? getDefaultMLXModelId()
        mlxLiveLog.info("Loading MLX model: \(modelId)")

        do {
            try await mlxService.loadModel(modelId: modelId)
            mlxLiveLog.info("MLX model loaded successfully")
        } catch {
            mlxLiveLog.error("Failed to load MLX model: \(error.localizedDescription)")
            throw LiveProviderError.modelNotLoaded
        }

        // Request STT authorization
        if config.useOnDeviceSTT {
            let authorized = await speechRecognition.requestAuthorization()
            if !authorized {
                mlxLiveLog.warning("Speech recognition not authorized")
                // Continue anyway - user can still use text input
            }
        }

        // Initialize TTS service
        if config.fallbackTTSEngine == .kokoro {
            do {
                ttsService = KokoroTTSService.shared
                if let tts = ttsService, !tts.isModelLoaded {
                    mlxLiveLog.info("Loading Kokoro TTS model...")
                    try await tts.loadModel()
                }
            } catch {
                mlxLiveLog.error("Failed to load TTS: \(error.localizedDescription)")
                // Continue without TTS
            }
        }

        // Configure VAD
        if let sensitivity = vadSensitivityFromLatencyMode(config.latencyMode) {
            vad.setSensitivity(sensitivity)
        }
        vad.silenceThresholdMs = config.latencyMode.silenceThresholdMs

        // Add system instruction to history if present
        if let system = config.systemInstruction, !system.isEmpty {
            conversationHistory.append(LiveMessage(role: "system", content: system))
        }

        isConnected = true
        delegate?.onStatusChange(.connected)
        mlxLiveLog.info("MLX Live provider connected")
    }

    func disconnect() {
        mlxLiveLog.info("Disconnecting MLX Live provider")
        isConnected = false
        speechRecognition.stopRecognition()
        vad.reset()
        conversationHistory.removeAll()
        isProcessing = false
        delegate?.onStatusChange(.disconnected)
    }

    func sendAudio(buffer: AVAudioPCMBuffer) {
        guard isConnected, let config = currentConfig else { return }

        // Process VAD
        let vadResult = vad.processAudio(buffer: buffer)

        if vadResult.isSpeech {
            // Start or continue speech recognition
            if !speechRecognition.isListening && config.useOnDeviceSTT {
                do {
                    try speechRecognition.startRecognition()
                    mlxLiveLog.debug("Started speech recognition")
                } catch {
                    mlxLiveLog.error("Failed to start STT: \(error.localizedDescription)")
                }
            }

            if speechRecognition.isListening {
                speechRecognition.appendAudio(buffer: buffer)

                // Update partial transcript
                if !speechRecognition.partialTranscript.isEmpty {
                    delegate?.onTranscript(speechRecognition.partialTranscript, role: "user")
                }
            }
        } else if vad.isUtteranceComplete && speechRecognition.hasTranscript {
            // Utterance complete - process the transcript
            let transcript = speechRecognition.currentTranscript
            if !transcript.isEmpty && !isProcessing {
                mlxLiveLog.info("Utterance complete: \(transcript.prefix(50))...")
                speechRecognition.stopRecognition()
                speechRecognition.reset()

                // Process the user's utterance
                Task {
                    await processUserUtterance(transcript)
                }
            }
        }
    }

    func sendText(_ text: String) {
        guard isConnected, !isProcessing else { return }
        mlxLiveLog.info("Received text input: \(text.prefix(50))...")

        Task {
            await processUserUtterance(text)
        }
    }

    func sendToolOutput(toolCallId: String, output: String) {
        // MLX models typically don't support tool calling in Live mode
        mlxLiveLog.warning("Tool output not supported in MLX Live mode")
    }

    // MARK: - Private Methods

    private func processUserUtterance(_ text: String) async {
        guard !isProcessing, currentConfig != nil else { return }

        isProcessing = true
        delegate?.onTranscript(text, role: "user")

        // Add to conversation history
        conversationHistory.append(LiveMessage(role: "user", content: text))

        do {
            var fullResponse = ""

            // Build messages for MLX
            let messages = conversationHistory.map { $0.toMLXMessage() }

            // Get generation settings
            let maxTokens = 1024
            let temperature = 0.7
            let topP = 0.9
            let repetitionPenalty = 1.2
            let repetitionContextSize = 64

            mlxLiveLog.info("Starting MLX generation...")

            // Use streaming generation
            try await mlxService.generateStreaming(
                systemPrompt: nil,  // Already in conversation history
                messages: messagesToDictArray(messages),
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                repetitionContextSize: repetitionContextSize
            ) { [weak self] token in
                fullResponse += token
                Task { @MainActor in
                    self?.delegate?.onTextDelta(token)
                }
            }

            mlxLiveLog.info("MLX generation complete, response length: \(fullResponse.count)")

            // Clean up response (remove special tokens)
            let cleanedResponse = cleanMLXResponse(fullResponse)

            // Add assistant response to history
            if !cleanedResponse.isEmpty {
                conversationHistory.append(LiveMessage(role: "assistant", content: cleanedResponse))
                delegate?.onTranscript(cleanedResponse, role: "assistant")

                // Generate TTS audio
                await generateAndPlayTTS(text: cleanedResponse)
            }

        } catch {
            mlxLiveLog.error("Failed to process utterance: \(error.localizedDescription)")
            delegate?.onError(error)
        }

        isProcessing = false
    }

    private func generateAndPlayTTS(text: String) async {
        guard let config = currentConfig,
              config.fallbackTTSEngine == .kokoro,
              let tts = ttsService else {
            return
        }

        do {
            let voice = config.fallbackTTSVoice ?? .af_heart
            mlxLiveLog.info("Generating TTS with voice: \(voice.rawValue)")

            let audioData = try await tts.generateSpeech(
                text: text,
                voice: voice,
                speed: 1.0
            )

            // Send audio to delegate for playback
            delegate?.onAudioData(audioData)
            mlxLiveLog.info("TTS audio generated: \(audioData.count) bytes")

        } catch {
            mlxLiveLog.error("TTS generation failed: \(error.localizedDescription)")
        }
    }

    private func messagesToDictArray(_ messages: [MLXMessage]) -> [[String: String]] {
        messages.map { ["role": $0.role, "content": $0.content] }
    }

    private func cleanMLXResponse(_ response: String) -> String {
        var cleaned = response

        // Remove common special tokens
        let tokensToRemove = [
            "<|endoftext|>",
            "<|end|>",
            "</s>",
            "<eos>",
            "[/INST]",
            "[INST]",
            "<|im_end|>",
            "<|im_start|>",
            "<|assistant|>",
            "<|user|>"
        ]

        for token in tokensToRemove {
            cleaned = cleaned.replacingOccurrences(of: token, with: "")
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func getDefaultMLXModelId() -> String {
        // Return the default bundled model or first available
        // This should match LocalMLXModel.defaultModel
        return "lmstudio-community/gemma-3-270m-it-MLX-8bit"
    }

    private func vadSensitivityFromLatencyMode(_ mode: LatencyMode) -> Float? {
        switch mode {
        case .ultra:
            return 0.3  // More sensitive
        case .balanced:
            return 0.5
        case .quality:
            return 0.7  // Less sensitive
        }
    }
}

// MARK: - MLXModelService Extension for Streaming

extension MLXModelService {
    /// Generate response with streaming callback
    func generateStreaming(
        systemPrompt: String?,
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        repetitionPenalty: Double,
        repetitionContextSize: Int,
        onToken: @escaping (String) -> Void
    ) async throws {
        // Convert to Message format expected by existing API
        var apiMessages: [Message] = []

        for msg in messages {
            guard let role = msg["role"], let content = msg["content"] else { continue }

            let messageRole: MessageRole
            switch role {
            case "assistant":
                messageRole = .assistant
            case "system":
                messageRole = .system
            default:
                messageRole = .user
            }

            apiMessages.append(Message(
                id: UUID().uuidString,
                conversationId: "live",
                role: messageRole,
                content: content,
                hiddenReason: nil,
                timestamp: Date(),
                tokens: nil,
                artifacts: nil,
                toolCalls: nil,
                isStreaming: false,
                modelName: nil,
                providerName: nil,
                attachments: nil
            ))
        }

        // Use the existing streaming generation with callback
        // Note: This may need adjustment based on actual MLXModelService API
        for try await token in generateStreamingAsync(
            systemPrompt: systemPrompt,
            messages: apiMessages,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            repetitionPenalty: repetitionPenalty,
            repetitionContextSize: repetitionContextSize
        ) {
            onToken(token)
        }
    }

    /// Async stream wrapper for generation
    private func generateStreamingAsync(
        systemPrompt: String?,
        messages: [Message],
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        repetitionPenalty: Double,
        repetitionContextSize: Int
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Call the existing generateStreaming method
                    try await self.generateStreaming(
                        systemPrompt: systemPrompt,
                        messages: messages,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP,
                        repetitionPenalty: repetitionPenalty,
                        repetitionContextSize: repetitionContextSize
                    ) { token in
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
