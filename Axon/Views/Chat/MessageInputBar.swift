//
//  MessageInputBar.swift
//  Axon
//
//  Message input field with attachment support and tools toggle
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct MessageInputBar: View {
    @Binding var text: String
    @Binding var attachments: [MessageAttachment]
    let isLoading: Bool
    let onSend: () -> Void
    let focus: FocusState<Bool>.Binding?

    @State private var selectedItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var showVideoImporter = false
    @State private var showAudioImporter = false

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
        focus: FocusState<Bool>.Binding? = nil,
        conversationId: String? = nil
    ) {
        self._text = text
        self._attachments = attachments
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
            // Claude: images and PDFs only
            return AttachmentCapability(images: true, documents: true, video: false, audio: false, description: "Claude supports images and PDFs.")
        case "gemini":
            // Gemini: full multimodal support including video and audio
            return AttachmentCapability(images: true, documents: true, video: true, audio: true, description: "Gemini supports images, documents, video, and audio.")
        case "openai":
            // GPT-4o: images only (audio input requires special handling)
            return AttachmentCapability(images: true, documents: false, video: false, audio: false, description: "GPT supports images.")
        case "grok":
            // Grok: images only (JPEG, PNG)
            return AttachmentCapability(images: true, documents: false, video: false, audio: false, description: "Grok supports images only.")
        case "openai-compatible":
            return AttachmentCapability(images: true, documents: false, video: false, audio: false, description: "Images supported; other formats depend on the provider.")
        default:
            return AttachmentCapability(images: true, documents: false, video: false, audio: false, description: "Images supported.")
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
                                        Image(systemName: attachmentIcon(for: attachment.type))
                                            .font(.system(size: 24))
                                            .foregroundColor(attachmentIconColor(for: attachment.type))
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

            GlassCard(padding: 10, cornerRadius: 26) {
                HStack(spacing: 10) {
                    let capability = attachmentCapability

                    // Attachment Button
                    Group {
                        if capability.images || capability.documents || capability.video || capability.audio {
                            Menu {
                                if capability.images {
                                    Button(action: { showPhotoPicker = true }) {
                                        Label("Photo Library", systemImage: "photo")
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
                                    .font(AppTypography.labelSmall())
                                    .foregroundColor(AppColors.textSecondary)
                            } label: {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.textSecondary)
                                    .frame(width: 32, height: 32)
                            }
                            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
                        }
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
            guard let newItem = newItem else { return }
            Task {
                // Always reset selectedItem to allow re-selecting the same photo
                defer { selectedItem = nil }

                do {
                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                        print("[MessageInputBar] Failed to load photo data")
                        return
                    }
                    guard let uiImage = UIImage(data: data) else {
                        print("[MessageInputBar] Failed to create UIImage from data")
                        return
                    }
                    guard let compressedData = uiImage.jpegData(compressionQuality: 0.7) else {
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
                    attachments.append(attachment)
                    print("[MessageInputBar] Successfully added image attachment (\(compressedData.count) bytes)")
                } catch {
                    print("[MessageInputBar] Photo loading error: \(error.localizedDescription)")
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
                guard let url = urls.first else {
                    print("[MessageInputBar] File import: No URL returned")
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    print("[MessageInputBar] Failed to access security-scoped resource: \(url.lastPathComponent)")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let base64 = data.base64EncodedString()
                    let mimeType = getMimeType(for: url)
                    let attachment = MessageAttachment(
                        type: .document,
                        base64: base64,
                        name: url.lastPathComponent,
                        mimeType: mimeType
                    )
                    attachments.append(attachment)
                    print("[MessageInputBar] Successfully added document: \(url.lastPathComponent) (\(data.count) bytes)")
                } catch {
                    print("[MessageInputBar] Failed to read file data: \(error.localizedDescription)")
                }
            case .failure(let error):
                print("[MessageInputBar] File import failed: \(error.localizedDescription)")
            }
        }
        // Video file importer
        .fileImporter(
            isPresented: $showVideoImporter,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    print("[MessageInputBar] Video import: No URL returned")
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    print("[MessageInputBar] Failed to access security-scoped resource for video: \(url.lastPathComponent)")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    // Check file size - warn if >20MB (Gemini inline limit)
                    let fileSizeMB = Double(data.count) / (1024 * 1024)
                    if fileSizeMB > 20 {
                        print("[MessageInputBar] Warning: Video file is \(String(format: "%.1f", fileSizeMB))MB. Files >20MB should use File API upload.")
                    }

                    let base64 = data.base64EncodedString()
                    let mimeType = getMimeType(for: url)
                    let attachment = MessageAttachment(
                        type: .video,
                        base64: base64,
                        name: url.lastPathComponent,
                        mimeType: mimeType
                    )
                    attachments.append(attachment)
                    print("[MessageInputBar] Successfully added video: \(url.lastPathComponent) (\(String(format: "%.1f", fileSizeMB))MB)")
                } catch {
                    print("[MessageInputBar] Failed to read video data: \(error.localizedDescription)")
                }
            case .failure(let error):
                print("[MessageInputBar] Video import failed: \(error.localizedDescription)")
            }
        }
        // Audio file importer
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio, .mp3, .wav, .aiff, .mpeg4Audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    print("[MessageInputBar] Audio import: No URL returned")
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    print("[MessageInputBar] Failed to access security-scoped resource for audio: \(url.lastPathComponent)")
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                do {
                    let data = try Data(contentsOf: url)
                    let base64 = data.base64EncodedString()
                    let mimeType = getMimeType(for: url)
                    let attachment = MessageAttachment(
                        type: .audio,
                        base64: base64,
                        name: url.lastPathComponent,
                        mimeType: mimeType
                    )
                    attachments.append(attachment)
                    print("[MessageInputBar] Successfully added audio: \(url.lastPathComponent) (\(data.count) bytes)")
                } catch {
                    print("[MessageInputBar] Failed to read audio data: \(error.localizedDescription)")
                }
            case .failure(let error):
                print("[MessageInputBar] Audio import failed: \(error.localizedDescription)")
            }
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

        // Video formats (Gemini supported)
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

        // Audio formats (Gemini supported)
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

    /// Determine attachment type from URL extension
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
