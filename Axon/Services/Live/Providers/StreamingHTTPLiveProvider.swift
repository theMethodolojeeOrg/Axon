import Foundation
import AVFoundation
import os.log

private let httpLiveLog = Logger(subsystem: "com.axon.app", category: "HTTPLive")

/// Live provider that uses HTTP streaming APIs with on-device STT/TTS
/// Enables Live mode for ANY chat API (Anthropic, OpenAI non-realtime, etc.)
final class StreamingHTTPLiveProvider: LiveProviderProtocol {
    let id: String
    weak var delegate: LiveProviderDelegate?

    /// HTTP streaming capabilities - uses STT input and TTS output
    var capabilities: LiveProviderCapabilities {
        .httpStreaming
    }

    // MARK: - Dependencies

    private let vad = VoiceActivityDetector.shared
    private let speechRecognition = SpeechRecognitionService.shared
    private let streamingHandler = StreamingResponseHandler()

    // MARK: - Configuration

    private var currentConfig: LiveSessionConfig?
    private let provider: AIProvider
    private var ttsService: KokoroTTSService?

    // MARK: - State

    private var conversationHistory: [LiveMessage] = []
    private var isProcessing = false
    private var isConnected = false
    private var currentUtterance = ""

    // Simple message structure for Live conversation
    struct LiveMessage {
        let role: String  // "user" or "assistant"
        let content: String
    }

    // MARK: - Initialization

    init(provider: AIProvider, capabilities: LiveProviderCapabilities) {
        self.provider = provider
        self.id = "http-\(provider.rawValue)"
    }

    // MARK: - LiveProviderProtocol

    func connect(config: LiveSessionConfig) async throws {
        httpLiveLog.info("Connecting HTTP Live provider for \(self.provider.rawValue)")
        self.currentConfig = config

        // Request STT authorization
        if config.useOnDeviceSTT {
            let authorized = await speechRecognition.requestAuthorization()
            if !authorized {
                httpLiveLog.warning("Speech recognition not authorized, will use text-only mode")
            }
        }

        // Initialize TTS service
        if config.fallbackTTSEngine == .kokoro {
            do {
                ttsService = KokoroTTSService.shared
                if let tts = ttsService, !tts.isModelLoaded {
                    httpLiveLog.info("Loading Kokoro TTS model...")
                    try await tts.loadModel()
                }
            } catch {
                httpLiveLog.error("Failed to load TTS: \(error.localizedDescription)")
                // Continue without TTS
            }
        }

        // Configure VAD
        if let sensitivity = vadSensitivityFromLatencyMode(config.latencyMode) {
            vad.setSensitivity(sensitivity)
        }
        vad.silenceThresholdMs = config.latencyMode.silenceThresholdMs

        isConnected = true
        delegate?.onStatusChange(.connected)
        httpLiveLog.info("HTTP Live provider connected")
    }

    func disconnect() {
        httpLiveLog.info("Disconnecting HTTP Live provider")
        isConnected = false
        speechRecognition.stopRecognition()
        vad.reset()
        conversationHistory.removeAll()
        currentUtterance = ""
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
                    httpLiveLog.debug("Started speech recognition")
                } catch {
                    httpLiveLog.error("Failed to start STT: \(error.localizedDescription)")
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
                httpLiveLog.info("Utterance complete: \(transcript.prefix(50))...")
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
        httpLiveLog.info("Received text input: \(text.prefix(50))...")

        Task {
            await processUserUtterance(text)
        }
    }

    func sendToolOutput(toolCallId: String, output: String) {
        // Tool output would need to be appended to conversation and trigger new response
        httpLiveLog.info("Tool output received: \(toolCallId)")
        // TODO: Implement tool response handling
    }

    // MARK: - Private Methods

    private func processUserUtterance(_ text: String) async {
        guard !isProcessing, let config = currentConfig else { return }

        isProcessing = true
        delegate?.onTranscript(text, role: "user")

        // Add to conversation history
        conversationHistory.append(LiveMessage(role: "user", content: text))

        do {
            // Build messages for the API
            let messages = buildMessages(systemInstruction: config.systemInstruction)

            // Determine provider string for streaming handler
            let providerString = mapProviderToStreamingProvider(provider)

            let streamConfig = StreamingResponseHandler.StreamingConfig(
                provider: providerString,
                apiKey: config.apiKey,
                model: config.modelId,
                baseUrl: baseUrlForProvider(provider),
                system: config.systemInstruction,
                maxTokens: 2048
            )

            var fullResponse = ""

            // Stream the response
            for try await event in streamingHandler.stream(config: streamConfig, messages: messages) {
                switch event {
                case .textDelta(let delta):
                    fullResponse += delta
                    delegate?.onTextDelta(delta)

                case .completion(let completion):
                    httpLiveLog.info("Stream complete, response length: \(fullResponse.count), tokens: \(completion.tokens?.total ?? 0)")

                case .error(let error):
                    httpLiveLog.error("Streaming error: \(error.localizedDescription)")
                    delegate?.onError(error)

                default:
                    break
                }
            }

            // Add assistant response to history
            if !fullResponse.isEmpty {
                conversationHistory.append(LiveMessage(role: "assistant", content: fullResponse))
                delegate?.onTranscript(fullResponse, role: "assistant")

                // Generate TTS audio
                await generateAndPlayTTS(text: fullResponse)
            }

        } catch {
            httpLiveLog.error("Failed to process utterance: \(error.localizedDescription)")
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
            httpLiveLog.info("Generating TTS with voice: \(voice.rawValue)")

            let audioData = try await tts.generateSpeech(
                text: text,
                voice: voice,
                speed: 1.0
            )

            // Send audio to delegate for playback
            delegate?.onAudioData(audioData)
            httpLiveLog.info("TTS audio generated: \(audioData.count) bytes")

        } catch {
            httpLiveLog.error("TTS generation failed: \(error.localizedDescription)")
        }
    }

    private func buildMessages(systemInstruction: String?) -> [Message] {
        var messages: [Message] = []

        // Add system instruction if present
        if let system = systemInstruction, !system.isEmpty {
            messages.append(Message(
                id: "system",
                conversationId: "live",
                role: .system,
                content: system,
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

        // Add conversation history
        for msg in conversationHistory {
            let role: MessageRole = msg.role == "assistant" ? .assistant : .user
            messages.append(Message(
                id: UUID().uuidString,
                conversationId: "live",
                role: role,
                content: msg.content,
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

        return messages
    }

    private func mapProviderToStreamingProvider(_ provider: AIProvider) -> String {
        switch provider {
        case .anthropic:
            return "anthropic"
        case .openai:
            return "openai"
        case .gemini:
            return "gemini"
        case .xai:
            return "grok"
        case .deepseek:
            return "deepseek"
        case .perplexity, .minimax, .mistral, .zai:
            return "openai-compatible"
        default:
            return "openai-compatible"
        }
    }

    private func baseUrlForProvider(_ provider: AIProvider) -> String? {
        switch provider {
        case .perplexity:
            return "https://api.perplexity.ai/chat/completions"
        case .deepseek:
            return "https://api.deepseek.com/chat/completions"
        case .xai:
            return "https://api.x.ai/v1/chat/completions"
        case .minimax:
            return "https://api.minimax.chat/v1/text/chatcompletion_v2"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        case .zai:
            return nil  // Use default
        default:
            return nil
        }
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

// MARK: - Streaming Event Extension

extension StreamingEvent {
    var eventDescription: String {
        switch self {
        case .textDelta(let text):
            return "Text: \(text.prefix(20))..."
        case .completion:
            return "Completion"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        default:
            return "Unknown event"
        }
    }
}
