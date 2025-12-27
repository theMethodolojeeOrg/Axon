//
//  MessageInputBar.swift
//  Axon
//
//  Message input field with attachment support and tools toggle
//

import SwiftUI
import PhotosUI
import Combine
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Custom Text Editor with Enter/Shift+Enter handling

#if canImport(AppKit)
/// macOS: NSTextView wrapper that handles Enter to send, Shift+Enter for newline.
/// Also supports auto-growing up to `maxHeight`, then scrolling.
struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isDisabled: Bool
    let maxHeight: CGFloat
    @Binding var dynamicHeight: CGFloat
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = ChatNSTextView()

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onSubmit = onSubmit

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView

        // initial size calc
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChatNSTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = !isDisabled
        textView.onSubmit = onSubmit

        context.coordinator.maxHeight = maxHeight
        context.coordinator.dynamicHeight = $dynamicHeight
        context.coordinator.recalculateHeight()

        // Update placeholder (handled via overlay)
        context.coordinator.placeholder = placeholder
        context.coordinator.updatePlaceholder()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatTextEditor
        weak var textView: ChatNSTextView?
        var placeholder: String = ""
        var maxHeight: CGFloat
        var dynamicHeight: Binding<CGFloat>

        init(_ parent: ChatTextEditor) {
            self.parent = parent
            self.placeholder = parent.placeholder
            self.maxHeight = parent.maxHeight
            self.dynamicHeight = parent.$dynamicHeight
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight()
            updatePlaceholder()
        }

        func updatePlaceholder() {
            // Placeholder is handled via the overlay in SwiftUI
        }

        func recalculateHeight() {
            guard let textView else { return }

            // Force layout so usedRect is accurate
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let used = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0
            let insets = textView.textContainerInset.height * 2
            let target = min(maxHeight, max(20, used + insets))

            if abs(dynamicHeight.wrappedValue - target) > 0.5 {
                DispatchQueue.main.async {
                    self.dynamicHeight.wrappedValue = target
                }
            }
        }
    }
}

/// Custom NSTextView that intercepts Enter key
class ChatNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        // Check for Enter key (keyCode 36) without Shift
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            // Enter without shift - submit
            onSubmit?()
            return
        }
        // Otherwise, handle normally (Shift+Enter will insert newline)
        super.keyDown(with: event)
    }
}

#elseif canImport(UIKit)
/// iOS: UITextView wrapper that handles Enter to send, Shift+Enter for newline.
/// Also supports auto-growing up to `maxHeight`, then scrolling.
struct ChatTextEditor: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isDisabled: Bool
    let maxHeight: CGFloat
    @Binding var dynamicHeight: CGFloat
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 17)
        textView.textColor = UIColor.label
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        context.coordinator.textView = textView

        // initial size calc
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        textView.isEditable = !isDisabled

        context.coordinator.onSubmit = onSubmit
        context.coordinator.maxHeight = maxHeight
        context.coordinator.dynamicHeight = $dynamicHeight
        context.coordinator.recalculateHeight()

        // Toggle internal scrolling only once we hit the cap
        textView.isScrollEnabled = dynamicHeight >= maxHeight
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatTextEditor
        weak var textView: UITextView?
        var onSubmit: (() -> Void)?
        var maxHeight: CGFloat
        var dynamicHeight: Binding<CGFloat>

        init(_ parent: ChatTextEditor) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
            self.maxHeight = parent.maxHeight
            self.dynamicHeight = parent.$dynamicHeight
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView else { return }
            let targetSize = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
            let fitted = textView.sizeThatFits(targetSize)

            // Ensure a comfortable single-line height baseline
            let minHeight: CGFloat = 20
            let target = min(maxHeight, max(minHeight, fitted.height))

            if abs(dynamicHeight.wrappedValue - target) > 0.5 {
                DispatchQueue.main.async {
                    self.dynamicHeight.wrappedValue = target
                }
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Check if Enter was pressed (newline character)
            if text == "\n" {
                // Check if hardware keyboard with shift is pressed
                // On iOS, we check if there's a hardware keyboard event
                if let window = textView.window,
                   let keyCommands = window.keyCommands,
                   keyCommands.contains(where: { $0.modifierFlags.contains(.shift) }) {
                    // Shift is held - allow newline
                    return true
                }

                // For software keyboard, we'll use a simple heuristic:
                // If the text already has content and user presses enter, submit
                // This matches common chat app behavior
                let currentText = (textView.text as NSString).replacingCharacters(in: range, with: text)
                let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

                // Submit if there's content
                if !trimmed.isEmpty {
                    // Check if this is a "quick enter" (no shift held on hardware keyboard)
                    // We'll submit on enter for hardware keyboards
                    #if targetEnvironment(macCatalyst)
                    onSubmit?()
                    return false
                    #else
                    // On iOS with software keyboard, allow newlines normally
                    // Users can use the send button to submit
                    return true
                    #endif
                }
            }
            return true
        }
    }
}
#endif

// MARK: - Message Input Bar

struct MessageInputBar: View {
    @Binding var text: String
    @Binding var attachments: [MessageAttachment]
    let isLoading: Bool
    let onSend: () -> Void
    let onStop: (() -> Void)?
    let focus: FocusState<Bool>.Binding?

    private let inputMaxHeight: CGFloat = 120
    @State private var inputHeight: CGFloat = 20

    @State private var selectedItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showVideoImporter = false
    @State private var showAudioImporter = false
    @State private var showAnyFileImporter = false
    @State private var showAttachmentOptions = false  // iOS action sheet

    // Slash Command Menu
    @State private var slashMenuState: SlashMenuState = .hidden
    @State private var commandSuggestions: [SlashCommandSuggestion] = []
    @State private var toolSuggestions: [ToolSuggestion] = []

    // Tool Invocation Sheet (for /use command)
    @State private var showToolInvocationSheet = false
    @State private var selectedToolForInvocation: ToolSuggestion?

    // Flag to prevent onChange from overriding manual state updates
    @State private var skipNextTextChange = false

    // VS Code Bridge
    @ObservedObject private var bridgeServer = BridgeServer.shared

    private let conversationId: String?

    private struct AttachmentCapability {
        let images: Bool
        let documents: Bool
        let video: Bool
        let audio: Bool
        let description: String
    }

    init(
        text: Binding<String>,
        attachments: Binding<[MessageAttachment]> = .constant([]),
        isLoading: Bool,
        onSend: @escaping () -> Void,
        onStop: (() -> Void)? = nil,
        focus: FocusState<Bool>.Binding? = nil,
        conversationId: String? = nil
    ) {
        self._text = text
        self._attachments = attachments
        self.isLoading = isLoading
        self.onSend = onSend
        self.onStop = onStop
        self.focus = focus
        self.conversationId = conversationId
    }

    private var attachmentCapability: AttachmentCapability {
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()

        // Resolve the effective provider+model used for this conversation.
        // This keeps the attachment UI aligned with the actual send path.
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
            // Claude supports images + PDFs natively.
            // Audio/video require the Gemini proxy.
            let supportsVideoAudio = canProxyMedia
            return AttachmentCapability(
                images: true,
                documents: true,
                video: supportsVideoAudio,
                audio: supportsVideoAudio,
                description: supportsVideoAudio
                    ? "Claude supports images and PDFs natively, and video/audio via Gemini proxy."
                    : "Claude supports images and PDFs."
            )

        case "gemini":
            // Gemini supports images, documents, video, and audio.
            debugLog(.attachments, "Gemini provider detected - all attachment types enabled (images, documents, video, audio)")
            return AttachmentCapability(
                images: true,
                documents: true,
                video: true,
                audio: true,
                description: "Gemini supports images, documents, video, and audio."
            )

        case "openai":
            // OpenAI: treat audio as supported for GPT-4o-family models.
            // Video/PDF are still proxied.
            let model = resolved.modelId.lowercased()
            let supportsAudioNatively = model.contains("4o") || model.contains("audio") || model.contains("realtime")
            let supportsVideo = canProxyMedia

            return AttachmentCapability(
                images: true,
                documents: canProxyMedia,
                video: supportsVideo,
                audio: supportsAudioNatively,
                description: supportsVideo
                    ? "GPT supports images natively; audio depends on model; video/docs via Gemini proxy."
                    : "GPT supports images natively; audio depends on model."
            )

        case "grok":
            // Grok is images-only unless proxied.
            let supportsAll = canProxyMedia
            return AttachmentCapability(
                images: true,
                documents: supportsAll,
                video: supportsAll,
                audio: supportsAll,
                description: supportsAll
                    ? "Grok supports images natively, and other media via Gemini proxy."
                    : "Grok supports images only."
            )

        case "openai-compatible":
            // Provider-declared: use the selected custom provider/model from settings/overrides.
            // If your provider doesn't declare capabilities yet, we fall back to conservative defaults.
            if let (caps, description) = declaredCustomProviderCapability(settings: settings, conversationId: conversationId) {
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

        default:
            // Conservative default.
            return AttachmentCapability(
                images: true,
                documents: canProxyMedia,
                video: canProxyMedia,
                audio: canProxyMedia,
                description: "Images supported."
            )
        }
    }

    /// Provider-declared capability lookup for custom providers.
    ///
    /// NOTE: If your `CustomProviderModel`/`CustomProvider` types later grow explicit capability fields,
    /// this should be updated to read those instead of using the heuristics below.
    private func declaredCustomProviderCapability(
        settings: AppSettings,
        conversationId: String?
    ) -> (caps: AttachmentCapability, description: String)? {
        // Identify custom provider + model using the same override precedence used by ConversationService.
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

        // Heuristic: without explicit capability metadata, infer from model code/name.
        // This is a best-effort until the provider schema declares capabilities.
        var modelCode: String? = nil
        if let modelId,
           let model = provider.models.first(where: { $0.id == modelId }) {
            modelCode = model.modelCode
        }

        let signature = (modelCode ?? "").lowercased()

        // Vision/Multimodal hints
        let supportsVision = signature.contains("vision") || signature.contains("image") || signature.contains("vl") || signature.contains("v-") || signature.hasSuffix("-v")

        // Audio hints
        let supportsAudio = signature.contains("audio") || signature.contains("speech") || signature.contains("tts") || signature.contains("realtime")

        // Video hints (rare in openai-compatible providers)
        let supportsVideo = signature.contains("video")

        // Documents (PDF) hints
        let supportsDocs = signature.contains("pdf") || signature.contains("doc")

        // Default to images (most compatible OpenAI-like providers support vision if they are multimodal).
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
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
    
    private func handleSend() {
        guard canSend && !isLoading else { return }
        onSend()
    }
    
    private func handleStop() {
        guard isLoading else { return }
        onStop?()
    }

    // MARK: - Slash Command Menu

    private func updateSlashMenuState(for input: String) {
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
                // Use filtered list for /use (excludes AI-only tools, adds user actions)
                toolSuggestions = SlashCommandParser.shared.getUserInvokableTools(filter: filter)
            }
        }
    }

    private func handleCommandSelection(_ suggestion: SlashCommandSuggestion) {
        if suggestion.hasSubmenu {
            // For commands with submenus (like /tool, /use), insert the command with a space
            // and immediately show the tool list
            // Set flag to prevent onChange from overriding our state
            skipNextTextChange = true
            text = "/\(suggestion.command) "
            // Immediately update state to show tool suggestions
            withAnimation(.easeOut(duration: 0.15)) {
                if suggestion.command == "use" {
                    slashMenuState = .showingUseTools(filter: "")
                    commandSuggestions = []
                    // Use filtered list for /use (excludes AI-only tools, adds user actions)
                    toolSuggestions = SlashCommandParser.shared.getUserInvokableTools(filter: "")
                } else {
                    slashMenuState = .showingTools(filter: "")
                    commandSuggestions = []
                    toolSuggestions = SlashCommandParser.shared.getToolSuggestions(filter: "")
                }
            }
        } else {
            // For direct commands, insert and send immediately
            skipNextTextChange = true
            text = "/\(suggestion.command)"
            dismissSlashMenu()
            // Auto-send after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.handleSend()
            }
        }
    }

    private func handleToolSelection(_ tool: ToolSuggestion) {
        // Insert the full /tool command with the selected tool ID and auto-send
        text = "/tool \(tool.toolId)"
        dismissSlashMenu()
        // Auto-send the command after a brief delay to ensure UI updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.handleSend()
        }
    }

    private func handleUseToolSelection(_ tool: ToolSuggestion) {
        // Clear text and show the tool invocation sheet
        text = ""
        dismissSlashMenu()
        selectedToolForInvocation = tool
        showToolInvocationSheet = true
    }

    private func dismissSlashMenu() {
        withAnimation(.easeOut(duration: 0.15)) {
            slashMenuState = .hidden
            commandSuggestions = []
            toolSuggestions = []
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Slash Command Menu (appears above input)
            if slashMenuState != .hidden {
                VStack {
                    Spacer()
                    SlashCommandMenu(
                        menuState: slashMenuState,
                        commandSuggestions: commandSuggestions,
                        toolSuggestions: toolSuggestions,
                        onSelectCommand: handleCommandSelection,
                        onSelectTool: handleToolSelection,
                        onSelectUseTool: handleUseToolSelection,
                        onDismiss: dismissSlashMenu
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 70) // Position above input bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(1)
            }

            // Main content
            VStack(spacing: 0) {
                // Attachments Preview
                if !attachments.isEmpty {
                    attachmentsPreview
                }

                // Main input bar
                HStack(alignment: .center, spacing: 8) {
                    let capability = attachmentCapability

                    // VS Code Bridge Toggle (macOS only)
                    #if os(macOS)
                    bridgeButton
                    #endif

                    // Attachment Button
                    if capability.images || capability.documents || capability.video || capability.audio {
                        attachmentMenu(capability: capability)
                    }

                    // Text input area
                    textInputArea

                    // Send button
                    sendButton
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(AppColors.substrateSecondary.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(AppColors.glassBorder, lineWidth: 0.5)
                        )
                )
                .background(.ultraThinMaterial.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .onChange(of: text) { _, newText in
            // Skip if we manually set the state (e.g., after tapping a command)
            if skipNextTextChange {
                skipNextTextChange = false
                return
            }
            updateSlashMenuState(for: newText)
        }
        .onChange(of: selectedItem) { _, newItem in
            handlePhotoSelection(newItem)
        }
        // State change observers for debugging
        .onChange(of: showFileImporter) { _, newValue in
            debugLog(.attachments, "showFileImporter changed to \(newValue)")
        }
        .onChange(of: showVideoImporter) { _, newValue in
            debugLog(.attachments, "showVideoImporter changed to \(newValue)")
        }
        .onChange(of: showAudioImporter) { _, newValue in
            debugLog(.attachments, "showAudioImporter changed to \(newValue)")
        }
        .onChange(of: showPhotoPicker) { _, newValue in
            debugLog(.attachments, "showPhotoPicker changed to \(newValue)")
        }
        .onChange(of: showAttachmentOptions) { _, newValue in
            debugLog(.attachments, "showAttachmentOptions (action sheet) changed to \(newValue)")
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: attachmentCapability.documents ? [.pdf, .text, .plainText, .rtf, .image, .item] : [.item],
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (document) callback triggered")
            handleFileImport(result, type: .document)
        }
        .fileImporter(
            isPresented: $showVideoImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg, .mpeg2Video],
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (video) callback triggered")
            handleFileImport(result, type: .video)
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (audio) callback triggered")
            handleFileImport(result, type: .audio)
        }
        // Mac: Any file picker
        .fileImporter(
            isPresented: $showAnyFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (any file) callback triggered")
            handleAnyFileImport(result)
        }
        // Tool Invocation Sheet (for /use command)
        .sheet(isPresented: $showToolInvocationSheet) {
            if let tool = selectedToolForInvocation {
                ToolInvocationSheet(
                    tool: tool,
                    onDismiss: {
                        showToolInvocationSheet = false
                        selectedToolForInvocation = nil
                    },
                    onResult: { result, success in
                        // Insert the result into the text field for the user to send to AI
                        if success {
                            text = "Tool result from \(tool.displayName):\n\n\(result)"
                        }
                    }
                )
            }
        }
        // Photos picker attached at top level to avoid UIContextMenuInteraction warning
        // when dismissing Menu while presenting picker
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
        // iOS: Use confirmationDialog (action sheet) instead of Menu to avoid UIContextMenu timing issues
        #if os(iOS)
        .confirmationDialog(
            "Add Attachment",
            isPresented: $showAttachmentOptions,
            titleVisibility: .visible
        ) {
            let capability = attachmentCapability
            debugLog(.attachments, "confirmationDialog opened - capabilities: images=\(capability.images), docs=\(capability.documents), video=\(capability.video), audio=\(capability.audio)")

            if capability.images {
                Button("Photo Library") {
                    debugLog(.attachments, "User tapped Photo Library")
                    showPhotoPicker = true
                }
            }
            if capability.video {
                Button("Video") {
                    debugLog(.attachments, "User tapped Video - setting showVideoImporter=true")
                    showVideoImporter = true
                }
            }
            if capability.audio {
                Button("Audio") {
                    debugLog(.attachments, "User tapped Audio - setting showAudioImporter=true")
                    showAudioImporter = true
                }
            }
            if capability.documents {
                Button("Document") {
                    debugLog(.attachments, "User tapped Document - setting showFileImporter=true")
                    showFileImporter = true
                }
            }
            Button("Cancel", role: .cancel) {
                debugLog(.attachments, "User cancelled attachment selection")
            }
        } message: {
            Text(attachmentCapability.description)
        }
        #endif
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach($attachments) { $attachment in
                    attachmentPreviewItem(attachment: $attachment)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private func attachmentPreviewItem(attachment: Binding<MessageAttachment>) -> some View {
        ZStack(alignment: .topTrailing) {
            // Preview
            if attachment.wrappedValue.type == .image,
               let base64 = attachment.wrappedValue.base64,
               let data = Data(base64Encoded: base64),
               let image = PlatformImageCodec.image(from: data) {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .cornerRadius(10)
                    .clipped()
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .cornerRadius(10)
                    .clipped()
                #else
                EmptyView()
                #endif
            } else {
                VStack(spacing: 4) {
                    Image(systemName: attachmentIcon(for: attachment.wrappedValue.type))
                        .font(.system(size: 20))
                        .foregroundColor(attachmentIconColor(for: attachment.wrappedValue.type))
                    Text(attachment.wrappedValue.name ?? (attachment.wrappedValue.type == .image ? "Image" : "File"))
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(width: 56, height: 56)
                .background(AppColors.substrateTertiary)
                .cornerRadius(10)
            }

            // Remove button
            Button(action: {
                if let index = attachments.firstIndex(where: { $0.id == attachment.wrappedValue.id }) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        attachments.remove(at: index)
                    }
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .red)
            }
            .offset(x: 6, y: -6)
        }
    }
    
    @ViewBuilder
    private func attachmentMenu(capability: AttachmentCapability) -> some View {
        #if os(iOS)
        // iOS: Use button that triggers confirmationDialog (avoids UIContextMenu timing issues)
        Button {
            debugLog(.attachments, "Attachment button tapped - opening action sheet")
            showAttachmentOptions = true
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(AppColors.textSecondary)
            .frame(width: 36, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #else
        // macOS: Keep Menu (works fine, no UIContextMenu timing issues)
        Menu {
            Button(action: { showAnyFileImporter = true }) {
                Label("Choose File...", systemImage: "folder")
            }
            Divider()
            if capability.images {
                Button(action: { showPhotoPicker = true }) {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
            }
            if capability.video {
                Button(action: { showVideoImporter = true }) {
                    Label("Video", systemImage: "video")
                }
            }
            if capability.audio {
                Button(action: { showAudioImporter = true }) {
                    Label("Audio", systemImage: "waveform")
                }
            }
            if capability.documents {
                Button(action: { showFileImporter = true }) {
                    Label("Document", systemImage: "doc")
                }
            }
            Divider()
            Text(capability.description)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "paperclip")
                    .font(.system(size: 18, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(AppColors.textSecondary)
            .frame(width: 36, height: 32)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        #endif
    }

    /// Whether the current input is a slash command
    private var isSlashCommand: Bool {
        text.trimmingCharacters(in: .whitespaces).hasPrefix("/")
    }

    @ViewBuilder
    private var textInputArea: some View {
        ZStack(alignment: .leading) {
            // Placeholder with slash command hint
            if text.isEmpty {
                Text("Message or /tool...")
                    .font(.system(size: 15))
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            // Custom text editor with Enter handling
            ChatTextEditor(
                text: $text,
                placeholder: "Message or /tool...",
                isDisabled: isLoading,
                maxHeight: inputMaxHeight,
                dynamicHeight: $inputHeight,
                onSubmit: handleSend
            )
            .frame(height: inputHeight)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.substrateTertiary.opacity(0.4))
        )
        .overlay(
            // Visual indicator when typing a slash command
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSlashCommand ? AppColors.signalMercury.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isSlashCommand)
    }
    
    @ViewBuilder
    private var sendButton: some View {
        Button(action: isLoading ? handleStop : handleSend) {
            Group {
                if isLoading {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(isLoading ? .white.opacity(0.3) : (canSend ? AppColors.signalLichen : AppColors.textDisabled.opacity(0.3)))
                    .shadow(color: canSend && !isLoading ? AppColors.signalLichen.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isLoading && !canSend)
        .animation(.easeInOut(duration: 0.15), value: canSend)
        .animation(.easeInOut(duration: 0.15), value: isLoading)
        .scaleEffect(canSend || isLoading ? 1.0 : 0.95)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: canSend)
    }

    #if os(macOS)
    @ViewBuilder
    private var bridgeButton: some View {
        Button {
            Task {
                if bridgeServer.isRunning {
                    await bridgeServer.stop()
                } else {
                    await bridgeServer.start()
                }
            }
        } label: {
            Image(systemName: bridgeIconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(bridgeIconColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(bridgeTooltip)
    }

    private var bridgeIconName: String {
        if bridgeServer.isConnected {
            return "personalhotspot"
        } else if bridgeServer.isRunning {
            return "personalhotspot"
        } else {
            return "personalhotspot.slash"
        }
    }

    private var bridgeIconColor: Color {
        if bridgeServer.isConnected {
            return AppColors.signalLichen
        } else if bridgeServer.isRunning {
            return AppColors.textSecondary.opacity(0.8)
        } else {
            return AppColors.textSecondary.opacity(0.5)
        }
    }

    private var bridgeTooltip: String {
        if bridgeServer.isConnected, let session = bridgeServer.connectedSession {
            return "Connected to \(session.displayName)"
        } else if bridgeServer.isRunning {
            return "Waiting for VS Code connection..."
        } else {
            return "Start VS Code Bridge"
        }
    }
    #endif
    
    // MARK: - Helper Methods
    
    private func handlePhotoSelection(_ newItem: PhotosPickerItem?) {
        guard let newItem = newItem else { return }
        Task {
            defer { selectedItem = nil }

            do {
                guard let data = try await newItem.loadTransferable(type: Data.self) else {
                    print("[MessageInputBar] Failed to load photo data")
                    return
                }
                guard let image = PlatformImageCodec.image(from: data) else {
                    print("[MessageInputBar] Failed to decode image data")
                    return
                }
                guard let compressedData = PlatformImageCodec.jpegData(from: image, compressionQuality: 0.7) else {
                    print("[MessageInputBar] Failed to compress image")
                    return
                }

                let base64 = compressedData.base64EncodedString()
                let attachment = MessageAttachment(
                    type: .image,
                    base64: base64,
                    name: "image.jpg",
                    mimeType: "image/jpeg"
                )
                withAnimation(.easeOut(duration: 0.2)) {
                    attachments.append(attachment)
                }
                print("[MessageInputBar] Successfully added image attachment (\(compressedData.count) bytes)")
            } catch {
                print("[MessageInputBar] Photo loading error: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>, type: MessageAttachment.AttachmentType) {
        debugLog(.attachments, "handleFileImport called for type: \(String(describing: type))")
        switch result {
        case .success(let urls):
            debugLog(.attachments, "File import success - got \(urls.count) URL(s)")
            guard let url = urls.first else {
                debugLog(.attachments, "File import: No URL returned")
                return
            }
            debugLog(.attachments, "Attempting to access security-scoped resource: \(url.lastPathComponent)")
            guard url.startAccessingSecurityScopedResource() else {
                debugLog(.attachments, "Failed to access security-scoped resource: \(url.lastPathComponent)")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            debugLog(.attachments, "Security-scoped resource access granted for: \(url.lastPathComponent)")

            do {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()
                let mimeType = getMimeType(for: url)
                
                // Check file size for video
                if type == .video {
                    let fileSizeMB = Double(data.count) / (1024 * 1024)
                    if fileSizeMB > 20 {
                        print("[MessageInputBar] Warning: Video file is \(String(format: "%.1f", fileSizeMB))MB. Files >20MB should use File API upload.")
                    }
                }
                
                let attachment = MessageAttachment(
                    type: type,
                    base64: base64,
                    name: url.lastPathComponent,
                    mimeType: mimeType
                )
                withAnimation(.easeOut(duration: 0.2)) {
                    attachments.append(attachment)
                }
                debugLog(.attachments, "Successfully added \(String(describing: type)): \(url.lastPathComponent) (\(data.count) bytes)")
            } catch {
                debugLog(.attachments, "Failed to read file data: \(error.localizedDescription)")
            }
        case .failure(let error):
            debugLog(.attachments, "File import FAILED: \(error.localizedDescription)")
        }
    }

    private func handleAnyFileImport(_ result: Result<[URL], Error>) {
        debugLog(.attachments, "handleAnyFileImport called")
        switch result {
        case .success(let urls):
            debugLog(.attachments, "Any file import success - got \(urls.count) URL(s)")
            guard let url = urls.first else {
                debugLog(.attachments, "Any file import: No URL returned")
                return
            }
            guard url.startAccessingSecurityScopedResource() else {
                debugLog(.attachments, "Failed to access security-scoped resource: \(url.lastPathComponent)")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            debugLog(.attachments, "Security-scoped access granted for: \(url.lastPathComponent)")

            do {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()
                let mimeType = getMimeType(for: url)
                let type = attachmentType(for: url)
                
                let attachment = MessageAttachment(
                    type: type,
                    base64: base64,
                    name: url.lastPathComponent,
                    mimeType: mimeType
                )
                withAnimation(.easeOut(duration: 0.2)) {
                    attachments.append(attachment)
                }
                debugLog(.attachments, "Successfully added file: \(url.lastPathComponent) (\(data.count) bytes, type: \(String(describing: type)))")
            } catch {
                debugLog(.attachments, "Failed to read file data: \(error.localizedDescription)")
            }
        case .failure(let error):
            debugLog(.attachments, "Any file import FAILED: \(error.localizedDescription)")
        }
    }

    private func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
        // Documents
        case "pdf":
            return "application/pdf"
        case "txt", "text":
            return "text/plain"
        case "json":
            return "application/json"
        case "xml":
            return "application/xml"
        case "doc", "docx":
            return "application/msword"
        case "xls", "xlsx":
            return "application/vnd.ms-excel"
        case "ppt", "pptx":
            return "application/vnd.ms-powerpoint"

        // Images
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"

        // Video formats
        case "mp4", "m4v":
            return "video/mp4"
        case "mpeg", "mpg":
            return "video/mpeg"
        case "mov":
            return "video/mov"
        case "avi":
            return "video/avi"
        case "flv":
            return "video/x-flv"
        case "webm":
            return "video/webm"
        case "wmv":
            return "video/wmv"
        case "3gp", "3gpp":
            return "video/3gpp"

        // Audio formats
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mp3"
        case "aiff", "aif":
            return "audio/aiff"
        case "aac", "m4a":
            return "audio/aac"
        case "ogg":
            return "audio/ogg"
        case "flac":
            return "audio/flac"

        default:
            return "application/octet-stream"
        }
    }

    private func attachmentIcon(for type: MessageAttachment.AttachmentType) -> String {
        switch type {
        case .image:
            return "photo.fill"
        case .document:
            return "doc.fill"
        case .video:
            return "video.fill"
        case .audio:
            return "waveform"
        }
    }

    private func attachmentIconColor(for type: MessageAttachment.AttachmentType) -> Color {
        switch type {
        case .image:
            return AppColors.textPrimary
        case .document:
            return AppColors.textPrimary
        case .video:
            return Color.red
        case .audio:
            return Color.purple
        }
    }

    private func attachmentType(for url: URL) -> MessageAttachment.AttachmentType {
        let ext = url.pathExtension.lowercased()

        // Video extensions
        let videoExtensions = ["mp4", "m4v", "mpeg", "mpg", "mov", "avi", "flv", "webm", "wmv", "3gp", "3gpp"]
        if videoExtensions.contains(ext) {
            return .video
        }

        // Audio extensions
        let audioExtensions = ["wav", "mp3", "aiff", "aif", "aac", "m4a", "ogg", "flac"]
        if audioExtensions.contains(ext) {
            return .audio
        }

        // Image extensions
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"]
        if imageExtensions.contains(ext) {
            return .image
        }

        // Default to document
        return .document
    }
}
