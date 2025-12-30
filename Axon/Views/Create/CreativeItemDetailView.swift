//
//  CreativeItemDetailView.swift
//  Axon
//
//  Detail view for a creative item showing full content and metadata.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct CreativeItemDetailView: View {
    @State private var item: CreativeItem

    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var playbackService = TTSPlaybackService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showShareSheet = false
    @State private var copied = false
    @State private var playbackError: String?
    @State private var showEditTitleAlert = false
    @State private var editedTitle = ""

    init(item: CreativeItem) {
        self._item = State(initialValue: item)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.substratePrimary
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Content display
                        contentView
                        
                        // Metadata card
                        metadataCard
                        
                        // Actions
                        actionButtons
                    }
                    .padding()
                }
            }
            .navigationTitle(item.displayTitle)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(AppColors.signalMercury)
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editedTitle = item.displayTitle
                            showEditTitleAlert = true
                        } label: {
                            Label("Edit Title", systemImage: "pencil")
                        }

                        Button {
                            shareItem()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            copyToClipboard()
                        } label: {
                            Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }

                        Divider()

                        Button(role: .destructive) {
                            CreativeGalleryService.shared.deleteItem(item)
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(AppColors.signalMercury)
                    }
                }
            }
            .alert("Edit Title", isPresented: $showEditTitleAlert) {
                TextField("Title", text: $editedTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    saveEditedTitle()
                }
            } message: {
                Text("Enter a new title for this item")
            }
        }
    }

    private func saveEditedTitle() {
        guard !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        item = CreativeGalleryService.shared.updateItemTitle(item, newTitle: editedTitle)
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch item.type {
        case .photo:
            photoContent
        case .video:
            videoContent
        case .audio:
            audioContent
        case .artifact:
            artifactContent
        }
    }
    
    private var photoContent: some View {
        Group {
            if let base64 = item.contentBase64,
               let data = Data(base64Encoded: base64),
               let image = PlatformImageCodec.image(from: data) {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(12)
                #endif
            } else if let urlString = item.contentURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                    case .failure:
                        contentPlaceholder(icon: "exclamationmark.triangle", message: "Failed to load image")
                    case .empty:
                        ProgressView()
                            .frame(height: 300)
                    @unknown default:
                        contentPlaceholder(icon: "photo", message: "Loading...")
                    }
                }
            } else {
                contentPlaceholder(icon: "photo", message: "Image not available")
            }
        }
    }
    
    private var videoContent: some View {
        contentPlaceholder(icon: "video.fill", message: "Video playback coming soon")
            .frame(height: 200)
    }
    
    private var audioContent: some View {
        VStack(spacing: 16) {
            // Audio visualization
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColors.signalMercury.opacity(0.1))
                    .frame(height: 120)

                if playbackService.isPlaying && playbackService.currentMessageId == item.id {
                    // Animated waveform when playing
                    HStack(spacing: 3) {
                        ForEach(0..<30, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.signalMercury)
                                .frame(width: 4, height: CGFloat.random(in: 20...80))
                                .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(Double(i) * 0.02), value: playbackService.isPlaying)
                        }
                    }
                } else {
                    // Static waveform
                    HStack(spacing: 3) {
                        ForEach(0..<30, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.signalMercury.opacity(0.5))
                                .frame(width: 4, height: CGFloat(20 + (i % 5) * 12))
                        }
                    }
                }
            }

            // Playback progress
            if playbackService.currentMessageId == item.id && playbackService.duration > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: playbackService.currentTime, total: playbackService.duration)
                        .tint(AppColors.signalMercury)

                    HStack {
                        Text(formatTime(playbackService.currentTime))
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                        Spacer()
                        Text(formatTime(playbackService.duration))
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal)
            }

            // Play/Pause button
            Button {
                toggleAudioPlayback()
            } label: {
                HStack(spacing: 8) {
                    if playbackService.isPlaying && playbackService.currentMessageId == item.id {
                        Image(systemName: "pause.fill")
                        Text("Pause")
                    } else {
                        Image(systemName: "play.fill")
                        Text("Play Audio")
                    }
                }
                .font(AppTypography.bodyMedium(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppColors.signalMercury)
                .cornerRadius(24)
            }

            // Error display
            if let error = playbackError {
                Text(error)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.accentError)
            }
        }
    }

    private func toggleAudioPlayback() {
        if playbackService.isPlaying && playbackService.currentMessageId == item.id {
            playbackService.pause()
        } else if playbackService.currentMessageId == item.id {
            playbackService.resume()
        } else {
            // Start new playback
            Task {
                await playAudio()
            }
        }
    }

    private func playAudio() async {
        playbackError = nil

        guard let base64 = item.contentBase64,
              let audioData = Data(base64Encoded: base64) else {
            // Try loading from URL if no base64
            if let urlString = item.contentURL,
               let url = URL(string: urlString),
               url.isFileURL {
                do {
                    let audioData = try Data(contentsOf: url)
                    try await playbackService.playAudioData(audioData, itemId: item.id, mimeType: item.mimeType)
                } catch {
                    playbackError = "Failed to load audio: \(error.localizedDescription)"
                }
            } else {
                playbackError = "Audio data not available"
            }
            return
        }

        do {
            try await playbackService.playAudioData(audioData, itemId: item.id, mimeType: item.mimeType)
        } catch {
            playbackError = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var artifactContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Language badge
            if let language = item.language {
                HStack {
                    Text(language.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.signalMercury)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.signalMercury.opacity(0.15))
                        .cornerRadius(6)
                    Spacer()
                    
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Copied" : "Copy")
                        }
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(AppColors.substrateSecondary)
                        .cornerRadius(6)
                    }
                }
            }
            
            // Code content
            if let base64 = item.contentBase64,
               let data = Data(base64Encoded: base64),
               let code = String(data: data, encoding: .utf8) {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(AppColors.substrateTertiary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
            }
        }
    }
    
    private func contentPlaceholder(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(AppColors.textTertiary)
            Text(message)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(AppColors.substrateTertiary)
        .cornerRadius(12)
    }
    
    // MARK: - Metadata Card
    
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: item.type.icon)
                    .foregroundColor(AppColors.signalMercury)
                Text(item.type.displayName)
                    .font(AppTypography.bodyMedium(.semibold))
                    .foregroundColor(AppColors.textPrimary)
            }
            
            Divider()
            
            metadataRow(label: "Created", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
            
            if let prompt = item.prompt {
                metadataRow(label: "Prompt", value: prompt)
            }
            
            if let fileSize = item.fileSize {
                metadataRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
            }
        }
        .padding(16)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
    }
    
    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 70, alignment: .leading)
            
            Text(value)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Go to Chat button
            Button {
                navigateToChat()
            } label: {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Go to Chat")
                }
                .font(AppTypography.bodyMedium(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.signalMercury)
                .cornerRadius(12)
            }
            
            // Share button
            Button {
                shareItem()
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share")
                }
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.substrateSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )
            }
        }
    }
    
    // MARK: - Actions
    
    private func navigateToChat() {
        dismiss()
        
        NotificationCenter.default.post(
            name: .navigateToConversation,
            object: nil,
            userInfo: [
                "conversationId": item.conversationId,
                "messageId": item.messageId
            ]
        )
    }
    
    private func copyToClipboard() {
        var stringToCopy: String?
        
        switch item.type {
        case .artifact:
            if let base64 = item.contentBase64,
               let data = Data(base64Encoded: base64),
               let code = String(data: data, encoding: .utf8) {
                stringToCopy = code
            }
        case .photo, .video:
            stringToCopy = item.contentURL
        case .audio:
            stringToCopy = item.contentURL
        }
        
        if let text = stringToCopy {
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            
            withAnimation {
                copied = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    copied = false
                }
            }
        }
    }
    
    private func shareItem() {
        #if os(iOS)
        var itemsToShare: [Any] = []
        
        if let base64 = item.contentBase64,
           let data = Data(base64Encoded: base64) {
            if item.type == .photo, let image = UIImage(data: data) {
                itemsToShare.append(image)
            } else {
                // Create temp file for other types
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(item.displayTitle).\(item.fileExtension)")
                try? data.write(to: tempURL)
                itemsToShare.append(tempURL)
            }
        } else if let urlString = item.contentURL, let url = URL(string: urlString) {
            itemsToShare.append(url)
        }
        
        guard !itemsToShare.isEmpty else { return }
        
        let activityVC = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the topmost presented view controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.maxY - 100, width: 0, height: 0)
            }
            topVC.present(activityVC, animated: true)
        }
        #endif
    }
}

// MARK: - Preview

#Preview {
    CreativeItemDetailView(item: CreativeItem(
        type: .photo,
        conversationId: "test-conv",
        messageId: "test-msg",
        title: "Test Image",
        prompt: "A beautiful sunset over mountains"
    ))
}
