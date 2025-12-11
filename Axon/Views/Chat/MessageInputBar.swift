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
    @ObservedObject private var settingsViewModel = SettingsViewModel.shared

    private let conversationId: String?

    private struct AttachmentCapability {
        let images: Bool
        let documents: Bool
        let description: String
    }

    /// Whether tools are enabled based on settings
    private var hasToolsEnabled: Bool {
        settingsViewModel.settings.toolSettings.toolsEnabled &&
        !settingsViewModel.settings.toolSettings.enabledToolIds.isEmpty
    }

    /// Count of enabled tools for display
    private var enabledToolCount: Int {
        settingsViewModel.settings.toolSettings.enabledToolIds.count
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

                    // Tools Status Indicator
                    // Shows if tools are enabled in Settings > Tools
                    // Tapping shows info tooltip
                    Menu {
                        if hasToolsEnabled {
                            Text("\(enabledToolCount) tool\(enabledToolCount == 1 ? "" : "s") enabled")
                            ForEach(settingsViewModel.settings.toolSettings.enabledTools, id: \.id) { tool in
                                Label(tool.displayName, systemImage: tool.icon)
                            }
                            Divider()
                            Text("Configure in Settings > Tools")
                                .font(.caption)
                        } else {
                            Text("No tools enabled")
                            Divider()
                            Text("Enable tools in Settings > Tools")
                                .font(.caption)
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundColor(hasToolsEnabled ? AppColors.signalMercury : AppColors.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(hasToolsEnabled ? AppColors.signalMercury.opacity(0.1) : Color.clear)
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
                        let mimeType = getMimeType(for: url)
                        let attachment = MessageAttachment(
                            type: .document,
                            base64: base64,
                            name: url.lastPathComponent,
                            mimeType: mimeType
                        )
                        attachments.append(attachment)
                    }
                }
            case .failure(let error):
                print("File import failed: \(error.localizedDescription)")
            }
        }
    }

    private func getMimeType(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        switch pathExtension {
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
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }
}
