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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(AppColors.signalLichen.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(AppColors.signalLichen.opacity(0.3), lineWidth: 1)
                        )
                )
                .contextMenu {
                    Button(action: { onCopy(message) }) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }

            // User avatar
            Circle()
                .fill(AppColors.signalLichen)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                )
        }
        .padding(.horizontal)
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

            // Main content with inline tool calls during streaming
            if let toolCalls = liveToolCalls, !toolCalls.isEmpty {
                // Streaming mode with tool calls - interleave content and tools
                StreamingContentWithToolsView(
                    content: textToRender,
                    toolCalls: toolCalls
                )
            } else {
                // Standard markdown rendering
                AssistantMarkdownView(content: textToRender)
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

            // Footer toolbar (hide during streaming)
            if !isStreaming {
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
        .padding(.horizontal)
        .padding(.vertical, 8)
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
        HStack(spacing: 12) {
            // Model icon
            Image("AxonChatIconTemplate")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(iconStyle(for: modelProvider, modelName: message.modelName))

            // Model name
            if let modelName = message.modelName {
                Text(modelName)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                // Select Text button - opens sheet with selectable text
                Button(action: { showTextSelector = true }) {
                    Image(systemName: "selection.pin.in.out")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)
                }

                // Quote button - inserts clipboard content as formatted quote
                if onQuote != nil {
                    Button(action: quoteFromClipboard) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                // Copy button
                Button(action: { onCopy(message) }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)
                }

                // Regenerate button
                Button(action: { onRegenerate(message) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(AppColors.textTertiary)
                }

                // TTS button
                let settings = SettingsViewModel.shared.settings
                if ttsService.hasGeneratedAudio(for: message.id, settings: settings) {
                    Button(action: {
                        Task {
                            do {
                                try await ttsService.playGenerated(messageId: message.id, settings: settings)
                            } catch {
                                print("[TTS] Failed to play generated audio: \(error)")
                            }
                        }
                    }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.signalMercury)
                    }
                } else {
                    Button(action: {
                        Task {
                            do {
                                try await ttsService.speak(text: message.content, settings: settings, messageId: message.id)
                            } catch {
                                print("[TTS] Failed to speak: \(error)")
                            }
                        }
                    }) {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }

            // Timestamp
            Text(message.timestamp, style: .time)
                .font(AppTypography.labelSmall())
                .foregroundColor(AppColors.textTertiary)
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
        NavigationView {
            SelectableTextView(text: content)
                .padding()
                .background(AppColors.substratePrimary)
                .navigationTitle("Select Text")
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
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
        #if os(macOS)
        .frame(minWidth: 450, idealWidth: 550, minHeight: 350, idealHeight: 450)
        #else
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
struct SelectableTextView: View {
    let text: String

    var body: some View {
        Text(text)
            .textSelection(.enabled)
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

// MARK: - Streaming Content With Tools View

/// Renders streaming content with inline tool calls
struct StreamingContentWithToolsView: View {
    let content: String
    let toolCalls: [LiveToolCall]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Render content up to first tool call marker
            let (textBeforeTools, hasToolMarker) = extractTextBeforeTools()

            if !textBeforeTools.isEmpty {
                AssistantMarkdownView(content: textBeforeTools)
                    .codeArtifactHost()
            }

            // Render inline tool calls
            if !toolCalls.isEmpty {
                InlineToolCallsView(toolCalls: toolCalls)
            }

            // If there's content after the tool request marker, render it
            if hasToolMarker {
                let textAfterTools = extractTextAfterTools()
                if !textAfterTools.isEmpty {
                    AssistantMarkdownView(content: textAfterTools)
                        .codeArtifactHost()
                }
            }
        }
    }

    /// Extract text before any tool_request block
    private func extractTextBeforeTools() -> (String, Bool) {
        // Look for tool_request code block
        let patterns = [
            "```tool_request",
            "```tool_request\n",
            "```\ntool_request"
        ]

        for pattern in patterns {
            if let range = content.range(of: pattern) {
                let before = String(content[..<range.lowerBound])
                return (before.trimmingCharacters(in: .whitespacesAndNewlines), true)
            }
        }

        // No tool marker found - return all content
        return (content, false)
    }

    /// Extract text after the tool_request block (if any)
    private func extractTextAfterTools() -> String {
        // Look for closing ``` after tool_request
        guard let startRange = content.range(of: "```tool_request") else {
            return ""
        }

        let afterStart = content[startRange.upperBound...]

        // Find the closing ```
        guard let endRange = afterStart.range(of: "```") else {
            return ""
        }

        let afterEnd = afterStart[endRange.upperBound...]
        return String(afterEnd).trimmingCharacters(in: .whitespacesAndNewlines)
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
