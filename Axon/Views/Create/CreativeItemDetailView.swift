//
//  CreativeItemDetailView.swift
//  Axon
//
//  Theater-style detail view for a creative item.
//

import SwiftUI
import AxonArtifacts
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
    @State private var imageLoaded = false

    init(item: CreativeItem) {
        self._item = State(initialValue: item)
    }

    private var accentColor: Color {
        switch item.type {
        case .photo:    return AppColors.signalMercury
        case .audio:    return AppColors.signalLichen
        case .video:    return AppColors.signalCopper
        case .artifact: return AppColors.signalHematite
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.substratePrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Full-bleed content area
                        contentArea

                        // Metadata + actions below
                        VStack(spacing: 16) {
                            metadataStrip
                            promptCard
                            actionBar
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(item.displayTitle)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(accentColor)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            editedTitle = item.displayTitle
                            showEditTitleAlert = true
                        } label: {
                            Label("Edit Title", systemImage: "pencil")
                        }
                        Button { shareItem() } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        Button { copyToClipboard() } label: {
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
                            .foregroundColor(accentColor)
                    }
                }
            }
            .alert("Edit Title", isPresented: $showEditTitleAlert) {
                TextField("Title", text: $editedTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") { saveEditedTitle() }
            } message: {
                Text("Enter a new title for this item")
            }
        }
    }

    private func saveEditedTitle() {
        guard !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        item = CreativeGalleryService.shared.updateItemTitle(item, newTitle: editedTitle)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch item.type {
        case .photo:    photoContent
        case .video:    videoContent
        case .audio:    audioContent
        case .artifact: artifactContent
        }
    }

    // MARK: - Photo Content

    private var photoContent: some View {
        Group {
            if let base64 = item.contentBase64,
               let data = Data(base64Encoded: base64),
               let image = PlatformImageCodec.image(from: data) {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                    .opacity(imageLoaded ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.3)) { imageLoaded = true }
                    }
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .opacity(imageLoaded ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeIn(duration: 0.3)) { imageLoaded = true }
                    }
                #endif
            } else if let urlString = item.contentURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().frame(maxWidth: .infinity)
                    case .failure:
                        contentPlaceholder(icon: "exclamationmark.triangle", label: "Failed to load")
                    case .empty:
                        ZStack {
                            AppColors.substrateTertiary
                            ProgressView().tint(accentColor)
                        }
                        .frame(height: 300)
                    @unknown default:
                        contentPlaceholder(icon: "photo", label: "Loading…")
                    }
                }
            } else {
                contentPlaceholder(icon: "photo", label: "Image not available")
            }
        }
    }

    // MARK: - Video Content

    private var videoContent: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.signalCopper.opacity(0.2), AppColors.signalCopperDark.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 220)

            VStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(AppColors.signalCopper.opacity(0.8))
                    .shadow(color: AppColors.signalCopper.opacity(0.3), radius: 16, x: 0, y: 8)

                Text("Video playback coming soon")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Audio Content

    private var audioContent: some View {
        VStack(spacing: 0) {
            // Waveform + player area — full bleed
            ZStack {
                LinearGradient(
                    colors: [AppColors.signalLichen.opacity(0.15), AppColors.signalLichenDark.opacity(0.25)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 200)

                VStack(spacing: 20) {
                    // Waveform visualization
                    waveformDisplay

                    // Progress bar (when playing)
                    if playbackService.currentMessageId == item.id && playbackService.duration > 0 {
                        VStack(spacing: 6) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(height: 3)
                                    Capsule()
                                        .fill(AppColors.signalLichen)
                                        .frame(
                                            width: geo.size.width * CGFloat(playbackService.currentTime / max(playbackService.duration, 1)),
                                            height: 3
                                        )
                                }
                            }
                            .frame(height: 3)
                            .padding(.horizontal, 32)

                            HStack {
                                Text(formatTime(playbackService.currentTime))
                                Spacer()
                                Text(formatTime(playbackService.duration))
                            }
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 32)
                        }
                        .transition(.opacity)
                    }

                    // Play button
                    Button { toggleAudioPlayback() } label: {
                        ZStack {
                            Circle()
                                .fill(AppColors.signalLichen)
                                .frame(width: 52, height: 52)
                                .shadow(color: AppColors.signalLichen.opacity(0.4), radius: 12, x: 0, y: 6)
                            Image(systemName: isPlayingThisItem ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .offset(x: isPlayingThisItem ? 0 : 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Error
            if let error = playbackError {
                Text(error)
                    .font(AppTypography.labelSmall())
                    .foregroundColor(AppColors.accentError)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
    }

    private var isPlayingThisItem: Bool {
        playbackService.isPlaying && playbackService.currentMessageId == item.id
    }

    private var waveformDisplay: some View {
        HStack(spacing: 3) {
            ForEach(Array(audioWaveHeights.enumerated()), id: \.offset) { idx, baseH in
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.signalLichen.opacity(isPlayingThisItem ? 0.85 : 0.45))
                    .frame(width: 4, height: isPlayingThisItem ? baseH : baseH * 0.5)
                    .animation(
                        isPlayingThisItem
                            ? .easeInOut(duration: 0.4 + Double(idx % 5) * 0.08)
                                .repeatForever(autoreverses: true)
                                .delay(Double(idx) * 0.03)
                            : .easeInOut(duration: 0.3),
                        value: isPlayingThisItem
                    )
            }
        }
    }

    private let audioWaveHeights: [CGFloat] = [
        18, 32, 50, 28, 56, 22, 44, 60, 26, 48, 20, 52, 34, 58, 24, 46, 30, 54, 16, 42, 56, 28, 48, 36, 52
    ]

    // MARK: - Artifact Content

    private func preparedWorkspace() -> ArtifactWorkspace? {
        guard var workspace = item.artifactWorkspace else { return nil }
        if let explicitEntry = item.artifactEntryPath, !explicitEntry.isEmpty {
            workspace.preview.entryPath = explicitEntry
        }
        workspace.title = item.displayTitle
        workspace.conversationId = item.conversationId
        workspace.messageId = item.messageId
        workspace.sourceItemId = item.sourceItemId ?? (item.isEditableFork ? item.sourceItemId : item.id)
        workspace.isEditableFork = item.isEditableFork
        workspace.isReadOnlySnapshot = !item.isEditableFork
        return workspace
    }

    @ViewBuilder
    private var artifactContent: some View {
        if let workspace = preparedWorkspace() {
            ArtifactWorkspaceEditorView(
                initialWorkspace: workspace,
                initialSelectedPath: workspace.entryPath,
                context: .gallery,
                onWorkspaceUpdated: { updated in
                    if let refreshed = CreativeGalleryService.shared.items.first(where: { $0.id == updated.id }) {
                        item = refreshed
                    }
                }
            )
        } else {
            legacyArtifactContent
        }
    }

    private var legacyArtifactContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language header bar
            HStack {
                if let language = item.language {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColors.signalHematite)
                            .frame(width: 8, height: 8)
                        Text(language.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.signalHematite)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.signalHematite.opacity(0.1))
                    .clipShape(Capsule())
                }
                Spacer()
                Button { copyToClipboard() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.signalHematite)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.signalHematite.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(AppColors.substrateTertiary)

            // Code content
            if let base64 = item.contentBase64,
               let data = Data(base64Encoded: base64),
               let code = String(data: data, encoding: .utf8) {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(code)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(AppColors.textPrimary)
                        .textSelection(.enabled)
                        .padding(20)
                }
                .background(AppColors.substrateTertiary)
                .frame(minHeight: 200)
            } else {
                contentPlaceholder(icon: "doc.text", label: "Code not available")
            }
        }
    }

    // MARK: - Metadata Strip

    private var metadataStrip: some View {
        HStack(spacing: 8) {
            // Type badge
            HStack(spacing: 5) {
                Image(systemName: item.type.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(item.type.displayName)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accentColor.opacity(0.1))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(accentColor.opacity(0.25), lineWidth: 1))

            // Date badge
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
            }
            .foregroundColor(AppColors.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColors.substrateSecondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(AppColors.glassBorder, lineWidth: 1))

            // File size badge (if available)
            if let fileSize = item.fileSize {
                Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColors.substrateSecondary)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppColors.glassBorder, lineWidth: 1))
            }

            Spacer()
        }
    }

    // MARK: - Prompt Card

    @ViewBuilder
    private var promptCard: some View {
        if let prompt = item.prompt, !prompt.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textTertiary)
                    Text("Prompt")
                        .font(AppTypography.labelMedium(.semibold))
                        .foregroundColor(AppColors.textTertiary)
                }
                Text(prompt)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.substrateSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.glassBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 10) {
            // Primary row: Share + Copy
            HStack(spacing: 10) {
                ActionButton(
                    label: "Share",
                    icon: "square.and.arrow.up",
                    style: .secondary
                ) { shareItem() }

                ActionButton(
                    label: copied ? "Copied!" : "Copy",
                    icon: copied ? "checkmark" : "doc.on.doc",
                    style: .secondary
                ) { copyToClipboard() }
            }

            // Secondary: Go to Chat
            ActionButton(
                label: "Go to Chat",
                icon: "bubble.left.and.bubble.right",
                style: .primary(accentColor)
            ) { navigateToChat() }
        }
    }

    // MARK: - Placeholder

    private func contentPlaceholder(icon: String, label: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(AppColors.textTertiary)
            Text(label)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(AppColors.substrateTertiary)
    }

    // MARK: - Actions

    private func navigateToChat() {
        dismiss()
        NotificationCenter.default.post(
            name: .navigateToConversation,
            object: nil,
            userInfo: ["conversationId": item.conversationId, "messageId": item.messageId]
        )
    }

    private func toggleAudioPlayback() {
        if playbackService.isPlaying && playbackService.currentMessageId == item.id {
            playbackService.pause()
        } else if playbackService.currentMessageId == item.id {
            playbackService.resume()
        } else {
            Task { await playAudio() }
        }
    }

    private func playAudio() async {
        playbackError = nil
        guard let base64 = item.contentBase64,
              let audioData = Data(base64Encoded: base64) else {
            if let urlString = item.contentURL,
               let url = URL(string: urlString),
               url.isFileURL {
                do {
                    let data = try Data(contentsOf: url)
                    try await playbackService.playAudioData(data, itemId: item.id, mimeType: item.mimeType)
                } catch {
                    playbackError = "Failed to load: \(error.localizedDescription)"
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
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
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
        default:
            stringToCopy = item.contentURL
        }
        if let text = stringToCopy {
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copied = false }
            }
        }
    }

    private func shareItem() {
        #if os(iOS)
        var itemsToShare: [Any] = []
        if let base64 = item.contentBase64, let data = Data(base64Encoded: base64) {
            if item.type == .photo, let image = UIImage(data: data) {
                itemsToShare.append(image)
            } else {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(item.displayTitle).\(item.fileExtension)")
                try? data.write(to: tempURL)
                itemsToShare.append(tempURL)
            }
        } else if let urlString = item.contentURL, let url = URL(string: urlString) {
            itemsToShare.append(url)
        }
        guard !itemsToShare.isEmpty else { return }
        let activityVC = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 100, width: 0, height: 0)
            }
            top.present(activityVC, animated: true)
        }
        #endif
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    enum Style {
        case primary(Color)
        case secondary
    }

    let label: String
    let icon: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(AppTypography.bodyMedium(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundColor(foregroundColor)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return AppColors.textPrimary
        }
    }

    private var background: some View {
        Group {
            switch style {
            case .primary(let color):
                AnyView(
                    LinearGradient(
                        colors: [color, color.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .secondary:
                AnyView(AppColors.substrateSecondary)
            }
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary(let color): return color.opacity(0.3)
        case .secondary: return AppColors.glassBorder
        }
    }
}

// MARK: - Preview

#Preview {
    CreativeItemDetailView(item: CreativeItem(
        type: .photo,
        conversationId: "test-conv",
        messageId: "test-msg",
        title: "Mountain Sunrise",
        prompt: "A misty mountain valley at dawn, golden cinematic light, photorealistic, 4K"
    ))
}
