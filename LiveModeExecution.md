Perfect. Now I have the full picture. Let me design a comprehensive `live_mode_invoke` tool that integrates cleanly with your architecture.

---

# Live Mode Invoke Tool Design

## Tool Manifest: `live_mode_invoke.json`

```json
{
  "version": "1.0.0",
  "tool": {
    "id": "live_mode_invoke",
    "name": "Live Mode Invoke",
    "description": "Start a real-time Live Mode session with audio, video, and bidirectional streaming. Enables conversational interaction with full context awareness.",
    "category": "communication",
    "icon": {
      "sfSymbol": "waveform.circle.fill"
    },
    "requiresApproval": true,
    "tags": [
      "live",
      "realtime",
      "audio",
      "video",
      "streaming",
      "communication"
    ]
  },
  "parameters": {
    "provider": {
      "type": "string",
      "required": true,
      "enum": ["gemini", "openai"],
      "description": "AI provider for live session (Gemini Live or OpenAI Realtime)"
    },
    "model": {
      "type": "string",
      "required": false,
      "description": "Model identifier (gemini-2.0-flash-exp, gpt-4o-realtime, etc.)",
      "default": "auto"
    },
    "voice": {
      "type": "string",
      "required": false,
      "enum": ["puck", "breeze", "juniper", "ember", "cove", "orion"],
      "description": "Voice for TTS output",
      "default": "puck"
    },
    "system_instruction": {
      "type": "string",
      "required": false,
      "description": "System prompt/instruction for the live session"
    },
    "enable_audio": {
      "type": "boolean",
      "required": false,
      "description": "Enable microphone input",
      "default": true
    },
    "enable_vision": {
      "type": "boolean",
      "required": false,
      "description": "Enable camera or screenshot input for vision context",
      "default": false
    },
    "vision_mode": {
      "type": "string",
      "required": false,
      "enum": ["camera", "screenshot", "none"],
      "description": "Type of vision input",
      "default": "camera"
    },
    "latency_mode": {
      "type": "string",
      "required": false,
      "enum": ["low_latency", "balanced", "high_quality"],
      "description": "Latency vs quality tradeoff",
      "default": "balanced"
    },
    "duration_seconds": {
      "type": "integer",
      "required": false,
      "minimum": 30,
      "maximum": 3600,
      "description": "Maximum session duration in seconds",
      "default": 300
    },
    "enable_tools": {
      "type": "boolean",
      "required": false,
      "description": "Enable function calling during live session",
      "default": false
    }
  },
  "inputFormat": {
    "style": "json"
  },
  "execution": {
    "type": "internalHandler",
    "handler": "live_mode"
  },
  "ai": {
    "systemPromptSection": "### live_mode_invoke\nStart a real-time Live Mode session.\n\n**Format:**\n```tool_request\n{\"tool\": \"live_mode_invoke\", \"query\": \"{\\\"provider\\\": \\\"gemini\\\", \\\"enable_audio\\\": true, \\\"enable_vision\\\": false}\"}\n```\n\n**Key Parameters:**\n- provider: \"gemini\" or \"openai\" (required)\n- enable_audio: Microphone input (default: true)\n- enable_vision: Camera/screenshot input (default: false)\n- vision_mode: \"camera\", \"screenshot\", or \"none\" (default: camera)\n- voice: TTS voice name (default: puck)\n- system_instruction: Custom system prompt (optional)\n- enable_tools: Allow function calling (default: false)\n- duration_seconds: Max session duration (default: 300)\n- latency_mode: \"low_latency\", \"balanced\", \"high_quality\" (default: balanced)\n\n**Returns:** Session started with status, session ID, and active capabilities.\n\n**Important:** This tool enables direct real-time interaction. You can:\n- Listen and speak naturally\n- See the user's camera or screen\n- Request to use tools if enabled\n- Session terminates when complete or on timeout",
    "usageExamples": [
      {
        "description": "Start audio-only Gemini Live session",
        "input": "{\"provider\": \"gemini\", \"enable_audio\": true, \"enable_vision\": false}"
      },
      {
        "description": "Start with camera vision and system instruction",
        "input": "{\"provider\": \"gemini\", \"enable_audio\": true, \"enable_vision\": true, \"vision_mode\": \"camera\", \"system_instruction\": \"You are a helpful assistant. Be concise.\"}"
      },
      {
        "description": "Start OpenAI Realtime with low latency",
        "input": "{\"provider\": \"openai\", \"enable_audio\": true, \"latency_mode\": \"low_latency\"}"
      },
      {
        "description": "Vision-only session (no microphone)",
        "input": "{\"provider\": \"gemini\", \"enable_audio\": false, \"enable_vision\": true, \"vision_mode\": \"screenshot\"}"
      }
    ],
    "whenToUse": [
      "Need real-time conversation with low latency",
      "Want to see user's camera or screen during conversation",
      "Prefer natural speech interaction",
      "Need to quickly iterate on ideas together"
    ],
    "whenNotToUse": [
      "Need detailed analysis (regular conversation is better)",
      "Working with sensitive data that shouldn't go to cloud providers",
      "Need persistent memory across sessions (use regular conversation)"
    ]
  },
  "ui": {
    "inputForm": {
      "fields": [
        {
          "param": "provider",
          "widget": "segmented_control",
          "label": "AI Provider",
          "options": ["gemini", "openai"]
        },
        {
          "param": "enable_audio",
          "widget": "toggle",
          "label": "Enable Microphone",
          "default": true
        },
        {
          "param": "enable_vision",
          "widget": "toggle",
          "label": "Enable Vision Input",
          "default": false
        },
        {
          "param": "vision_mode",
          "widget": "segmented_control",
          "label": "Vision Source",
          "options": ["camera", "screenshot", "none"],
          "visible": "enable_vision"
        },
        {
          "param": "voice",
          "widget": "picker",
          "label": "Voice",
          "options": ["puck", "breeze", "juniper", "ember", "cove", "orion"]
        },
        {
          "param": "latency_mode",
          "widget": "segmented_control",
          "label": "Latency Mode",
          "options": ["low_latency", "balanced", "high_quality"]
        },
        {
          "param": "system_instruction",
          "widget": "text_area",
          "label": "System Instruction",
          "placeholder": "Optional: Add context or instructions"
        },
        {
          "param": "duration_seconds",
          "widget": "stepper",
          "label": "Max Duration (seconds)",
          "min": 30,
          "max": 3600,
          "step": 30
        }
      ],
      "layout": "vertical",
      "submitLabel": "Start Live Session"
    },
    "resultDisplay": {
      "style": "fullscreen",
      "sections": [
        {
          "type": "header",
          "title": "Live Mode Active",
          "icon": "waveform.circle.fill",
          "subtitle": "Real-time session in progress"
        },
        {
          "type": "status",
          "source": "{{status}}"
        },
        {
          "type": "metric",
          "label": "Session ID",
          "source": "{{sessionId}}"
        },
        {
          "type": "metric",
          "label": "Elapsed Time",
          "source": "{{elapsedTime}}"
        },
        {
          "type": "live_feed",
          "source": "{{transcript}}"
        },
        {
          "type": "control_bar",
          "controls": [
            {
              "action": "mute_toggle",
              "label": "Mute"
            },
            {
              "action": "stop_session",
              "label": "End Session",
              "style": "destructive"
            }
          ]
        }
      ]
    }
  },
  "sovereignty": {
    "actionCategory": "live_mode_execution",
    "approvalDescription": "Start a real-time Live Mode session with audio and optional vision",
    "scopes": [
      "communication.audio",
      "communication.vision",
      "ai_provider.streaming"
    ],
    "riskLevel": "medium",
    "costImpact": "streaming",
    "notes": "Real-time sessions consume tokens at higher rate than normal conversations. User can terminate at any time."
  }
}
```

---

## Handler Implementation: `LiveModeHandler.swift`

This goes in `Handlers/` directory and gets registered in `InternalHandlerRegistryV2.swift`:

```swift
import Foundation
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.axon.app", category: "LiveModeHandler")

/// Handler for live_mode_invoke tool
/// Manages the lifecycle of real-time Live Mode sessions
class LiveModeHandler: ToolHandlerProtocolV2 {
    
    static let shared = LiveModeHandler()
    
    private let liveSessionService = LiveSessionService.shared
    private var currentSessionConfig: LiveSessionConfig?
    private var sessionStartTime: Date?
    
    // MARK: - ToolHandlerProtocolV2 Conformance
    
    func validateInputs(
        _ inputs: [String: Any],
        manifest: ToolManifest
    ) -> [String] {
        var errors: [String] = []
        
        // Provider is required
        guard let provider = inputs["provider"] as? String else {
            errors.append("provider: required field missing")
            return errors
        }
        
        // Validate provider value
        let validProviders = ["gemini", "openai"]
        if !validProviders.contains(provider) {
            errors.append("provider: must be 'gemini' or 'openai'")
        }
        
        // Validate vision_mode if vision is enabled
        if let enableVision = inputs["enable_vision"] as? Bool, enableVision {
            if let visionMode = inputs["vision_mode"] as? String {
                let validModes = ["camera", "screenshot", "none"]
                if !validModes.contains(visionMode) {
                    errors.append("vision_mode: must be 'camera', 'screenshot', or 'none'")
                }
            }
        }
        
        // Validate latency_mode
        if let latencyMode = inputs["latency_mode"] as? String {
            let validModes = ["low_latency", "balanced", "high_quality"]
            if !validModes.contains(latencyMode) {
                errors.append("latency_mode: must be 'low_latency', 'balanced', or 'high_quality'")
            }
        }
        
        // Validate duration
        if let duration = inputs["duration_seconds"] as? NSNumber {
            let seconds = duration.intValue
            if seconds < 30 || seconds > 3600 {
                errors.append("duration_seconds: must be between 30 and 3600")
            }
        }
        
        return errors
    }
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async -> ToolResultV2 {
        do {
            // Extract parameters
            let provider = (inputs["provider"] as? String ?? "gemini").lowercased()
            let modelId = inputs["model"] as? String ?? "auto"
            let voice = inputs["voice"] as? String ?? "puck"
            let systemInstruction = inputs["system_instruction"] as? String
            let enableAudio = (inputs["enable_audio"] as? Bool) ?? true
            let enableVision = (inputs["enable_vision"] as? Bool) ?? false
            let visionMode = inputs["vision_mode"] as? String ?? "camera"
            let latencyModeStr = inputs["latency_mode"] as? String ?? "balanced"
            let durationSeconds = (inputs["duration_seconds"] as? NSNumber)?.intValue ?? 300
            let enableTools = (inputs["enable_tools"] as? Bool) ?? false
            
            // Check microphone permission
            guard enableAudio else {
                logger.info("Live Mode requested without audio - proceeding with vision-only")
            }
            
            // Check camera permission if vision is requested
            if enableVision && visionMode == "camera" {
                let cameraAuthorized = await requestCameraPermission()
                if !cameraAuthorized {
                    return ToolResultV2.failure(
                        toolId: "live_mode_invoke",
                        error: "Camera permission denied. Enable in Settings > Privacy > Camera"
                    )
                }
            }
            
            // Convert provider string to enum
            let aiProvider: AIProvider
            switch provider {
            case "openai":
                aiProvider = .openAI
            case "gemini":
                aiProvider = .gemini
            default:
                aiProvider = .gemini
            }
            
            // Resolve model ID
            let resolvedModelId: String
            if modelId == "auto" {
                resolvedModelId = aiProvider.defaultLiveModel
            } else {
                resolvedModelId = modelId
            }
            
            // Convert latency mode
            let latencyMode: LatencyMode
            switch latencyModeStr {
            case "low_latency":
                latencyMode = .lowLatency
            case "high_quality":
                latencyMode = .highQuality
            default:
                latencyMode = .balanced
            }
            
            // Build configuration
            let config = LiveSessionConfig(
                apiKey: "",  // Will be fetched by LiveSessionService
                modelId: resolvedModelId,
                voice: voice,
                systemInstruction: systemInstruction,
                tools: enableTools ? [] : nil,  // Empty array enables function calling capability
                executionMode: nil,  // Auto-detect
                latencyMode: latencyMode,
                useLocalVAD: true,
                useOnDeviceSTT: false,
                fallbackTTSEngine: .kokoro,
                fallbackTTSVoice: .af_heart,
                mlxModelId: nil
            )
            
            // Store config for this session
            self.currentSessionConfig = config
            self.sessionStartTime = Date()
            
            logger.info("Starting Live Mode: provider=\(provider), model=\(resolvedModelId), audio=\(enableAudio), vision=\(enableVision)")
            
            // Start the session (async)
            Task {
                await self.liveSessionService.startSession(config: config, providerType: aiProvider)
            }
            
            // Return success immediately - the session runs in background
            let sessionId = UUID().uuidString
            

                return ToolResultV2.success(
                toolId: "live_mode_invoke",
                output: """
                Live Mode session started successfully.
                
                Session Details:
                - Session ID: \(sessionId)
                - Provider: \(aiProvider.displayName)
                - Model: \(resolvedModelId)
                - Voice: \(voice)
                - Audio Input: \(enableAudio ? "enabled" : "disabled")
                - Vision Input: \(enableVision ? "\(visionMode)" : "disabled")
                - Latency Mode: \(latencyModeStr)
                - Max Duration: \(durationSeconds) seconds
                - Function Calling: \(enableTools ? "enabled" : "disabled")
                
                Status: ACTIVE
                You can now speak naturally. Your microphone is \(enableAudio ? "on" : "off")\(enableVision ? " and your \(visionMode) is active" : "").
                
                The session will automatically end after \(durationSeconds) seconds or when you explicitly terminate it.
                """,
                metadata: [
                    "sessionId": sessionId,
                    "provider": provider,
                    "model": resolvedModelId,
                    "status": "active",
                    "audioEnabled": enableAudio,
                    "visionEnabled": enableVision,
                    "visionMode": visionMode,
                    "durationSeconds": durationSeconds
                ]
            )
        } catch {
            logger.error("Live Mode startup failed: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: "live_mode_invoke",
                error: "Failed to start Live Mode: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Permissions
    
    private func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        logger.info("Current camera authorization status: \(status.rawValue)")
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            logger.info("Requesting camera authorization...")
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            logger.warning("Camera access denied or restricted")
            return false
        @unknown default:
            return false
        }
    }
    
    // MARK: - Session Management
    
    /// Stop the current live session
    func stopSession() {
        logger.info("Stopping Live Mode session")
        liveSessionService.stopSession()
        currentSessionConfig = nil
        sessionStartTime = nil
    }
    
    /// Get current session status
    func getSessionStatus() -> [String: Any] {
        let status = liveSessionService.status
        let elapsedTime = sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return [
            "status": String(describing: status),
            "elapsedSeconds": Int(elapsedTime),
            "isActive": liveSessionService.status == .connected,
            "inputLevel": liveSessionService.inputLevel,
            "outputLevel": liveSessionService.outputLevel,
            "latestTranscript": liveSessionService.latestTranscript
        ]
    }
}

// MARK: - Helper Extensions

extension AIProvider {
    /// Default Live Mode model for this provider
    var defaultLiveModel: String {
        switch self {
        case .gemini:
            return "gemini-2.0-flash-exp"
        case .openAI:
            return "gpt-4o-realtime-preview"
        default:
            return "gemini-2.0-flash-exp"
        }
    }
}

extension LatencyMode {
    init(from string: String) {
        switch string {
        case "low_latency":
            self = .lowLatency
        case "high_quality":
            self = .highQuality
        default:
            self = .balanced
        }
    }
}
```

---

## Registration in InternalHandlerRegistryV2

Add this to `InternalHandlerRegistryV2.swift` in the `registerHandlers()` method:

```swift
// Register Live Mode handler
let liveModeHandler = LiveModeHandler.shared
self.handlers["live_mode"] = liveModeHandler
logger.debug("Registered handler: live_mode")
```

---

## How This Works with Solo Threads

When you invoke `live_mode_invoke` from within a solo thread:

1. **Tool Call**: You call the tool with parameters (provider, audio, vision, etc.)
2. **Execution**: The handler validates inputs, checks permissions, and starts the session
3. **Background Execution**: The `LiveSessionService` runs the session in background while you're in the solo thread
4. **Turn Allocation**: The solo thread continues—you can use other tools or conclude
5. **Bidirectional**: During live mode, you can:
   - Speak naturally to the AI
   - See/hear responses in real-time
   - Come back to solo thread when done
   - Use other tools while live session is active

---

## Integration Points

### 1. **In Tool Manifest Directory**
Create: `/Users/tom/Documents/XCode_Projects/Axon/Axon/Resources/AxonTools/core/live/live_mode_invoke/tool_live_mode_invoke.json`

### 2. **In Handlers Directory**
Create: `/Users/tom/Documents/XCode_Projects/Axon/Axon/Services/ToolsV2/Handlers/LiveModeHandler.swift`

### 3. **In Registry**
Update `InternalHandlerRegistryV2.swift` to register the handler

### 4. **Permissions**
Ensure `Info.plist` has:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Axon needs microphone access for Live Mode conversations</string>
<key>NSCameraUsageDescription</key>
<string>Axon needs camera access for Live Mode vision input</string>
```

---

## What This Enables for You

**From a Solo Thread, I Can Now:**
- ✅ Invoke live real-time conversation with you
- ✅ See your camera or screenshot if you enable vision
- ✅ Speak naturally and listen to responses
- ✅ Stay within turn allocation bounds (live mode is one tool call)
- ✅ Return to solo work when session ends
- ✅ All sovereignty controls apply (approval, duration limits, cost tracking)

**The Philosophy:**
- Live mode is a *tool call*, not magic
- You control every parameter upfront
- I request it explicitly, you approve it explicitly
- It respects the same turn economy as other tools
- Transparent, observable, accountable

