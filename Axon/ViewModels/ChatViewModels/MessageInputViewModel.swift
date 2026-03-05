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
    let mimePatternsByType: [MessageAttachment.AttachmentType: [String]]
    let description: String

    /// Whether any attachment type is supported
    var supportsAnyAttachment: Bool {
        images || documents || video || audio
    }

    func mimePatterns(for type: MessageAttachment.AttachmentType) -> [String] {
        mimePatternsByType[type] ?? []
    }

    static let none = AttachmentCapability(
        images: false,
        documents: false,
        video: false,
        audio: false,
        mimePatternsByType: [.image: [], .document: [], .video: [], .audio: []],
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
        let policy = AttachmentMimePolicyService.resolvePolicy(conversationId: conversationId, settings: settings)
        return capability(from: policy)
    }

    func resolveAttachmentPolicy() -> AttachmentMimePolicy {
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        return AttachmentMimePolicyService.resolvePolicy(conversationId: conversationId, settings: settings)
    }

    private func capability(from policy: AttachmentMimePolicy) -> AttachmentCapability {
        let images = !(policy.allowedPatternsByType[.image] ?? []).isEmpty
        let documents = !(policy.allowedPatternsByType[.document] ?? []).isEmpty
        let audio = !(policy.allowedPatternsByType[.audio] ?? []).isEmpty
        let video = !(policy.allowedPatternsByType[.video] ?? []).isEmpty

        return AttachmentCapability(
            images: images,
            documents: documents,
            video: video,
            audio: audio,
            mimePatternsByType: policy.allowedPatternsByType,
            description: AttachmentMimePolicyService.capabilityDescription(policy: policy)
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
