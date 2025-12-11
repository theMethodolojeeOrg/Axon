//
//  MessageViews.swift
//  Axon
//
//  Modern chat message views - user bubbles and free-flowing assistant content
//

import SwiftUI
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
    case xai
    case custom
}

fileprivate func provider(for modelName: String?, providerName: String? = nil) -> ModelProvider {
    if let provider = providerName?.lowercased() {
        if provider == "anthropic" { return .anthropic }
        if provider == "openai" || provider == "openai-compatible" { return .openAI }
        if provider == "gemini" || provider == "google" { return .google }
        if provider == "xai" || provider == "grok" { return .xai }
    }

    guard let name = modelName?.lowercased() else { return .custom }
    if name.contains("claude") || name.contains("anthropic") { return .anthropic }
    if name.contains("gpt") || name.contains("openai") { return .openAI }
    if name.contains("gemini") || name.contains("google") { return .google }
    if name.contains("grok") || name.contains("xai") { return .xai }
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
                
                // Message content (text selection enabled for partial copy)
                Text(message.content)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                    .textSelection(.enabled)
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
    }
}

// MARK: - Assistant Message View

struct AssistantMessageView: View {
    let message: Message
    let overrideContent: String?
    let onCopy: (Message) -> Void
    let onRegenerate: (Message) -> Void
    
    @ObservedObject private var ttsService = TTSPlaybackService.shared
    
    private var textToRender: String {
        overrideContent ?? message.content
    }
    
    private var modelProvider: ModelProvider {
        provider(for: message.modelName, providerName: message.providerName)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Attachments (if any from assistant - rare but possible)
            if let attachments = message.attachments, !attachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(attachments) { attachment in
                        attachmentView(for: attachment)
                    }
                }
                .padding(.bottom, 12)
            }
            
            // Main content - free flowing markdown (text selection enabled for partial copy)
            Markdown(textToRender)
                .markdownTheme(MarkdownTheme.axon)
                .textSelection(.enabled)
            
            // Footer toolbar
            AssistantToolbar(
                message: message,
                onCopy: onCopy,
                onRegenerate: onRegenerate
            )
            .padding(.top, 12)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func attachmentView(for attachment: MessageAttachment) -> some View {
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
    }
}

// MARK: - Assistant Toolbar

struct AssistantToolbar: View {
    let message: Message
    let onCopy: (Message) -> Void
    let onRegenerate: (Message) -> Void
    
    @ObservedObject private var ttsService = TTSPlaybackService.shared
    
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
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.signalMercury)
                    }
                } else {
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
    }
}

// MARK: - Message Separator

struct MessageSeparator: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.glassBorder.opacity(0.5))
            .frame(height: 1)
            .padding(.horizontal)
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
