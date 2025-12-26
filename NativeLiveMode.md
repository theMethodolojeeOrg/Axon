# Axon-Native Live Mode: Comprehensive Implementation Plan

## Overview

Create a universal, provider-agnostic Live system that works with ANY AI model, from Gemini/OpenAI Realtime APIs to standard chat APIs and on-device MLX models. The system will automatically detect capabilities and adapt its behavior accordingly.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                  LiveSessionService                        │
│              (Central Orchestrator)                        │
│  - Audio I/O Management                                   │
│  - Connection Lifecycle                                   │
│  - Capability Detection                                   │
│  - Provider Selection                                     │
└──────────────┬────────────────────────────────────────────┘
               │
               ├── LiveProviderFactory
               │    - Detects model capabilities
               │    - Creates appropriate provider
               │    - Manages provider registry
               │
               ├── Provider Types
               │    ├── NativeDuplexProvider (Gemini, OpenAI Realtime)
               │    ├── StreamingHTTPLiveProvider (Any chat API)
               │    ├── OnDeviceMLXProvider (Local models)
               │    └── CustomProvider (User-defined)
               │
               └── Sub-Systems
                    ├── VoiceActivityDetector (Local VAD)
                    ├── SpeechRecognitionService (On-device STT)
                    ├── KokoroTTSService (On-device TTS)
                    └── AudioProcessingPipeline
```

## Core Components

### 1. LiveProviderCapabilities (Self-Discovery)

```swift
struct LiveProviderCapabilities: Codable {
    // Audio capabilities
    let supportsStreamingAudio: Bool
    let supportsRealtimeDuplex: Bool
    let requiresWebSocket: Bool
    let supportsServerSideVAD: Bool
    
    // Communication capabilities
    let supportsFunctionCalling: Bool
    let supportsVision: Bool
    let supportsMultimodal: Bool
    
    // Audio configuration
    let maxSampleRate: Int?
    let supportedAudioFormats: [AudioFormat]
    let audioLatencyMode: LatencyMode
    
    // Execution mode
    let executionMode: ExecutionMode
}

enum ExecutionMode: String, Codable {
    case cloudWebSocket      // Gemini, OpenAI Realtime
    case cloudHTTPStreaming   // Standard chat APIs
    case onDeviceMLX         // Local MLX models
    case custom              // User-defined
}

enum LatencyMode: String, Codable, CaseIterable {
    case ultra    // Minimize latency (may reduce quality)
    case balanced // Default balance
    case quality  // Maximize quality (may increase latency)
}

enum AudioFormat: String, Codable {
    case pcm16_24k_mono = "pcm16_24k_mono"
    case pcm16_16k_mono = "pcm16_16k_mono"
    case float32_48k_stereo = "float32_48k_stereo"
}
```

### 2. LiveProviderFactory

```swift
class LiveProviderFactory {
    /// Create the appropriate provider based on model capabilities
    static func createProvider(
        for model: AIModel,
        config: LiveSessionConfig
    ) async throws -> LiveProviderProtocol
    
    /// Auto-detect capabilities for a model
    static func detectCapabilities(
        for model: AIModel
    ) -> LiveProviderCapabilities
    
    /// Register custom providers
    static func registerCustomProvider(
        _ provider: CustomProviderConfig
    ) throws
}
```

### 3. Enhanced LiveProviderProtocol

```swift
protocol LiveProviderProtocol: AnyObject {
    var id: String { get }
    var delegate: LiveProviderDelegate? { get set }
    var capabilities: LiveProviderCapabilities { get }
    
    // Lifecycle
    func connect(config: LiveSessionConfig) async throws
    func disconnect()
    
    // Input
    func sendAudio(buffer: AVAudioPCMBuffer)
    func sendText(_ text: String)
    func sendImage(_ image: Data) // For vision models
    
    // Configuration
    func updateConfig(_ config: LiveSessionConfig) async throws
}

protocol LiveProviderDelegate: AnyObject {
    func onAudioData(_ data: Data)
    func onTextDelta(_ text: String)
    func onTranscript(_ text: String, role: String)
    func onStatusChange(_ status: LiveSessionStatus)
    func onError(_ error: Error)
    func onToolCall(name: String, args: [String: Any], id: String)
    func onCapabilityChange(_ capabilities: LiveProviderCapabilities)
}
```

### 4. VoiceActivityDetector (Local VAD)

```swift
@MainActor
class VoiceActivityDetector: ObservableObject {
    static let shared = VoiceActivityDetector()
    
    @Published var isSpeaking: Bool = false
    @Published var speechProbability: Float = 0.0
    
    // On-device energy-based VAD (no ML dependency)
    private func detectSpeech(in buffer: AVAudioPCMBuffer) -> Bool
    
    // Optional: Use CoreML-based VAD for higher accuracy
    private func detectSpeechML(in buffer: AVAudioPCMBuffer) -> Bool
}
```

### 5. SpeechRecognitionService (On-Device STT)

```swift
@MainActor
class SpeechRecognitionService: NSObject, ObservableObject {
    static let shared = SpeechRecognitionService()
    
    @Published var isListening: Bool = false
    @Published var partialTranscript: String = ""
    @Published var finalTranscript: String = ""
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Start real-time speech recognition
    func startRecognition(audioEngine: AVAudioEngine) async throws
    
    // Stop recognition
    func stopRecognition()
    
    // Reset transcript
    func reset()
}
```

### 6. OnDeviceMLXProvider (Local Models)

```swift
class OnDeviceMLXProvider: LiveProviderProtocol {
    let id = "mlx-ondevice"
    weak var delegate: LiveProviderDelegate?
    var capabilities: LiveProviderCapabilities
    
    private var mlxModel: MLXModel?
    private var tokenizer: Tokenizer?
    
    // Supported MLX models
    enum MLXModelType: String, CaseIterable {
        case gemma3n = "mlx-community/gemma-3n-E2B-it-3bit"
        case qwen3vl = "mlx-community/Qwen3-VL-2B-Thinking-MLX-4bit"
        // Add more as needed
    }
    
    func connect(config: LiveSessionConfig) async throws {
        // Load MLX model
        // Initialize tokenizer
        // Start inference loop
    }
    
    func sendAudio(buffer: AVAudioPCMBuffer) {
        // Transcribe using on-device STT
        // Send transcript to model
    }
}
```

### 7. StreamingHTTPLiveProvider (Universal Fallback)

```swift
class StreamingHTTPLiveProvider: LiveProviderProtocol {
    let id = "http-streaming"
    weak var delegate: LiveProviderDelegate?
    var capabilities: LiveProviderCapabilities
    
    private var httpClient: APIClient
    private let ttsService: TTSService
    
    func connect(config: LiveSessionConfig) async throws {
        // Standard HTTP streaming chat API
        // Works with ANY model
    }
    
    func sendText(_ text: String) {
        // Send as HTTP request with streaming
        // Receive text response
        // Use TTS for audio output
    }
    
    func sendAudio(buffer: AVAudioPCMBuffer) {
        // Use on-device STT to transcribe
        // Send transcript via HTTP
    }
}
```

## Implementation Plan

### Phase 1: Core Foundation Models & Protocols

#### 1.1 Capability System
- [ ] Create `LiveProviderCapabilities` struct
- [ ] Define `ExecutionMode`, `LatencyMode`, `AudioFormat` enums
- [ ] Create `LiveProviderProtocol` with capability property
- [ ] Extend `LiveProviderDelegate` with capability change callback

#### 1.2 Provider Factory
- [ ] Implement `LiveProviderFactory` class
- [ ] Create capability detection logic for built-in providers
- [ ] Implement provider registry system
- [ ] Add custom provider registration

#### 1.3 Live Configuration
- [ ] Enhance `LiveSessionConfig` with universal options
- [ ] Add MLX model selection
- [ ] Add TTS fallback settings
- [ ] Add VAD configuration

### Phase 2: Sub-Systems

#### 2.1 Voice Activity Detection
- [ ] Implement energy-based VAD algorithm
- [ ] Add configurable sensitivity
- [ ] Add speaking state publishing
- [ ] Create VAD settings UI

#### 2.2 On-Device Speech Recognition
- [ ] Implement `SpeechRecognitionService`
- [ ] Integrate with AVAudioEngine
- [ ] Add real-time transcription
- [ ] Handle permissions and errors
- [ ] Add transcription settings

#### 2.3 TTS Integration
- [ ] Integrate existing `KokoroTTSService`
- [ ] Add default voice selection (Heart/Echo)
- [ ] Implement TTS fallback chain
- [ ] Add TTS configuration to LiveSettings

### Phase 3: Provider Implementations

#### 3.1 NativeDuplexProvider
- [ ] Refactor `GeminiLiveProvider` to implement enhanced protocol
- [ ] Refactor `OpenAILiveProvider` to implement enhanced protocol
- [ ] Add capability metadata
- [ ] Implement dynamic configuration updates

#### 3.2 StreamingHTTPLiveProvider
- [ ] Create new provider class
- [ ] Implement HTTP streaming chat
- [ ] Integrate with on-device STT
- [ ] Integrate with TTS for audio output
- [ ] Support all standard chat APIs

#### 3.3 OnDeviceMLXProvider
- [ ] Create MLX provider class
- [ ] Integrate with existing `MLXModelService`
- [ ] Implement model loading (Gemma-3n, Qwen3-VL)
- [ ] Implement streaming inference
- [ ] Add model-specific optimizations

#### 3.4 CustomProvider
- [ ] Create custom provider framework
- [ ] Define custom provider config schema
- [ ] Implement custom protocol handler
- [ ] Add settings UI for custom providers

### Phase 4: Service Layer Updates

#### 4.1 LiveSessionService Refactor
- [ ] Update to use `LiveProviderFactory`
- [ ] Implement capability-based provider selection
- [ ] Add provider switching during session
- [ ] Integrate VAD and Speech Recognition
- [ ] Integrate TTS fallback chain

#### 4.2 Settings Integration
- [ ] Add LiveSettings to Settings model
- [ ] Create LiveSettings view
- [ ] Add provider selection UI
- [ ] Add MLX model management
- [ ] Add TTS/VAD configuration

#### 4.3 Audio Pipeline
- [ ] Create unified audio processing pipeline
- [ ] Add audio format conversion utilities
- [ ] Implement audio buffering for smooth playback
- [ ] Add audio level monitoring

### Phase 5: UI Updates

#### 5.1 LiveSessionOverlay
- [ ] Add capability indicator
- [ ] Show active provider type
- [ ] Add transcription display
- [ ] Show VAD state
- [ ] Add provider switching button

#### 5.2 Settings Views
- [ ] Create `LiveSettingsView`
- [ ] Add provider selection with capability badges
- [ ] Create `MLXLiveSettingsView`
- [ ] Add TTS voice selector with preview
- [ ] Add VAD sensitivity slider
- [ ] Add latency mode selector

#### 5.3 Model Selection
- [ ] Add live capability indicators to model picker
- [ ] Show recommended providers per model
- [ ] Add on-device model badges
- [ ] Implement per-model Live settings

### Phase 6: MLX Model Support

#### 6.1 Gemma-3n Integration
- [ ] Add Gemma-3n model definition
- [ ] Implement quantized model loading (3-bit)
- [ ] Optimize for live inference
- [ ] Add Gemma-specific tokenization

#### 6.2 Qwen3-VL Integration
- [ ] Add Qwen3-VL model definition
- [ ] Implement vision input handling
- [ ] Optimize for live inference
- [ ] Add thinking mode support

#### 6.3 Model Management
- [ ] Add MLX model download UI
- [ ] Implement model caching
- [ ] Add model size display
- [ ] Show hardware requirements

### Phase 7: Testing & Optimization

#### 7.1 Unit Tests
- [ ] Test provider factory logic
- [ ] Test capability detection
- [ ] Test VAD accuracy
- [ ] Test audio pipeline

#### 7.2 Integration Tests
- [ ] Test each provider type
- [ ] Test provider switching
- [ ] Test MLX model loading
- [ ] Test TTS fallback chain

#### 7.3 Performance Optimization
- [ ] Optimize audio buffering
- [ ] Minimize latency for MLX models
- [ ] Reduce memory footprint
- [ ] Optimize TTS generation speed

#### 7.4 User Experience Polish
- [ ] Add loading animations
- [ ] Improve error messages
- [ ] Add capability explanations
- [ ] Create onboarding flow

### Phase 8: Documentation

- [ ] Architecture documentation
- [ ] API documentation
- [ ] Provider implementation guide
- [ ] Custom provider guide
- [ ] MLX model integration guide

## File Structure

```
Axon/
├── Services/
│   ├── Live/
│   │   ├── Core/
│   │   │   ├── LiveProviderProtocol.swift (enhanced)
│   │   │   ├── LiveProviderCapabilities.swift
│   │   │   ├── LiveProviderFactory.swift
│   │   │   └── LiveSessionConfig.swift (enhanced)
│   │   ├── Providers/
│   │   │   ├── NativeDuplexProvider.swift
│   │   │   ├── StreamingHTTPLiveProvider.swift
│   │   │   ├── OnDeviceMLXProvider.swift
│   │   │   └── CustomProvider.swift
│   │   ├── SubSystems/
│   │   │   ├── VoiceActivityDetector.swift
│   │   │   └── SpeechRecognitionService.swift
│   │   ├── Providers/ (existing)
│   │   │   ├── GeminiLiveProvider.swift (refactor)
│   │   │   └── OpenAILiveProvider.swift (refactor)
│   │   └── LiveSessionService.swift (refactor)
│   ├── LocalModels/
│   │   ├── MLX/
│   │   │   ├── Gemma3nService.swift
│   │   │   └── Qwen3VLService.swift
│   │   └── MLXModelService.swift (extend)
│   └── TTS/
│       └── KokoroTTSService.swift (existing, integrate)
└── Views/
    ├── Live/
    │   ├── LiveSessionOverlay.swift (enhance)
    │   ├── LiveSettingsView.swift (new)
    │   ├── MLXLiveSettingsView.swift (new)
    │   ├── TTSLiveSettingsView.swift (new)
    │   └── ProviderSelectorView.swift (new)
    └── Settings/
        └── LiveSettingsSection.swift (new)
```

## Configuration Examples

### Default LiveSettings
```swift
struct LiveSettings: Codable {
    // Provider selection
    var defaultProvider: AIProvider = .gemini
    var useOnDeviceModels: Bool = false
    var preferredMLXModel: MLXModelType = .gemma3n
    
    // TTS fallback
    var fallbackTTSEngine: TTSEngine = .kokoro
    var defaultKokoroVoice: KokoroTTSVoice = .af_heart // Heart for new users
    
    // VAD settings
    var useLocalVAD: Bool = true
    var vadSensitivity: Float = 0.5
    var vadMode: VADMode = .energyBased
    
    // Latency
    var audioLatencyMode: LatencyMode = .balanced
    var preferRealtime: Bool = true
    
    // Speech recognition
    var useOnDeviceSTT: Bool = true
    var sttLocale: Locale = .current
}

enum VADMode: String, Codable {
    case energyBased    // Fast, no ML
    case mlBased       // More accurate, requires CoreML model
    case hybrid         // Energy for trigger, ML for confirmation
}
```

### LiveSessionConfig
```swift
struct LiveSessionConfig {
    // Core
    let apiKey: String
    let modelId: String
    let voice: String
    let systemInstruction: String?
    let tools: [ToolDefinition]?
    
    // NEW: Universal configuration
    let executionMode: ExecutionMode?
    let latencyMode: LatencyMode
    let useLocalVAD: Bool
    let useOnDeviceSTT: Bool
    
    // NEW: TTS fallback
    let fallbackTTSEngine: TTSEngine
    let fallbackTTSVoice: KokoroTTSVoice?
    
    // NEW: MLX configuration
    let mlxModel: MLXModelType?
    let mlxQuantization: Int?
}
```

## Usage Examples

### Starting a Live Session (Universal)

```swift
// Let the factory detect capabilities
let model = AIModel(provider: .openai, modelId: "gpt-4o")
let capabilities = LiveProviderFactory.detectCapabilities(for: model)

let config = LiveSessionConfig(
    apiKey: apiKey,
    modelId: model.modelId,
    voice: "alloy",
    systemInstruction: "You are a helpful assistant",
    tools: availableTools,
    executionMode: nil, // Auto-detect
    latencyMode: .balanced,
    useLocalVAD: true,
    useOnDeviceSTT: true,
    fallbackTTSEngine: .kokoro,
    fallbackTTSVoice: .af_heart, // Default for new users
    mlxModel: nil
)

// Factory creates appropriate provider
let provider = try await LiveProviderFactory.createProvider(
    for: model,
    config: config
)

LiveSessionService.shared.startSession(
    config: config,
    providerType: .openai
)
```

### Using On-Device MLX Model

```swift
let config = LiveSessionConfig(
    apiKey: "", // No API key needed
    modelId: "gemma-3n",
    voice: "af_heart",
    systemInstruction: nil,
    tools: nil,
    executionMode: .onDeviceMLX,
    latencyMode: .ultra,
    useLocalVAD: true,
    useOnDeviceSTT: true,
    fallbackTTSEngine: .kokoro,
    fallbackTTSVoice: .af_heart,
    mlxModel: .gemma3n,
    mlxQuantization: 3
)

LiveSessionService.shared.startSession(
    config: config,
    providerType: .mlx // New provider type
)
```

## Migration Strategy

### Backward Compatibility
- Keep existing `GeminiLiveProvider` and `OpenAILiveProvider` public APIs
- Deprecate direct usage in favor of factory pattern
- Auto-migrate existing LiveSettings
- Maintain old LiveSessionConfig for legacy code

### Migration Steps
1. Deploy new protocol alongside old one
2. Update `LiveSessionService` to use factory internally
3. Update UI to use new settings
4. Deprecate old provider selection
5. Remove old code after grace period

## Performance Considerations

### Audio Pipeline
- Use ring buffers for smooth audio
- Pre-allocate audio buffers
- Minimize format conversions
- Use low-latency audio session

### MLX Models
- Use quantized models for speed
- Optimize tokenization
- Use streaming inference
- Implement response caching

### Memory Management
- Unload unused models
- Implement model warm-up
- Cache frequently used TTS voices
- Monitor memory usage

## Security & Privacy

### On-Device Processing
- All audio processing happens on device when possible
- Only final transcripts sent to cloud providers
- Clear sensitive data from memory after use

### API Keys
- Use existing secure storage
- Never log API keys
- Support per-model key management

### Permissions
- Clearly request microphone permission
- Explain speech recognition usage
- Provide opt-out for on-device STT

## Testing Strategy

### Unit Tests
- Provider factory logic
- Capability detection
- VAD algorithms
- Audio format conversion

### Integration Tests
- End-to-end live sessions
- Provider switching
- MLX model loading
- TTS fallback chain

### Performance Tests
- Audio latency measurements
- Memory usage profiling
- Battery consumption
- Model inference speed

### User Testing
- Beta with power users
- Gather feedback on VAD settings
- Test MLX model quality
- Validate TTS voice preferences

## Success Metrics

- Support for 10+ AI providers
- <100ms latency for on-device VAD
- <500ms end-to-end latency for MLX models
- 95% speech recognition accuracy (on-device)
- Successful TTS fallback 99% of time
- Zero API key leakage
- Memory usage <500MB for live sessions

## Next Steps

1. Review and approve this plan
2. Set up development branch
3. Begin Phase 1 implementation
4. Regular progress reviews
5. Alpha testing with internal users
6. Beta testing with community
7. Production rollout

## Questions for Team

1. Should we support custom WebSockets beyond the standard Live APIs?
2. Do we want to implement CoreML-based VAD or stick with energy-based?
3. Should we cache TTS audio for common phrases?
4. Do we need to support simultaneous multi-model live sessions?
5. What's the priority for additional MLX models beyond Gemma-3n and Qwen3-VL?
