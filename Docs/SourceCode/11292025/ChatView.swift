//
//  ChatView.swift
//  Axon
//
//  Main chat interface
//  NOTE: This view appears to be a legacy or standalone component.
//  The actual chat interface used in the app is ChatContainerView inside Axon/Views/Components/AppContainerView.swift.
//

import SwiftUI
import Combine
import Foundation
import PhotosUI
import UniformTypeIdentifiers
import MarkdownUI

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
    case custom
}

fileprivate func provider(for modelName: String?, providerName: String? = nil) -> ModelProvider {
    if let provider = providerName?.lowercased() {
        if provider == "anthropic" { return .anthropic }
        if provider == "openai" { return .openAI }
        if provider == "gemini" || provider == "google" { return .google }
        // Custom providers might use "openai-compatible" or other names
    }

    guard let name = modelName?.lowercased() else { return .custom }
    if name.contains("claude") || name.contains("anthropic") { return .anthropic }
    if name.contains("gpt") || name.contains("openai") { return .openAI }
    if name.contains("gemini") || name.contains("google") { return .google }
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
        // Anthropic – official warm terra cotta/orange #d97757
        return AnyShapeStyle(colorFromHex("#d97757"))
    case .openAI:
        // OpenAI – ChatGPT Green #00A67E
        return AnyShapeStyle(colorFromHex("#00A67E"))
    case .google:
        // Google Gemini – multi-color gradient
        let colors: [Color] = [
            colorFromHex("#fabc12"), // yellow/gold
            colorFromHex("#f94543"), // red
            colorFromHex("#3186ff"), // blue
            colorFromHex("#08b962")  // green
        ]
        return AnyShapeStyle(AngularGradient(gradient: Gradient(colors: colors), center: .center))
    case .custom:
        // Use persistent unique color for custom models/providers
        let key = (modelName ?? "custom-unknown").lowercased()
        let hex = ModelColorRegistry.shared.hex(forKey: key)
        return AnyShapeStyle(colorFromHex(hex))
    }
}

fileprivate struct ChatIconView: View {
    let provider: ModelProvider
    let modelName: String?

    var body: some View {
        Image("AxonChatIconTemplate")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
            .foregroundStyle(iconStyle(for: provider, modelName: modelName))
    }
}

struct ChatView: View {
    @StateObject private var conversationService = ConversationService.shared
    @State private var messageText = ""
    @State private var attachments: [MessageAttachment] = []
    @State private var useGeminiTools = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var showChatInfo = false
    @State private var localMessages: [Message] = []

    let conversation: Conversation
    
    private var messagesList: some View {
        ForEach(localMessages) { message in
            MessageBubble(
                message: message,
                onCopy: { msg in
                    #if canImport(UIKit)
                    UIPasteboard.general.string = msg.content
                    #elseif canImport(AppKit)
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(msg.content, forType: .string)
                    #endif
                },
                onRegenerate: { msg in
                    Task { await regenerate(message: msg) }
                }
            )
            .id(message.id)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            messagesList
                        }
                        .padding()
                    }
                    .refreshable {
                        // Pull-to-refresh: Force refresh messages from API
                        do {
                            let refreshedMessages = try await conversationService.refreshMessages(conversationId: conversation.id)
                            localMessages = refreshedMessages
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                    .onChange(of: localMessages.count) { _ in
                        if let lastMessage = localMessages.last {
                            withAnimation(AppAnimations.standardEasing) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input area
                MessageInputBar(
                    text: $messageText,
                    attachments: $selectedAttachments,
                    useGeminiTools: $useGeminiTools,
                    isLoading: isLoading,
                    onSend: sendMessage,
                    focus: $isInputFocused,
                    conversationId: conversation?.id
                )
            }

            // Audio player overlay (drops down from top)
            AudioPlayerView(ttsService: TTSPlaybackService.shared)
        }
        .background(AppColors.substratePrimary)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    Task {
                        await loadMessages()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showChatInfo = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.signalMercury)
                }
            }
        }
        .sheet(isPresented: $showChatInfo) {
            ChatInfoSettingsView(conversation: conversation)
        }
        .task {
            await loadMessages()
        }
        .onChange(of: conversation.id) { _ in
            // Clear messages when conversation changes
            localMessages = []
            Task {
                await loadMessages()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
            Button("Retry") {
                Task {
                    await retryLastMessage()
                }
            }
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
    }

    private func loadMessages() async {
        print("[ChatView] 🔄 Loading messages...")
        print("[ChatView] Conversation ID: \(conversation.id)")
        print("[ChatView] Conversation Title: \(conversation.title)")
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let fetchedMessages = try await conversationService.getMessages(conversationId: conversation.id)
            localMessages = fetchedMessages
            
            print("[ChatView] ✅ Loaded \(fetchedMessages.count) messages")
            if fetchedMessages.isEmpty {
                print("[ChatView] ⚠️ WARNING: No messages returned from API!")
                print("[ChatView] This conversation should have messages according to Firestore")
            } else {
                print("[ChatView] First message: \(fetchedMessages.first?.content.prefix(50) ?? "N/A")")
                print("[ChatView] Last message: \(fetchedMessages.last?.content.prefix(50) ?? "N/A")")
            }
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
            showingError = true
            
            print("[ChatView] ❌ Error loading messages: \(error)")
            print("[ChatView] Error details: \(String(describing: error))")
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmed.isEmpty && attachments.isEmpty) else { return }

        let content = messageText
        let attachmentsToSend = attachments
        messageText = ""
        attachments = []
        isLoading = true

        Task {
            do {
                _ = try await conversationService.sendMessage(
                    conversationId: conversation.id,
                    content: content,
                    attachments: attachmentsToSend,
                    geminiTools: useGeminiTools
                )
                
                // Reset tools flag after sending
                useGeminiTools = false
                
                // Reload messages to get both user and assistant messages
                await loadMessages()
            } catch {
                errorMessage = "Failed to send message: \(error.localizedDescription)\n\nPlease check:\n• Your API key is configured in Settings\n• You have internet connection\n• The message is valid"
                showingError = true
                // Restore the message text so user can retry
                messageText = content
                attachments = attachmentsToSend
            }
            isLoading = false
        }
    }

    private func retryLastMessage() async {
        if !messageText.isEmpty {
            sendMessage()
        }
    }
    
    private func regenerate(message: Message) async {
        guard let convId = conversationService.currentConversation?.id ?? conversation.id as String? else { return }
        do {
            _ = try await conversationService.regenerateAssistantMessage(conversationId: convId, messageId: message.id)
            // Reload messages after regeneration
            await loadMessages()
        } catch {
            errorMessage = "Failed to regenerate: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let onCopy: (Message) -> Void
    let onRegenerate: (Message) -> Void
    let overrideContent: String?

    @ObservedObject private var ttsService = TTSPlaybackService.shared

    init(
        message: Message,
        onCopy: @escaping (Message) -> Void,
        onRegenerate: @escaping (Message) -> Void,
        overrideContent: String? = nil
    ) {
        self.message = message
        self.onCopy = onCopy
        self.onRegenerate = onRegenerate
        self.overrideContent = overrideContent
    }

    private var isUser: Bool {
        message.role == .user
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button(action: { onCopy(message) }) {
            Label("Copy", systemImage: "doc.on.doc")
        }
        
        if !isUser {
            Button(action: { onRegenerate(message) }) {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            
            if ttsService.hasGeneratedAudio(for: message.id) {
                Button(action: {
                    Task {
                        do {
                            try await ttsService.playGenerated(messageId: message.id)
                        } catch {
                            print("[TTS] Failed to play generated audio: \(error)")
                        }
                    }
                }) {
                    Label("Play Generated", systemImage: "play.circle.fill")
                }
            }
            
            Button(action: {
                Task {
                    do {
                        let settings = SettingsViewModel.shared.settings
                        try await ttsService.speak(text: message.content, settings: settings, messageId: message.id)
                    } catch {
                        print("[TTS] Failed to speak: \(error)")
                    }
                }
            }) {
                Label("Speak", systemImage: "speaker.wave.2.fill")
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser {
                // AI avatar with model label
                VStack(spacing: 4) {
                    ChatIconView(provider: provider(for: message.modelName, providerName: message.providerName), modelName: message.modelName)
                        .frame(width: 32, height: 32)

                    // Model label
                    if let modelName = message.modelName {
                        Text(modelName)
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: 60)
            }

            let bubbleAlignment: HorizontalAlignment = isUser ? .trailing : .leading
            let frameAlignment: Alignment = isUser ? .trailing : .leading
            VStack(alignment: bubbleAlignment, spacing: 8) {
                let textToRender = overrideContent ?? message.content

                // Attachments
                if let attachments = message.attachments, !attachments.isEmpty {
                    ForEach(attachments) { attachment in
                        if attachment.type == .image, let base64 = attachment.base64,
                           let data = Data(base64Encoded: base64),
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 200, maxHeight: 200)
                                .cornerRadius(12)
                                .padding(.bottom, 4)
                        } else if attachment.type == .document {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(AppColors.textPrimary)
                                Text(attachment.name ?? "Document")
                                    .font(AppTypography.bodySmall())
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            .padding(8)
                            .background(AppColors.substrateTertiary)
                            .cornerRadius(8)
                            .padding(.bottom, 4)
                        }
                    }
                }

                // Message content
                Group {
                    if isUser {
                        Text(textToRender)
                            .font(AppTypography.bodyMedium())
                            .foregroundColor(AppColors.textPrimary)
                    } else {
                        Markdown(textToRender)
                            .markdownTheme(MarkdownTheme.axon)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isUser ? AppColors.signalLichen.opacity(0.2) : AppColors.substrateSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    isUser ? AppColors.signalLichen.opacity(0.3) : AppColors.glassBorder,
                                    lineWidth: 1
                                )
                        )
                )
                .contextMenu {
                    contextMenuContent
                }

                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)

            if isUser {
                // User avatar
                Circle()
                    .fill(AppColors.signalLichen)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
            }
        }
    }
}

// MARK: - Message Input Bar

struct MessageInputBar: View {
    @Binding var text: String
    @Binding var attachments: [MessageAttachment]
    @Binding var useGeminiTools: Bool
    let isLoading: Bool
    let onSend: () -> Void
    let focus: FocusState<Bool>.Binding?

    @State private var selectedItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    
    private let conversationId: String?

    private struct AttachmentCapability {
        let images: Bool
        let documents: Bool
        let description: String
    }

    init(
        text: Binding<String>,
        attachments: Binding<[MessageAttachment]> = .constant([]),
        useGeminiTools: Binding<Bool> = .constant(false),
        isLoading: Bool,
        onSend: @escaping () -> Void,
        focus: FocusState<Bool>.Binding? = nil,
        conversationId: String? = nil
    ) {
        self._text = text
        self._attachments = attachments
        self._useGeminiTools = useGeminiTools
        self.isLoading = isLoading
        self.onSend = onSend
        self.focus = focus
        self.conversationId = conversationId
    }
    
    private var attachmentCapability: AttachmentCapability {
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        var providerString = settings.defaultProvider.rawValue
        
        if let conversationId = conversationId {
            let overridesKey = "conversation_overrides_\(conversationId)"
            if let data = UserDefaults.standard.data(forKey: overridesKey),
               let overrides = try? JSONDecoder().decode(ConversationOverrides.self, from: data) {
                
                if overrides.customProviderId != nil {
                    providerString = "openai-compatible"
                } else if let builtInProvider = overrides.builtInProvider {
                    providerString = builtInProvider
                }
            } else if settings.selectedCustomProviderId != nil {
                providerString = "openai-compatible"
            }
        } else if settings.selectedCustomProviderId != nil {
            providerString = "openai-compatible"
        }
        
        switch providerString {
        case "anthropic":
            return AttachmentCapability(images: true, documents: true, description: "Claude supports images and PDFs.")
        case "gemini":
            return AttachmentCapability(images: true, documents: true, description: "Gemini supports images and documents.")
        case "openai":
            return AttachmentCapability(images: true, documents: false, description: "GPT supports images only.")
        case "grok":
            return AttachmentCapability(images: true, documents: false, description: "Grok supports images only.")
        case "openai-compatible":
            return AttachmentCapability(images: true, documents: false, description: "Images supported; docs depend on the provider.")
        default:
            return AttachmentCapability(images: true, documents: false, description: "Images supported.")
        }
    }
    
    @ViewBuilder
    private var textFieldView: some View {
        if let focus = focus {
            TextField("Type a message...", text: $text, axis: .vertical)
                .focused(focus)
        } else {
            TextField("Type a message...", text: $text, axis: .vertical)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Attachments Preview
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            ZStack(alignment: .topTrailing) {
                                if attachment.type == .image, let base64 = attachment.base64,
                                   let data = Data(base64Encoded: base64),
                                   let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                } else {
                                    VStack {
                                        Image(systemName: "doc.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(AppColors.textPrimary)
                                        Text(attachment.name ?? "File")
                                            .font(AppTypography.labelSmall())
                                            .lineLimit(1)
                                            .foregroundColor(AppColors.textPrimary)
                                    }
                                    .frame(width: 60, height: 60)
                                    .background(AppColors.substrateTertiary)
                                    .cornerRadius(8)
                                }

                                // Remove button
                                Button(action: {
                                    if let index = attachments.firstIndex(where: { $0.id == attachment.id }) {
                                        attachments.remove(at: index)
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }

            GlassCard(padding: 12) {
                HStack(spacing: 12) {
                    let capability = attachmentCapability

                    // Attachment Button
                    Group {
                        if capability.images {
                            Menu {
                                Button(action: { showPhotoPicker = true }) {
                                    Label("Photo Library", systemImage: "photo")
                                }
                                
                                if capability.documents {
                                    Button(action: { showFileImporter = true }) {
                                        Label("Document", systemImage: "doc")
                                    }
                                }
                                
                                Text(capability.description)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                            } label: {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.textSecondary)
                                    .frame(width: 32, height: 32)
                            }
                            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
                        } else if capability.documents {
                            Menu {
                                Button(action: { showFileImporter = true }) {
                                    Label("Document", systemImage: "doc")
                                }
                                
                                Text(capability.description)
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                            } label: {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.textSecondary)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }

                    // Gemini Tools Toggle
                    Button(action: { useGeminiTools.toggle() }) {
                        Image(systemName: useGeminiTools ? "sparkles" : "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(useGeminiTools ? AppColors.signalMercury : AppColors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(useGeminiTools ? AppColors.signalMercury.opacity(0.1) : Color.clear)
                            .clipShape(Circle())
                    }

                    // Text field
                    textFieldView
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.substrateTertiary)
                        .cornerRadius(20)
                        .disabled(isLoading)
                        .lineLimit(1...5)

                    // Send button
                    Button(action: onSend) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor((text.trimmingCharacters(in: .whitespaces).isEmpty && attachments.isEmpty)
                                    ? AppColors.textDisabled
                                    : AppColors.signalMercury
                                )
                        }
                    }
                    .disabled(isLoading || (text.trimmingCharacters(in: .whitespaces).isEmpty && attachments.isEmpty))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let compressedData = uiImage.jpegData(compressionQuality: 0.7) {
                    let base64 = compressedData.base64EncodedString()
                    let attachment = MessageAttachment(
                        type: .image,
                        base64: base64,
                        name: "image.jpg",
                        mimeType: "image/jpeg"
                    )
                    attachments.append(attachment)
                    selectedItem = nil
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: attachmentCapability.documents ? [.pdf, .text, .image, .item] : [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if url.startAccessingSecurityScopedResource() {
                    defer { url.stopAccessingSecurityScopedResource() }
                    if let data = try? Data(contentsOf: url) {
                        let base64 = data.base64EncodedString()
                        let attachment = MessageAttachment(
                            type: .document,
                            base64: base64,
                            name: url.lastPathComponent,
                            mimeType: url.pathExtension
                        )
                        attachments.append(attachment)
                    }
                }
            case .failure(let error):
                print("File import failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ChatView(conversation: Conversation(
            userId: "user1",
            title: "Test Conversation",
            projectId: "default",
            messageCount: 5,
            summary: "A test conversation"
        ))
    }
}
