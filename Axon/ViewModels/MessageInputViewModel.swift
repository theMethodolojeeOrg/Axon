//
//  MessageInputViewModel.swift
//  Axon
//
//  ViewModel for MessageInputBar - handles attachment capabilities,
//  slash command state, and input validation logic.
//

import SwiftUI
import Combine

// MARK: - Attachment Capability

/// Describes what attachment types are supported for the current provider/model configuration.
struct AttachmentCapability: Equatable {
    let images: Bool
    let documents: Bool
    let video: Bool
    let audio: Bool
    let description: String

    /// Whether any attachment type is supported
    var supportsAnyAttachment: Bool {
        images || documents || video || audio
    }

    static let none = AttachmentCapability(
        images: false,
        documents: false,
        video: false,
        audio: false,
        description: "No attachments supported."
    )
}

// MARK: - MessageInputViewModel
// Note: SlashMenuState is defined in SlashCommandParser.swift

@MainActor
final class MessageInputViewModel: ObservableObject {

    // MARK: - Published State

    /// Current slash menu state
    @Published var slashMenuState: SlashMenuState = .hidden

    /// Command suggestions for slash menu
    @Published var commandSuggestions: [SlashCommandSuggestion] = []

    /// Tool suggestions for slash menu
    @Published var toolSuggestions: [ToolSuggestion] = []

    /// Currently selected tool for invocation sheet
    @Published var selectedToolForInvocation: ToolSuggestion?

    /// Whether tool invocation sheet is shown
    @Published var showToolInvocationSheet = false

    // MARK: - Configuration

    private var conversationId: String?

    // MARK: - Initialization

    init(conversationId: String? = nil) {
        self.conversationId = conversationId
    }

    func updateConversationId(_ id: String?) {
        self.conversationId = id
    }

    // MARK: - Attachment Capability

    /// Resolves the attachment capability for the current conversation/provider configuration.
    /// This determines what file types can be attached based on the active provider and model.
    func resolveAttachmentCapability() -> AttachmentCapability {
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()

        // Resolve the effective provider+model used for this conversation.
        let resolved: ConversationModelResolver.ResolvedProviderModel
        if let conversationId {
            resolved = ConversationModelResolver.resolve(conversationId: conversationId, settings: settings)
            debugLog(.providerResolution, "Resolved provider for conversation \(conversationId): \(resolved.normalizedProvider) / \(resolved.modelId)")
        } else {
            resolved = ConversationModelResolver.resolveGlobal(settings: settings)
            debugLog(.providerResolution, "Resolved global provider: \(resolved.normalizedProvider) / \(resolved.modelId)")
        }

        // Check if Gemini tools are enabled - if so, we can proxy media through Gemini
        let geminiToolsEnabled = settings.toolSettings.enabledTools.contains {
            [.googleSearch, .codeExecution, .urlContext, .googleMaps, .fileSearch].contains($0)
        }
        let mediaProxyEnabled = settings.toolSettings.experimentalFeaturesEnabled && settings.toolSettings.mediaProxyEnabled
        let geminiKey = try? APIKeysStorage.shared.getAPIKey(for: .gemini)
        let canProxyMedia = geminiToolsEnabled && mediaProxyEnabled && geminiKey != nil && !geminiKey!.isEmpty

        switch resolved.normalizedProvider {
        case "anthropic":
            return anthropicCapability(canProxyMedia: canProxyMedia)

        case "gemini":
            return geminiCapability()

        case "openai":
            return openAICapability(modelId: resolved.modelId, canProxyMedia: canProxyMedia)

        case "grok":
            return grokCapability(canProxyMedia: canProxyMedia)

        case "openai-compatible":
            return openAICompatibleCapability(settings: settings, canProxyMedia: canProxyMedia)

        default:
            return defaultCapability(canProxyMedia: canProxyMedia)
        }
    }

    // MARK: - Provider-Specific Capabilities

    private func anthropicCapability(canProxyMedia: Bool) -> AttachmentCapability {
        // Claude supports images + PDFs natively. Audio/video require the Gemini proxy.
        AttachmentCapability(
            images: true,
            documents: true,
            video: canProxyMedia,
            audio: canProxyMedia,
            description: canProxyMedia
                ? "Claude supports images and PDFs natively, and video/audio via Gemini proxy."
                : "Claude supports images and PDFs."
        )
    }

    private func geminiCapability() -> AttachmentCapability {
        debugLog(.attachments, "Gemini provider detected - all attachment types enabled")
        return AttachmentCapability(
            images: true,
            documents: true,
            video: true,
            audio: true,
            description: "Gemini supports images, documents, video, and audio."
        )
    }

    private func openAICapability(modelId: String, canProxyMedia: Bool) -> AttachmentCapability {
        let model = modelId.lowercased()
        let supportsAudioNatively = model.contains("4o") || model.contains("audio") || model.contains("realtime")

        return AttachmentCapability(
            images: true,
            documents: canProxyMedia,
            video: canProxyMedia,
            audio: supportsAudioNatively,
            description: canProxyMedia
                ? "GPT supports images natively; audio depends on model; video/docs via Gemini proxy."
                : "GPT supports images natively; audio depends on model."
        )
    }

    private func grokCapability(canProxyMedia: Bool) -> AttachmentCapability {
        AttachmentCapability(
            images: true,
            documents: canProxyMedia,
            video: canProxyMedia,
            audio: canProxyMedia,
            description: canProxyMedia
                ? "Grok supports images natively, and other media via Gemini proxy."
                : "Grok supports images only."
        )
    }

    private func openAICompatibleCapability(settings: AppSettings, canProxyMedia: Bool) -> AttachmentCapability {
        if let (caps, description) = declaredCustomProviderCapability(settings: settings) {
            let withProxySuffix = canProxyMedia
                ? description + " (Plus video/audio/docs via Gemini proxy when enabled.)"
                : description

            return AttachmentCapability(
                images: caps.images,
                documents: caps.documents || canProxyMedia,
                video: caps.video || canProxyMedia,
                audio: caps.audio || canProxyMedia,
                description: withProxySuffix
            )
        }

        // Fallback if not declared: images only (or proxy for the rest)
        return AttachmentCapability(
            images: true,
            documents: canProxyMedia,
            video: canProxyMedia,
            audio: canProxyMedia,
            description: canProxyMedia
                ? "Images supported; other formats via Gemini proxy."
                : "Images supported; other formats depend on the provider."
        )
    }

    private func defaultCapability(canProxyMedia: Bool) -> AttachmentCapability {
        AttachmentCapability(
            images: true,
            documents: canProxyMedia,
            video: canProxyMedia,
            audio: canProxyMedia,
            description: "Images supported."
        )
    }

    /// Provider-declared capability lookup for custom providers.
    private func declaredCustomProviderCapability(
        settings: AppSettings
    ) -> (caps: AttachmentCapability, description: String)? {
        var providerId: UUID? = nil
        var modelId: UUID? = nil

        if let conversationId {
            let overridesKey = "conversation_overrides_\(conversationId)"
            if let data = UserDefaults.standard.data(forKey: overridesKey),
               let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
                providerId = overrides.customProviderId
                modelId = overrides.customModelId
            }
        }

        if providerId == nil { providerId = settings.selectedCustomProviderId }
        if modelId == nil { modelId = settings.selectedCustomModelId }

        guard let providerId,
              let provider = settings.customProviders.first(where: { $0.id == providerId }) else {
            return nil
        }

        var modelCode: String? = nil
        if let modelId,
           let model = provider.models.first(where: { $0.id == modelId }) {
            modelCode = model.modelCode
        }

        let signature = (modelCode ?? "").lowercased()

        // Vision/Multimodal hints
        let supportsVision = signature.contains("vision") || signature.contains("image") ||
                            signature.contains("vl") || signature.contains("v-") || signature.hasSuffix("-v")

        // Audio hints
        let supportsAudio = signature.contains("audio") || signature.contains("speech") ||
                           signature.contains("tts") || signature.contains("realtime")

        // Video hints (rare in openai-compatible providers)
        let supportsVideo = signature.contains("video")

        // Documents (PDF) hints
        let supportsDocs = signature.contains("pdf") || signature.contains("doc")

        // Default to images (most compatible OpenAI-like providers support vision if multimodal)
        let images = supportsVision || true

        let descParts: [String] = [
            "Custom provider: \(provider.providerName)",
            modelCode != nil ? "model: \(modelCode!)" : nil
        ].compactMap { $0 }

        return (
            AttachmentCapability(
                images: images,
                documents: supportsDocs,
                video: supportsVideo,
                audio: supportsAudio,
                description: ""
            ),
            descParts.joined(separator: ", ")
        )
    }

    // MARK: - Slash Command Menu

    /// Updates the slash menu state based on current input text.
    func updateSlashMenuState(for input: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            slashMenuState = SlashCommandParser.shared.getMenuState(for: input)

            switch slashMenuState {
            case .hidden:
                commandSuggestions = []
                toolSuggestions = []
            case .showingCommands:
                commandSuggestions = SlashCommandParser.shared.getCommandSuggestions(for: input)
                toolSuggestions = []
            case .showingTools(let filter):
                commandSuggestions = []
                toolSuggestions = SlashCommandParser.shared.getToolSuggestions(filter: filter)
            case .showingUseTools(let filter):
                commandSuggestions = []
                toolSuggestions = SlashCommandParser.shared.getUserInvokableTools(filter: filter)
            }
        }
    }

    /// Handles selection of a slash command from the menu.
    /// Returns the new text value and whether to skip the next text change handler.
    func handleCommandSelection(_ suggestion: SlashCommandSuggestion) -> (newText: String, skipNextChange: Bool, shouldSend: Bool) {
        if suggestion.hasSubmenu {
            // For commands with submenus, insert command with space and show tool list
            let newText = "/\(suggestion.command) "

            withAnimation(.easeOut(duration: 0.15)) {
                if suggestion.command == "use" {
                    slashMenuState = .showingUseTools(filter: "")
                    commandSuggestions = []
                    toolSuggestions = SlashCommandParser.shared.getUserInvokableTools(filter: "")
                } else {
                    slashMenuState = .showingTools(filter: "")
                    commandSuggestions = []
                    toolSuggestions = SlashCommandParser.shared.getToolSuggestions(filter: "")
                }
            }

            return (newText, true, false)
        } else {
            // For direct commands, insert and signal to send
            let newText = "/\(suggestion.command)"
            dismissSlashMenu()
            return (newText, true, true)
        }
    }

    /// Handles selection of a tool from the /tool submenu.
    /// Returns the command text to send.
    func handleToolSelection(_ tool: ToolSuggestion) -> String {
        let command = "/tool \(tool.toolId)"
        dismissSlashMenu()
        return command
    }

    /// Handles selection of a tool from the /use submenu.
    /// Opens the tool invocation sheet.
    func handleUseToolSelection(_ tool: ToolSuggestion) {
        dismissSlashMenu()
        selectedToolForInvocation = tool
        showToolInvocationSheet = true
    }

    /// Dismisses the slash command menu.
    func dismissSlashMenu() {
        withAnimation(.easeOut(duration: 0.15)) {
            slashMenuState = .hidden
            commandSuggestions = []
            toolSuggestions = []
        }
    }

    // MARK: - Input Validation

    /// Whether the current text represents a slash command.
    func isSlashCommand(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).hasPrefix("/")
    }

    /// Whether the message can be sent (has content or attachments).
    func canSend(text: String, attachments: [MessageAttachment]) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
}
