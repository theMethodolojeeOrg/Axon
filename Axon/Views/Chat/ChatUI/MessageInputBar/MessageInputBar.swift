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

// MARK: - AttachmentType Color Extension

extension MessageAttachment.AttachmentType {
    /// Color for displaying attachment type icons.
    var iconColor: Color {
        switch self {
        case .image: return AppColors.textPrimary
        case .document: return AppColors.textPrimary
        case .video: return Color.red
        case .audio: return Color.purple
        }
    }
}

// MARK: - Attachment Hub

private struct AttachmentHubSheet: View {
    @Environment(\.dismiss) private var dismiss

    let capability: AttachmentCapability
    let bridgeStatus: String?
    let onSelectPhotos: () -> Void
    let onSelectAnyFile: () -> Void
    let onSelectDocument: () -> Void
    let onSelectVideo: () -> Void
    let onSelectAudio: () -> Void
    let onToggleBridge: () -> Void

    private let attachmentTypes: [MessageAttachment.AttachmentType] = [.image, .document, .audio, .video]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickActions
                supportedTypes
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Add to Message")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(AppSurfaces.color(.controlMutedBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text(capability.description)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quickActions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 12)], spacing: 12) {
            AttachmentQuickActionTile(
                title: "Photos",
                subtitle: capability.images ? "Images" : "Unavailable",
                systemImage: "photo.on.rectangle",
                isEnabled: capability.images,
                action: onSelectPhotos
            )

            AttachmentQuickActionTile(
                title: "Files",
                subtitle: capability.supportsAnyAttachment ? "Browse" : "Unavailable",
                systemImage: "folder",
                isEnabled: capability.supportsAnyAttachment,
                action: onSelectAnyFile
            )

            if let bridgeStatus {
                AttachmentQuickActionTile(
                    title: "VS Code",
                    subtitle: bridgeStatus,
                    systemImage: "personalhotspot",
                    isEnabled: true,
                    action: onToggleBridge
                )
            }
        }
    }

    private var supportedTypes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accepted MIME Types")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

            VStack(spacing: 8) {
                ForEach(attachmentTypes, id: \.self) { type in
                    AttachmentMimeTypeRow(
                        type: type,
                        patterns: capability.mimePatterns(for: type),
                        action: action(for: type)
                    )
                }
            }
        }
    }

    private func action(for type: MessageAttachment.AttachmentType) -> () -> Void {
        switch type {
        case .image:
            return onSelectPhotos
        case .document:
            return onSelectDocument
        case .audio:
            return onSelectAudio
        case .video:
            return onSelectVideo
        }
    }
}

private struct AttachmentQuickActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(isEnabled ? AppColors.textPrimary : AppColors.textDisabled)

                VStack(spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium().weight(.semibold))
                        .foregroundColor(isEnabled ? AppColors.textPrimary : AppColors.textDisabled)

                    Text(subtitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppSurfaces.color(.cardBorder).opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct AttachmentMimeTypeRow: View {
    let type: MessageAttachment.AttachmentType
    let patterns: [String]
    let action: () -> Void

    private var isSupported: Bool {
        !patterns.isEmpty
    }

    private var title: String {
        switch type {
        case .image: return "Photos"
        case .document: return "Documents"
        case .audio: return "Audio"
        case .video: return "Video"
        }
    }

    private var subtitle: String {
        isSupported ? patterns.joined(separator: ", ") : "Not supported by the current model"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: type.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSupported ? AppColors.signalMercury : AppColors.textDisabled)
                    .frame(width: 30, height: 30)
                    .background(AppSurfaces.color(.controlMutedBackground), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.bodyMedium().weight(.semibold))
                        .foregroundColor(isSupported ? AppColors.textPrimary : AppColors.textDisabled)

                    Text(subtitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(12)
            .background(AppSurfaces.color(.controlMutedBackground).opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isSupported)
        .opacity(isSupported ? 1 : 0.55)
    }
}

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
    private let conversationId: String?
    let onSend: () -> Void
    let onStop: (() -> Void)?
    let focus: FocusState<Bool>.Binding?

    // ViewModel handles attachment capability and slash command state
    @StateObject private var viewModel: MessageInputViewModel

    @State private var inputHeight: CGFloat = 20

    @State private var selectedItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showVideoImporter = false
    @State private var showAudioImporter = false
    @State private var showAnyFileImporter = false
    @State private var showAttachmentHub = false
    @State private var attachmentValidationMessage: String?

    // Flag to prevent onChange from overriding manual state updates
    @State private var skipNextTextChange = false

    // VS Code Bridge
    @ObservedObject private var bridgeServer = BridgeServer.shared

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
        self.conversationId = conversationId
        self.onSend = onSend
        self.onStop = onStop
        self.focus = focus
        self._viewModel = StateObject(wrappedValue: MessageInputViewModel(conversationId: conversationId))
    }

    // MARK: - Computed Properties (delegated to ViewModel)

    private var attachmentCapability: AttachmentCapability {
        viewModel.resolveAttachmentCapability()
    }

    private var canSend: Bool {
        viewModel.canSend(text: text, attachments: attachments)
    }

    private var isSlashCommand: Bool {
        viewModel.isSlashCommand(text)
    }

    private var isComposerFocused: Bool {
        focus?.wrappedValue ?? false
    }

    private var composerBorderColor: Color {
        isComposerFocused ? AppColors.signalMercury.opacity(0.45) : AppSurfaces.color(.cardBorder).opacity(0.85)
    }

    private var composerFocusGlow: Color {
        isComposerFocused ? AppColors.signalMercury.opacity(0.14) : .clear
    }

    private var sendButtonFill: Color {
        if isLoading {
            return AppColors.signalHematite.opacity(0.9)
        }
        return canSend ? AppColors.signalLichen : AppSurfaces.color(.controlBackground).opacity(0.8)
    }

    private var sendButtonForeground: Color {
        canSend || isLoading ? .white : AppColors.textSecondary.opacity(0.55)
    }

    private var bridgeStatusSummary: String? {
        #if os(macOS)
        if bridgeServer.isConnected, let session = bridgeServer.connectedSession {
            return "Connected to \(session.displayName)"
        }
        if bridgeServer.isRunning {
            return "Waiting for VS Code"
        }
        return "Start VS Code Bridge"
        #else
        return nil
        #endif
    }

    // MARK: - Actions

    private func handleSend() {
        guard canSend && !isLoading else { return }
        onSend()
    }

    private func handleStop() {
        guard isLoading else { return }
        onStop?()
    }

    private func presentAttachmentPicker(_ present: @escaping () -> Void) {
        showAttachmentHub = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            present()
        }
    }

    #if os(macOS)
    private func toggleBridgeServer() async {
        if bridgeServer.isRunning {
            await bridgeServer.stop()
        } else {
            await bridgeServer.start()
        }
    }
    #endif

    // MARK: - Slash Command Menu (delegated to ViewModel)

    private func handleCommandSelection(_ suggestion: SlashCommandSuggestion) {
        let result = viewModel.handleCommandSelection(suggestion)
        skipNextTextChange = result.skipNextChange
        text = result.newText

        if result.shouldSend {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.handleSend()
            }
        }
    }

    private func handleToolSelection(_ tool: ToolSuggestion) {
        text = viewModel.handleToolSelection(tool)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.handleSend()
        }
    }

    private func handleUseToolSelection(_ tool: ToolSuggestion) {
        text = ""
        viewModel.handleUseToolSelection(tool)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            // Slash Command Menu (appears above input)
            slashCommandMenuOverlay

            // Main content
            mainInputContent
        }
        .onChange(of: text) { _, newText in
            if skipNextTextChange {
                skipNextTextChange = false
                return
            }
            viewModel.updateSlashMenuState(for: newText)
        }
        .onAppear {
            viewModel.updateConversationId(conversationId)
        }
        .onChange(of: conversationId) { _, newConversationId in
            viewModel.updateConversationId(newConversationId)
        }
        .onChange(of: selectedItem) { _, newItem in
            handlePhotoSelection(newItem)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: allowedContentTypes(for: .document, capability: attachmentCapability),
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (document) callback triggered")
            handleFileImport(result, type: .document)
        }
        .fileImporter(
            isPresented: $showVideoImporter,
            allowedContentTypes: allowedContentTypes(for: .video, capability: attachmentCapability),
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (video) callback triggered")
            handleFileImport(result, type: .video)
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: allowedContentTypes(for: .audio, capability: attachmentCapability),
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (audio) callback triggered")
            handleFileImport(result, type: .audio)
        }
        .fileImporter(
            isPresented: $showAnyFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            debugLog(.attachments, "fileImporter (any file) callback triggered")
            handleAnyFileImport(result)
        }
        .sheet(isPresented: $viewModel.showToolInvocationSheet) {
            Group {
            if let tool = viewModel.selectedToolForInvocation {
                ToolInvocationSheet(
                    tool: tool,
                    onDismiss: {
                        viewModel.showToolInvocationSheet = false
                        viewModel.selectedToolForInvocation = nil
                    },
                    onResult: { result, success in
                        if success {
                            text = "Tool result from \(tool.displayName):\n\n\(result)"
                        }
                    }
                )
            }

            }
            .appSheetMaterial()
}
        .sheet(isPresented: $showAttachmentHub) {
            AttachmentHubSheet(
                capability: attachmentCapability,
                bridgeStatus: bridgeStatusSummary,
                onSelectPhotos: { presentAttachmentPicker { showPhotoPicker = true } },
                onSelectAnyFile: { presentAttachmentPicker { showAnyFileImporter = true } },
                onSelectDocument: { presentAttachmentPicker { showFileImporter = true } },
                onSelectVideo: { presentAttachmentPicker { showVideoImporter = true } },
                onSelectAudio: { presentAttachmentPicker { showAudioImporter = true } },
                onToggleBridge: {
                    #if os(macOS)
                    presentAttachmentPicker {
                        Task { await toggleBridgeServer() }
                    }
                    #endif
                }
            )
            .appSheetMaterial()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
        .alert("Attachment Error", isPresented: Binding(
            get: { attachmentValidationMessage != nil },
            set: { shown in
                if !shown {
                    attachmentValidationMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { attachmentValidationMessage = nil }
        } message: {
            Text(attachmentValidationMessage ?? "")
        }
    }

    // MARK: - Body Subviews

    @ViewBuilder
    private var slashCommandMenuOverlay: some View {
        if viewModel.slashMenuState != .hidden {
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    SlashCommandMenu(
                        availableHeight: geometry.size.height,
                        menuState: viewModel.slashMenuState,
                        commandSuggestions: viewModel.commandSuggestions,
                        toolSuggestions: viewModel.toolSuggestions,
                        onSelectCommand: handleCommandSelection,
                        onSelectTool: handleToolSelection,
                        onSelectUseTool: handleUseToolSelection,
                        onDismiss: { viewModel.dismissSlashMenu() }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, ChatVisualTokens.composerSlashMenuBottomOffset)
                    .frame(maxWidth: ChatVisualTokens.chatRailMaxWidth)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, ChatVisualTokens.chatRailHorizontalPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .zIndex(1)
        }
    }

    @ViewBuilder
    private var mainInputContent: some View {
        VStack(spacing: 0) {
            if !attachments.isEmpty {
                attachmentsPreview
            }

            composerShell
            .padding(.horizontal, ChatVisualTokens.composerHorizontalPadding)
            .padding(.bottom, ChatVisualTokens.composerBottomPadding)
        }
        .frame(maxWidth: ChatVisualTokens.chatRailMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, ChatVisualTokens.chatRailHorizontalPadding)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var composerShell: some View {
        let capability = attachmentCapability

        HStack(alignment: .center, spacing: 8) {
            #if os(macOS)
            leadingControlGroup(capability: capability)

            if capability.supportsAnyAttachment {
                composerSeparator
            }
            #else
            if capability.supportsAnyAttachment {
                attachmentMenu(capability: capability)
            }
            #endif

            textInputArea

            sendButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, ChatVisualTokens.composerOuterVerticalPadding)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ChatVisualTokens.composerCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ChatVisualTokens.composerCornerRadius, style: .continuous)
                .stroke(AppSurfaces.color(.cardBorder).opacity(0.55), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ChatVisualTokens.composerCornerRadius, style: .continuous)
                .stroke(composerBorderColor, lineWidth: isComposerFocused ? 1.5 : 0.75)
        )
        .shadow(color: composerFocusGlow, radius: 10, x: 0, y: 0)
        .shadow(color: AppColors.shadow.opacity(0.18), radius: 10, x: 0, y: -2)
        .animation(.easeInOut(duration: 0.16), value: isComposerFocused)
    }

    #if os(macOS)
    @ViewBuilder
    private func leadingControlGroup(capability: AttachmentCapability) -> some View {
        HStack(spacing: 1) {
            bridgeButton

            if capability.supportsAnyAttachment {
                attachmentMenu(capability: capability)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(AppSurfaces.color(.controlMutedBackground).opacity(0.65))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppSurfaces.color(.cardBorder).opacity(0.45), lineWidth: 1)
        )
    }

    private var composerSeparator: some View {
        Rectangle()
            .fill(AppSurfaces.color(.separator).opacity(0.65))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 1)
    }
    #endif

    @ViewBuilder
    private var attachmentsPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach($attachments) { $attachment in
                    attachmentPreviewItem(attachment: $attachment)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(height: ChatVisualTokens.composerAttachmentPreviewHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ChatVisualTokens.composerInnerCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ChatVisualTokens.composerInnerCornerRadius, style: .continuous)
                .stroke(AppSurfaces.color(.cardBorder).opacity(0.55), lineWidth: 1)
        )
        .padding(.horizontal, ChatVisualTokens.composerHorizontalPadding)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func attachmentPreviewItem(attachment: Binding<MessageAttachment>) -> some View {
        let tileSize = ChatVisualTokens.composerAttachmentTileSize

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
                    .frame(width: tileSize, height: tileSize)
                    .cornerRadius(10)
                    .clipped()
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: tileSize, height: tileSize)
                    .cornerRadius(10)
                    .clipped()
                #else
                EmptyView()
                #endif
            } else {
                VStack(spacing: 4) {
                    Image(systemName: attachment.wrappedValue.type.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(attachment.wrappedValue.type.iconColor)
                    Text(attachment.wrappedValue.name ?? (attachment.wrappedValue.type == .image ? "Image" : "File"))
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(width: tileSize, height: tileSize)
                .background(AppSurfaces.color(.controlBackground))
                .cornerRadius(10)
            }

            // Remove button
            Button(action: {
                if let index = attachments.firstIndex(where: { $0.id == attachment.wrappedValue.id }) {
                    _ = withAnimation(.easeOut(duration: 0.2)) {
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
        Button {
            debugLog(.attachments, "Attachment hub button tapped")
            showAttachmentHub = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: ChatVisualTokens.composerControlGlyphSize + 2, weight: .medium))
            .foregroundColor(AppColors.textSecondary)
            .frame(width: ChatVisualTokens.composerControlSize, height: ChatVisualTokens.composerControlSize)
            .background(
                Circle()
                    .fill(AppSurfaces.color(.controlMutedBackground).opacity(0.45))
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add attachment")
    }

    @ViewBuilder
    private var focusedTextEditor: some View {
        let editor = ChatTextEditor(
                text: $text,
                placeholder: "Message or /tool...",
                isDisabled: isLoading,
                maxHeight: ChatVisualTokens.composerInputMaxHeight,
                dynamicHeight: $inputHeight,
                onSubmit: handleSend
            )
            .frame(height: inputHeight)

        if let focus {
            editor.focused(focus)
        } else {
            editor
        }
    }

    @ViewBuilder
    private var textInputArea: some View {
        ZStack(alignment: .leading) {
            // Placeholder with slash command hint
            if text.isEmpty {
                Text("Message or /tool...")
                    .font(.body)
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }

            // Custom text editor with Enter handling
            focusedTextEditor
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minHeight: ChatVisualTokens.composerControlSize - 4)
        .background(AppSurfaces.color(.controlMutedBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: ChatVisualTokens.composerInnerCornerRadius, style: .continuous))
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: ChatVisualTokens.composerInnerCornerRadius, style: .continuous))
        .overlay(
            // Visual indicator when typing a slash command
            RoundedRectangle(cornerRadius: ChatVisualTokens.composerInnerCornerRadius, style: .continuous)
                .stroke(isSlashCommand ? AppColors.signalMercury.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: ChatVisualTokens.composerInnerCornerRadius, style: .continuous))
        .onTapGesture {
            focus?.wrappedValue = true
        }
        .animation(.easeInOut(duration: 0.15), value: isSlashCommand)
    }

    @ViewBuilder
    private var sendButton: some View {
        Button(action: isLoading ? handleStop : handleSend) {
            Group {
                if isLoading {
                    Image(systemName: "stop.fill")
                        .font(.system(size: ChatVisualTokens.composerSendGlyphSize, weight: .semibold))
                        .foregroundColor(sendButtonForeground)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: ChatVisualTokens.composerSendGlyphSize, weight: .semibold))
                        .foregroundColor(sendButtonForeground)
                }
            }
            .frame(width: ChatVisualTokens.composerSendIconFrame, height: ChatVisualTokens.composerSendIconFrame)
            .background(
                Circle()
                    .fill(sendButtonFill)
                    .overlay(
                        Circle()
                            .stroke(AppSurfaces.color(.cardBorder).opacity(canSend || isLoading ? 0.35 : 0.7), lineWidth: 1)
                    )
                    .shadow(color: canSend && !isLoading ? AppColors.signalLichen.opacity(0.28) : .clear, radius: 5, x: 0, y: 2)
            )
            .frame(width: ChatVisualTokens.composerControlSize, height: ChatVisualTokens.composerControlSize)
        }
        .buttonStyle(.plain)
        .disabled(!isLoading && !canSend)
        .animation(.easeInOut(duration: 0.15), value: canSend)
        .animation(.easeInOut(duration: 0.15), value: isLoading)
        .scaleEffect(canSend || isLoading ? 1.0 : 0.95)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: canSend)
        .accessibilityLabel(isLoading ? "Stop Generating" : "Send Message")
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
                .font(.system(size: ChatVisualTokens.composerControlGlyphSize, weight: .medium))
                .foregroundColor(bridgeIconColor)
                .frame(width: ChatVisualTokens.composerControlSize, height: ChatVisualTokens.composerControlSize)
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
                appendAttachmentIfAllowed(attachment)
                print("[MessageInputBar] Processed image attachment (\(compressedData.count) bytes)")
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
            let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
            let stopSecurityScopedAccess: (() -> Void)? = hasSecurityScopedAccess
                ? { url.stopAccessingSecurityScopedResource() }
                : nil
            defer { stopSecurityScopedAccess?() }
            if !hasSecurityScopedAccess {
                debugLog(.attachments, "Failed to access security-scoped resource: \(url.lastPathComponent)")
            } else {
                debugLog(.attachments, "Security-scoped resource access granted for: \(url.lastPathComponent)")
            }

            do {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()

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
                    mimeType: url.mimeType
                )
                appendAttachmentIfAllowed(attachment)
                debugLog(.attachments, "Processed \(String(describing: type)): \(url.lastPathComponent) (\(data.count) bytes)")
            } catch {
                debugLog(.attachments, "Failed to read file data: \(error.localizedDescription)")
                presentAttachmentImportError(fileName: url.lastPathComponent, error: error)
            }
        case .failure(let error):
            debugLog(.attachments, "File import FAILED: \(error.localizedDescription)")
            if !isUserCancelled(error) {
                presentAttachmentImportError(fileName: nil, error: error)
            }
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
            let hasSecurityScopedAccess = url.startAccessingSecurityScopedResource()
            let stopSecurityScopedAccess: (() -> Void)? = hasSecurityScopedAccess
                ? { url.stopAccessingSecurityScopedResource() }
                : nil
            defer { stopSecurityScopedAccess?() }
            if !hasSecurityScopedAccess {
                debugLog(.attachments, "Failed to access security-scoped resource: \(url.lastPathComponent)")
            } else {
                debugLog(.attachments, "Security-scoped access granted for: \(url.lastPathComponent)")
            }

            do {
                let data = try Data(contentsOf: url)
                let base64 = data.base64EncodedString()

                let attachment = MessageAttachment(
                    type: url.attachmentType,
                    base64: base64,
                    name: url.lastPathComponent,
                    mimeType: url.mimeType
                )
                appendAttachmentIfAllowed(attachment)
                debugLog(.attachments, "Processed file: \(url.lastPathComponent) (\(data.count) bytes, type: \(url.attachmentType))")
            } catch {
                debugLog(.attachments, "Failed to read file data: \(error.localizedDescription)")
                presentAttachmentImportError(fileName: url.lastPathComponent, error: error)
            }
        case .failure(let error):
            debugLog(.attachments, "Any file import FAILED: \(error.localizedDescription)")
            if !isUserCancelled(error) {
                presentAttachmentImportError(fileName: nil, error: error)
            }
        }
    }

    private func appendAttachmentIfAllowed(_ attachment: MessageAttachment) {
        let policy = viewModel.resolveAttachmentPolicy()
        let validation = AttachmentMimePolicyService.validate(attachments: [attachment], policy: policy)

        switch validation {
        case .accepted:
            withAnimation(.easeOut(duration: 0.2)) {
                attachments.append(attachment)
            }

        case .rejected(let failures):
            attachmentValidationMessage = AttachmentMimePolicyService.validationErrorMessage(
                failures: failures,
                policy: policy
            )
            debugLog(.attachments, "Rejected attachment \(attachment.name ?? attachment.id): \(attachmentValidationMessage ?? "unsupported MIME")")
        }
    }

    private func allowedContentTypes(
        for attachmentType: MessageAttachment.AttachmentType,
        capability: AttachmentCapability
    ) -> [UTType] {
        let patterns = capability.mimePatterns(for: attachmentType)
        var types: [UTType] = []

        func appendUnique(_ type: UTType) {
            if !types.contains(type) {
                types.append(type)
            }
        }

        for pattern in patterns {
            let lower = pattern.lowercased()
            if lower == "image/*" {
                appendUnique(.image)
                continue
            }
            if lower == "audio/*" {
                appendUnique(.audio)
                continue
            }
            if lower == "video/*" {
                appendUnique(.movie)
                appendUnique(.video)
                continue
            }
            if lower == "text/*" {
                appendUnique(.text)
                appendUnique(.plainText)
                appendUnique(.rtf)
                continue
            }
            if lower == "application/pdf" {
                appendUnique(.pdf)
                continue
            }
            if let resolved = UTType(mimeType: lower) {
                appendUnique(resolved)
            }
        }

        return types.isEmpty ? [.item] : types
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func presentAttachmentImportError(fileName: String?, error: Error) {
        if let fileName {
            attachmentValidationMessage = "Couldn't import '\(fileName)'. Check file permissions/location and try again.\n\n\(error.localizedDescription)"
        } else {
            attachmentValidationMessage = "Couldn't import the selected file.\n\n\(error.localizedDescription)"
        }
    }
}
