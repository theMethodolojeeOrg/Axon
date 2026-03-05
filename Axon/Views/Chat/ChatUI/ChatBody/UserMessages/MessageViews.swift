//
//  MessageViews.swift
//  Axon
//
//  Modern chat message views - user bubbles and free-flowing assistant content
//

import SwiftUI
import MarkdownUI
import Combine

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Model Provider & Icon Styling Helpers

fileprivate enum ModelProvider {
    case anthropic
    case openAI
    case google
    case xai
    case perplexity
    case deepseek
    case zai
    case minimax
    case mistral
    case custom
}

fileprivate func provider(for modelName: String?, providerName: String? = nil) -> ModelProvider {
    if let provider = providerName?.lowercased() {
        if provider == "anthropic" { return .anthropic }
        if provider == "openai" || provider == "openai-compatible" { return .openAI }
        if provider == "gemini" || provider == "google" { return .google }
        if provider == "xai" || provider == "grok" { return .xai }
        if provider == "perplexity" { return .perplexity }
        if provider == "deepseek" { return .deepseek }
        if provider == "zai" || provider == "z.ai" || provider == "zhipu" { return .zai }
        if provider == "minimax" { return .minimax }
        if provider == "mistral" { return .mistral }
    }

    guard let name = modelName?.lowercased() else { return .custom }
    if name.contains("claude") || name.contains("anthropic") { return .anthropic }
    if name.contains("gpt") || name.contains("openai") { return .openAI }
    if name.contains("gemini") || name.contains("google") { return .google }
    if name.contains("grok") || name.contains("xai") { return .xai }
    if name.contains("sonar") || name.contains("perplexity") { return .perplexity }
    if name.contains("deepseek") { return .deepseek }
    if name.contains("glm") || name.contains("zhipu") { return .zai }
    if name.contains("minimax") || name.contains("m2") { return .minimax }
    if name.contains("mistral") || name.contains("pixtral") || name.contains("codestral") { return .mistral }
    return .custom
}

fileprivate func colorFromHex(_ hex: String) -> Color {
    var hexString = hex
    if hexString.hasPrefix("#") { hexString.removeFirst() }
    let scanner = Scanner(string: hexString)
    var hexNumber: UInt64 = 0
    if scanner.scanHexInt64(&hexNumber) {
        let r = Double((hexNumber & 0xFF0000) >> 16) / 255.0
        let g = Double((hexNumber & 0x00FF00) >> 8) / 255.0
        let b = Double(hexNumber & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    return Color.gray
}

fileprivate func iconStyle(for provider: ModelProvider, modelName: String?) -> AnyShapeStyle {
    switch provider {
    case .anthropic:
        return AnyShapeStyle(colorFromHex("#d97757"))
    case .openAI:
        return AnyShapeStyle(colorFromHex("#00A67E"))
    case .google:
        let colors: [Color] = [
            colorFromHex("#fabc12"),
            colorFromHex("#f94543"),
            colorFromHex("#3186ff"),
            colorFromHex("#08b962")
        ]
        return AnyShapeStyle(AngularGradient(gradient: Gradient(colors: colors), center: .center))
    case .xai:
        return AnyShapeStyle(Color.white)
    case .perplexity:
        return AnyShapeStyle(colorFromHex("#20B2AA"))  // Teal/cyan color
    case .deepseek:
        return AnyShapeStyle(colorFromHex("#4169E1"))  // Royal blue
    case .zai:
        return AnyShapeStyle(colorFromHex("#6366F1"))  // Indigo (Zhipu brand)
    case .minimax:
        return AnyShapeStyle(colorFromHex("#FF6B35"))  // Orange (MiniMax brand)
    case .mistral:
        return AnyShapeStyle(colorFromHex("#FF7000"))  // Orange (Mistral brand)
    case .custom:
        let key = (modelName ?? "custom-unknown").lowercased()
        let hex = ModelColorRegistry.shared.hex(forKey: key)
        return AnyShapeStyle(colorFromHex(hex))
    }
}

fileprivate func providerColor(for provider: ModelProvider, modelName: String?) -> Color {
    switch provider {
    case .anthropic:
        return colorFromHex("#d97757")
    case .openAI:
        return colorFromHex("#00A67E")
    case .google:
        return colorFromHex("#4285F4")
    case .xai:
        return .white
    case .perplexity:
        return colorFromHex("#20B2AA")  // Teal/cyan color
    case .deepseek:
        return colorFromHex("#4169E1")  // Royal blue
    case .zai:
        return colorFromHex("#6366F1")  // Indigo (Zhipu brand)
    case .minimax:
        return colorFromHex("#FF6B35")  // Orange (MiniMax brand)
    case .mistral:
        return colorFromHex("#FF7000")  // Orange (Mistral brand)
    case .custom:
        let key = (modelName ?? "custom-unknown").lowercased()
        let hex = ModelColorRegistry.shared.hex(forKey: key)
        return colorFromHex(hex)
    }
}

// MARK: - User Message View

struct UserMessageView: View {
    let message: Message
    let onCopy: (Message) -> Void
    var onEdit: ((Message) -> Void)? = nil
    var onDelete: ((Message) -> Void)? = nil
    var showAvatar: Bool = true
    var showMetadata: Bool = true

    /// Maximum lines shown before truncating with "Show more".
    private let collapsedLineLimit = 12

    @State private var isExpanded = false
    @State private var isTruncated = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 4) {
                // Attachments
                if let attachments = message.attachments, !attachments.isEmpty {
                    ForEach(attachments) { attachment in
                        attachmentView(for: attachment)
                    }
                }

                // Message bubble
                VStack(alignment: .trailing, spacing: 6) {
                    // Message content (text selection enabled for partial copy)
                    Text(message.content)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(isExpanded ? nil : collapsedLineLimit)
                        .background(
                            // Invisible geometry reader to detect truncation
                            GeometryReader { visibleGeometry in
                                Text(message.content)
                                    .font(AppTypography.bodyMedium())
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background(
                                        GeometryReader { fullGeometry in
                                            Color.clear.preference(
                                                key: TruncationPreferenceKey.self,
                                                value: fullGeometry.size.height > visibleGeometry.size.height + 1
                                            )
                                        }
                                    )
                                    .hidden()
                            }
                        )
                        .onPreferenceChange(TruncationPreferenceKey.self) { truncated in
                            if !isExpanded {
                                isTruncated = truncated
                            }
                        }

                    // Show more / Show less button
                    if isTruncated || isExpanded {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            Text(isExpanded ? "Show less" : "Show more")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.signalLichen)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, ChatVisualTokens.messageBubbleHorizontalPadding)
                .padding(.vertical, ChatVisualTokens.messageBubbleVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(AppColors.signalMercury.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(AppColors.signalMercury.opacity(0.35), lineWidth: 1)
                        )
                )
                .contextMenu {
                    Button(action: { onCopy(message) }) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    if onEdit != nil {
                        Button(action: { onEdit?(message) }) {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    if onDelete != nil {
                        Button(role: .destructive, action: { onDelete?(message) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if onDelete != nil {
                        Button(role: .destructive) { onDelete?(message) }
                            label: { Label("Delete", systemImage: "trash") }
                    }
                    if onEdit != nil {
                        Button { onEdit?(message) }
                            label: { Label("Edit", systemImage: "pencil") }
                            .tint(.orange)
                    }
                }
                #endif

                // Timestamp and edited indicator (cluster tail only)
                if showMetadata {
                    HStack(spacing: 6) {
                        Text(message.timestamp, style: .time)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                        if message.isEdited {
                            Text("(edited)")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }
            }

            if showAvatar {
                Circle()
                    .fill(AppColors.signalMercury)
                    .frame(width: ChatVisualTokens.messageAvatarSize, height: ChatVisualTokens.messageAvatarSize)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    )
            } else {
                Color.clear
                    .frame(width: ChatVisualTokens.messageAvatarSize, height: ChatVisualTokens.messageAvatarSize)
            }
        }
        .padding(.horizontal, ChatVisualTokens.messageOuterHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    @ViewBuilder
    private func attachmentView(for attachment: MessageAttachment) -> some View {
        #if canImport(UIKit)
        if attachment.type == .image, let base64 = attachment.base64,
           let data = Data(base64Encoded: base64),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 200)
                .cornerRadius(12)
        } else if attachment.type == .document {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundColor(AppColors.textPrimary)
                Text(attachment.name ?? "Document")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(8)
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
        }
        #else
        if attachment.type == .image {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundColor(AppColors.textPrimary)
                Text(attachment.name ?? "Image")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(8)
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
        } else if attachment.type == .document {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundColor(AppColors.textPrimary)
                Text(attachment.name ?? "Document")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(8)
            .background(AppColors.substrateTertiary)
            .cornerRadius(8)
        }
        #endif
    }
}

// MARK: - Assistant Message View

struct AssistantMessageView: View {
    let message: Message
    let overrideContent: String?
    let onCopy: (Message) -> Void
    let onRegenerate: (Message) -> Void
    var onQuote: ((String) -> Void)? = nil

    /// Live tool calls during streaming (nil when not streaming)
    var liveToolCalls: [LiveToolCall]? = nil

    /// Streaming reasoning content (nil when not streaming)
    var streamingReasoning: String? = nil

    /// Context debug info (only populated when debug mode is enabled)
    var contextDebugInfo: ContextDebugInfo? = nil
    var showMetadata: Bool = true

    @ObservedObject private var ttsService = TTSPlaybackService.shared

    private var textToRender: String {
        overrideContent ?? message.content
    }

    private var modelProvider: ModelProvider {
        provider(for: message.modelName, providerName: message.providerName)
    }

    /// Check if we're in streaming mode
    private var isStreaming: Bool {
        message.isStreaming == true || overrideContent != nil
    }

    /// Reasoning to display (streaming or final)
    private var displayReasoning: String? {
        if let streaming = streamingReasoning, !streaming.isEmpty {
            return streaming
        }
        return message.reasoning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reasoning tokens (from reasoning models like DeepSeek R1, Perplexity Sonar Reasoning, etc.)
            if let reasoning = displayReasoning, !reasoning.isEmpty {
                ReasoningView(
                    reasoning: reasoning,
                    providerColor: providerColor(for: modelProvider, modelName: message.modelName),
                    isStreaming: isStreaming && streamingReasoning != nil
                )
                .padding(.bottom, 12)
            }

            // Attachments (if any from assistant - rare but possible)
            if let attachments = message.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(attachments) { attachment in
                        attachmentView(for: attachment)
                    }
                }
                .padding(.bottom, 12)
            }

            // Main content (or hidden banner)
            if let hiddenReason = message.hiddenReason, !hiddenReason.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "eye.slash")
                            .foregroundColor(AppColors.textTertiary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Message hidden")
                                .font(AppTypography.titleSmall())
                                .foregroundColor(AppColors.textPrimary)

                            Text(hiddenReason)
                                .font(AppTypography.bodySmall())
                                .foregroundColor(AppColors.textSecondary)

                            Text("Use Select Text to view/copy the full message.")
                                .font(AppTypography.labelSmall())
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppColors.substrateSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(AppColors.glassBorder, lineWidth: 1)
                            )
                    )
                }
            } else if let toolCalls = liveToolCalls, !toolCalls.isEmpty {
                // Streaming mode with tool calls - interleave content and tools
                StreamingContentWithToolsView(
                    content: textToRender,
                    toolCalls: toolCalls
                )
            } else {
                // Standard markdown rendering
                // When streaming: isFromHistory=false allows tools to auto-execute (if enabled)
                // When not streaming: isFromHistory=true prevents re-execution on app restart
                AssistantMarkdownView(
                    content: textToRender,
                    executedToolCalls: message.liveToolCalls,
                    isFromHistory: !isStreaming,
                    conversationId: message.conversationId,
                    messageId: message.id
                )
                .codeArtifactHost()
            }

            // Grounding sources (from tool calls like web search, maps)
            // Only show when not streaming (they'll be in inline tool calls during streaming)
            if !isStreaming, let sources = message.groundingSources, !sources.isEmpty {
                MessageSourcesView(sources: sources)
                    .padding(.top, 12)
            }

            // Memory operations (from create_memory tool calls)
            // Only show when not streaming
            if !isStreaming, let memOps = message.memoryOperations, !memOps.isEmpty {
                MemoryOperationsView(operations: memOps)
                    .padding(.top, 12)
            }

            // Context debug info (developer feature)
            // Only show when not streaming and debug info is available
            if !isStreaming, let debugInfo = contextDebugInfo {
                ContextDebugView(debugInfo: debugInfo)
                    .padding(.top, 12)
            }

            // Footer toolbar (cluster tail only)
            if !isStreaming && showMetadata {
                AssistantToolbar(
                    message: message,
                    onCopy: onCopy,
                    onRegenerate: onRegenerate,
                    onQuote: onQuote
                )
                .padding(.top, 12)
            } else {
                // Streaming indicator
                StreamingIndicator(modelName: message.modelName)
                    .padding(.top, 12)
            }
        }
        .frame(maxWidth: ChatVisualTokens.messageMaxReadableWidth, alignment: .leading)
        .padding(.horizontal, ChatVisualTokens.messageOuterHorizontalPadding)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private func attachmentView(for attachment: MessageAttachment) -> some View {
        #if canImport(UIKit)
        if attachment.type == .image, let base64 = attachment.base64,
           let data = Data(base64Encoded: base64),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, maxHeight: 300)
                .cornerRadius(12)
        } else if attachment.type == .document {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundColor(AppColors.textPrimary)
                Text(attachment.name ?? "Document")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
        #else
        if attachment.type == .image {
            HStack(spacing: 8) {
                Image(systemName: "photo")
                    .foregroundColor(AppColors.textPrimary)
                Text(attachment.name ?? "Image")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        } else if attachment.type == .document {
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .foregroundColor(AppColors.textPrimary)
                Text(attachment.name ?? "Document")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(8)
        }
        #endif
    }
}

// MARK: - Assistant Toolbar

struct AssistantToolbar: View {
    let message: Message
    let onCopy: (Message) -> Void
    let onRegenerate: (Message) -> Void
    var onQuote: ((String) -> Void)? = nil

    @ObservedObject private var ttsService = TTSPlaybackService.shared
    @State private var showQuoteToast = false
    @State private var showTextSelector = false

    private var modelProvider: ModelProvider {
        provider(for: message.modelName, providerName: message.providerName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image("AxonChatIconTemplate")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(iconStyle(for: modelProvider, modelName: message.modelName))

                if let modelName = message.modelName {
                    Text(modelName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toolbarAction(
                        icon: "selection.pin.in.out",
                        label: "Select Text",
                        color: AppColors.textTertiary
                    ) {
                        showTextSelector = true
                    }

                    if onQuote != nil {
                        toolbarAction(
                            icon: "text.quote",
                            label: "Quote from Clipboard",
                            color: AppColors.textTertiary
                        ) {
                            quoteFromClipboard()
                        }
                    }

                    toolbarAction(
                        icon: "doc.on.doc",
                        label: "Copy Message",
                        color: AppColors.textTertiary
                    ) {
                        onCopy(message)
                    }

                    toolbarAction(
                        icon: "arrow.clockwise",
                        label: "Regenerate",
                        color: AppColors.textTertiary
                    ) {
                        onRegenerate(message)
                    }

                    let settings = SettingsViewModel.shared.settings
                    if ttsService.hasGeneratedAudio(for: message.id, settings: settings) {
                        toolbarAction(
                            icon: "play.circle.fill",
                            label: "Play Audio",
                            color: AppColors.signalMercury
                        ) {
                            Task {
                                do {
                                    try await ttsService.playGenerated(messageId: message.id, settings: settings)
                                } catch {
                                    print("[TTS] Failed to play generated audio: \(error)")
                                }
                            }
                        }
                    } else {
                        toolbarAction(
                            icon: "speaker.wave.2",
                            label: "Text to Speech",
                            color: AppColors.textTertiary
                        ) {
                            Task {
                                do {
                                    try await ttsService.speak(text: message.content, settings: settings, messageId: message.id)
                                } catch {
                                    print("[TTS] Failed to speak: \(error)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if showQuoteToast {
                Text("Copy text first, then tap quote")
                    .font(AppTypography.labelSmall())
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.substrateSecondary)
                    .cornerRadius(8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .offset(y: -30)
            }
        }
        .sheet(isPresented: $showTextSelector) {
            TextSelectorSheet(
                content: message.content,
                onQuote: onQuote
            )
        }
    }

    @ViewBuilder
    private func toolbarAction(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(
                    Capsule()
                        .fill(AppColors.substrateSecondary.opacity(0.85))
                )
                .overlay(
                    Capsule()
                        .stroke(AppColors.glassBorder.opacity(0.7), lineWidth: 1)
                )
                .frame(width: ChatVisualTokens.minTouchTarget, height: ChatVisualTokens.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func quoteFromClipboard() {
        guard let clipboardText = AppClipboard.pasteString(), !clipboardText.isEmpty else {
            // Show toast if clipboard is empty
            withAnimation {
                showQuoteToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showQuoteToast = false
                }
            }
            return
        }

        // Format as a quote block
        let formattedQuote = formatAsQuote(clipboardText)
        onQuote?(formattedQuote)
    }

    private func formatAsQuote(_ text: String) -> String {
        // Format as markdown quote with line prefix
        let lines = text.components(separatedBy: .newlines)
        let quotedLines = lines.map { "> \($0)" }
        return quotedLines.joined(separator: "\n") + "\n\n"
    }
}

// MARK: - Text Selector Sheet

struct TextSelectorSheet: View {
    let content: String
    var onQuote: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Select Text")
                    .font(.headline)

                Spacer()

                if onQuote != nil {
                    Button(action: quoteFromClipboard) {
                        Label("Quote", systemImage: "text.quote")
                    }
                } else {
                    // Invisible spacer to balance the header
                    Button("Done") { }
                        .opacity(0)
                }
            }
            .padding()
            .background(AppColors.substrateSecondary)

            // Text content - fills remaining space
            SelectableTextView(text: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(AppColors.substratePrimary)
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 500)
        #else
        NavigationView {
            SelectableTextView(text: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .background(AppColors.substratePrimary)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }

                    if onQuote != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: quoteFromClipboard) {
                                Label("Quote", systemImage: "text.quote")
                            }
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func quoteFromClipboard() {
        guard let clipboardText = AppClipboard.pasteString(), !clipboardText.isEmpty else {
            return
        }

        // Format as a quote block
        let lines = clipboardText.components(separatedBy: .newlines)
        let quotedLines = lines.map { "> \($0)" }
        let formattedQuote = quotedLines.joined(separator: "\n") + "\n\n"
        onQuote?(formattedQuote)
        dismiss()
    }
}

// MARK: - Selectable Text View (UIKit wrapper)

#if canImport(UIKit)
struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = UIColor(AppColors.textPrimary)
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }
}
#else
struct SelectableTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(AppColors.textPrimary)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 0, height: 0)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }
}
#endif

// MARK: - Message Separator

struct MessageSeparator: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.glassBorder.opacity(0.5))
            .frame(height: 1)
            .padding(.horizontal)
    }
}

// MARK: - Deleted Message Placeholder

struct DeletedMessageView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.circle")
                .font(.system(size: 16))
                .foregroundColor(AppColors.textTertiary)
            Text("This message was deleted")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textTertiary)
                .italic()
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - Streaming Content With Tools View

/// Represents a segment of content - either text or a tool call placeholder
private enum ContentSegment: Identifiable {
    case text(String)
    case toolPlaceholder(index: Int, toolName: String)

    var id: String {
        switch self {
        case .text(let content):
            return "text-\(content.hashValue)"
        case .toolPlaceholder(let index, _):
            return "tool-\(index)"
        }
    }
}

/// Renders streaming content with inline tool calls interleaved at their actual positions
struct StreamingContentWithToolsView: View {
    let content: String
    let toolCalls: [LiveToolCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let segments = parseContentSegments()

            ForEach(segments) { segment in
                switch segment {
                case .text(let text):
                    if !text.isEmpty {
                        AssistantMarkdownView(content: text)
                            .codeArtifactHost()
                    }

                case .toolPlaceholder(let index, let toolName):
                    // Find the matching tool call by index or name
                    if let toolCall = findToolCall(at: index, named: toolName) {
                        InlineToolCallView(toolCall: toolCall)
                    }
                }
            }

            // Show any remaining tool calls that weren't matched to placeholders
            // (handles case where tool calls exist but no markers in content)
            let unmatchedTools = toolCalls.enumerated().filter { index, _ in
                !segments.contains { segment in
                    if case .toolPlaceholder(let idx, _) = segment {
                        return idx == index
                    }
                    return false
                }
            }.map { $0.element }

            if !unmatchedTools.isEmpty && !hasAnyToolMarkers() {
                InlineToolCallsView(toolCalls: unmatchedTools)
            }
        }
    }

    /// Parse content into segments of text and tool placeholders
    private func parseContentSegments() -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var remaining = content
        var toolIndex = 0

        let pattern = "```tool_request\\s*\\n?([\\s\\S]*?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // No regex, return content as single text segment
            return [.text(content)]
        }

        while true {
            let range = NSRange(remaining.startIndex..., in: remaining)
            guard let match = regex.firstMatch(in: remaining, options: [], range: range) else {
                // No more matches - add remaining text
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(.text(trimmed))
                }
                break
            }

            // Extract text before this match
            if let beforeRange = Range(NSRange(location: 0, length: match.range.location), in: remaining) {
                let beforeText = String(remaining[beforeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !beforeText.isEmpty {
                    segments.append(.text(beforeText))
                }
            }

            // Extract tool name from the JSON if possible
            var toolName = ""
            if let jsonRange = Range(match.range(at: 1), in: remaining) {
                let jsonString = String(remaining[jsonRange])
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let name = json["tool"] as? String {
                    toolName = name
                }
            }

            // Add tool placeholder
            segments.append(.toolPlaceholder(index: toolIndex, toolName: toolName))
            toolIndex += 1

            // Move past this match
            if let matchRange = Range(match.range, in: remaining) {
                remaining = String(remaining[matchRange.upperBound...])
            } else {
                break
            }
        }

        return segments
    }

    /// Find a tool call by index or matching name
    private func findToolCall(at index: Int, named toolName: String) -> LiveToolCall? {
        // First try exact index match
        if index < toolCalls.count {
            return toolCalls[index]
        }

        // Fall back to name match
        if !toolName.isEmpty {
            return toolCalls.first { $0.name == toolName }
        }

        return nil
    }

    /// Check if content has any tool markers
    private func hasAnyToolMarkers() -> Bool {
        return content.contains("```tool_request")
    }
}

// MARK: - Streaming Indicator

/// Shows a streaming indicator while AI is generating
struct StreamingIndicator: View {
    let modelName: String?

    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 8) {
            // Pulsing dots
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppColors.textTertiary)
                        .frame(width: 6, height: 6)
                        .opacity(dotCount % 3 == index ? 1.0 : 0.3)
                }
            }

            Text("Generating")
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)

            Spacer()
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                dotCount += 1
            }
        }
    }
}

// MARK: - Truncation Detection

private struct TruncationPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Preview

#Preview("User Message") {
    VStack {
        UserMessageView(
            message: Message(
                conversationId: "test",
                role: .user,
                content: "Can you explain how SwiftUI's state management works?",
                timestamp: Date()
            ),
            onCopy: { _ in }
        )
    }
    .padding()
    .background(AppColors.substratePrimary)
}

#Preview("Assistant Message") {
    ScrollView {
        VStack {
            AssistantMessageView(
                message: Message(
                    conversationId: "test",
                    role: .assistant,
                    content: """
                    # SwiftUI State Management
                    
                    SwiftUI provides several property wrappers for managing state:
                    
                    ## @State
                    For simple value types owned by a view:
                    
                    ```swift
                    @State private var count = 0
                    ```
                    
                    ## @Binding
                    For passing state to child views:
                    
                    ```swift
                    @Binding var isPresented: Bool
                    ```
                    
                    ## @StateObject
                    For reference types (ObservableObject) owned by a view.
                    
                    ## @ObservedObject
                    For reference types passed from a parent view.
                    """,
                    timestamp: Date(),
                    modelName: "claude-3.5-sonnet",
                    providerName: "anthropic"
                ),
                overrideContent: nil,
                onCopy: { _ in },
                onRegenerate: { _ in }
            )
        }
    }
    .background(AppColors.substratePrimary)
}
