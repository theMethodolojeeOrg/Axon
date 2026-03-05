//
//  CreateGalleryView.swift
//  Axon
//
//  Studio-style gallery for AI-generated images, audio, video, and artifacts.
//

import SwiftUI
import AxonArtifacts

enum GalleryViewMode: String, CaseIterable {
    case grid
    case list

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct CreateGalleryView: View {
    @StateObject private var galleryService = CreativeGalleryService.shared
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var creationService = DirectMediaCreationService.shared
    @StateObject private var generativeViewStorageService = GenerativeViewStorageService.shared

    @State private var selectedFilter: GalleryFilter = .all
    @State private var selectedItem: CreativeItem?
    @State private var searchText = ""
    @State private var showingImageSheet = false
    @State private var showingAudioSheet = false
    @State private var showingVideoSheet = false
    @State private var showEditTitleAlert = false
    @State private var editingItem: CreativeItem?
    @State private var editedTitle = ""
    @State private var viewMode: GalleryViewMode = .grid
    @StateObject private var videoService = VideoGenerationService.shared
    @State private var searchFocused = false

    @Environment(\.dismiss) private var dismiss

    private var filteredItems: [CreativeItem] {
        let items = galleryService.items(for: selectedFilter)
        if searchText.isEmpty { return items }
        return items.filter { item in
            item.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            (item.prompt?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.substratePrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Creation Studio Strip
                if selectedFilter == .all || selectedFilter == .type(.photo) ||
                   selectedFilter == .type(.audio) || selectedFilter == .type(.video) {
                    creationStrip
                }

                // Search + Filter bar
                searchFilterBar

                Divider().background(AppColors.divider)

                // Content
                if galleryService.isLoading {
                    loadingView
                } else if filteredItems.isEmpty && !hasAnyCreateCard && selectedFilter != .views {
                    emptyStateView
                } else {
                    switch viewMode {
                    case .grid: galleryGrid
                    case .list: galleryList
                    }
                }
            }
        }
        .task {
            await generativeViewStorageService.loadAllViews()
        }
        .refreshable {
            await galleryService.loadAllItems()
            await generativeViewStorageService.loadAllViews()
        }
        .sheet(item: $selectedItem) { item in
            if let workspace = workspaceForEditor(from: item) {
                ArtifactWorkspaceEditorView(
                    initialWorkspace: workspace,
                    initialSelectedPath: workspace.entryPath,
                    context: .gallery,
                    onWorkspaceUpdated: { updated in
                        if let refreshed = galleryService.items.first(where: { $0.id == updated.id }) {
                            selectedItem = refreshed
                        }
                    }
                )
            } else {
                CreativeItemDetailView(item: item)
            }
        }
        .navigationDestination(isPresented: $showingImageSheet) { CreateImageSheet() }
        .navigationDestination(isPresented: $showingAudioSheet) { CreateAudioSheet() }
        .navigationDestination(isPresented: $showingVideoSheet) { CreateVideoSheet() }
        .alert("Edit Title", isPresented: $showEditTitleAlert) {
            TextField("Title", text: $editedTitle)
            Button("Cancel", role: .cancel) { editingItem = nil }
            Button("Save") { saveEditedTitle() }
        } message: {
            Text("Enter a new title for this item")
        }
    }

    private func saveEditedTitle() {
        guard let item = editingItem,
              !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            editingItem = nil
            return
        }
        galleryService.updateItemTitle(item, newTitle: editedTitle)
        editingItem = nil
    }

    // MARK: - Creation Strip

    private var creationStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if shouldShowImageCreateCard {
                    StudioCreateCard(
                        title: "Image",
                        subtitle: "ChatGPT Image",
                        icon: "sparkles",
                        gradient: [AppColors.signalMercury, AppColors.signalMercuryDark]
                    ) { showingImageSheet = true }
                }
                if shouldShowAudioCreateCard {
                    StudioCreateCard(
                        title: "Audio",
                        subtitle: "Text-to-Speech",
                        icon: "waveform",
                        gradient: [AppColors.signalLichen, AppColors.signalLichenDark]
                    ) { showingAudioSheet = true }
                }
                if shouldShowVideoCreateCard {
                    StudioCreateCard(
                        title: "Video",
                        subtitle: "Veo · Sora",
                        icon: "video.fill",
                        gradient: [AppColors.signalCopper, AppColors.signalCopperDark]
                    ) { showingVideoSheet = true }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(height: StudioCreateCard.totalHeight + 20)
        .background(AppColors.substratePrimary)
    }

    // MARK: - Search + Filter Bar

    private var searchFilterBar: some View {
        VStack(spacing: 0) {
            // Search row
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(searchText.isEmpty ? AppColors.textTertiary : AppColors.signalMercury)

                    TextField("Search creations…", text: $searchText)
                        .font(AppTypography.bodyMedium())
                        .foregroundColor(AppColors.textPrimary)

                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppColors.textTertiary)
                                .font(.system(size: 14))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppColors.substrateSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(searchText.isEmpty ? AppColors.glassBorder : AppColors.signalMercury.opacity(0.4), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)

                // View mode toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = viewMode == .grid ? .list : .grid
                    }
                } label: {
                    Image(systemName: viewMode == .grid ? GalleryViewMode.list.icon : GalleryViewMode.grid.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppColors.substrateSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.glassBorder, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Filter tabs
            filterTabs
        }
        .background(AppColors.substratePrimary)
    }

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                StudioFilterTab(title: "All", count: galleryService.items.count, isSelected: selectedFilter == .all, icon: "square.grid.2x2.fill") {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedFilter = .all }
                }
                ForEach(CreativeItemType.allCases) { type in
                    StudioFilterTab(
                        title: type.displayName,
                        count: galleryService.count(for: type),
                        isSelected: selectedFilter == .type(type),
                        isComingSoon: !type.isAvailable,
                        icon: type.icon
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) { selectedFilter = .type(type) }
                    }
                }
                StudioFilterTab(title: "Views", count: generativeViewStorageService.allViews.count, isSelected: selectedFilter == .views, icon: "sparkle.magnifyingglass") {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedFilter = .views }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Gallery Grid

    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 156, maximum: 210), spacing: 10)],
                spacing: 10
            ) {
                if selectedFilter == .views {
                    GenerativeViewGallerySection(viewMode: .grid, searchText: searchText)
                } else {
                    ForEach(filteredItems) { item in
                        StudioGalleryCard(item: item)
                            .onTapGesture { selectedItem = item }
                            .contextMenu { itemContextMenu(item) }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Gallery List

    private var galleryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if selectedFilter == .views {
                    GenerativeViewGallerySection(viewMode: .list, searchText: searchText)
                } else {
                    ForEach(filteredItems) { item in
                        StudioGalleryListRow(item: item)
                            .onTapGesture { selectedItem = item }
                            .contextMenu { itemContextMenu(item) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func itemContextMenu(_ item: CreativeItem) -> some View {
        Button {
            editingItem = item
            editedTitle = item.displayTitle
            showEditTitleAlert = true
        } label: {
            Label("Edit Title", systemImage: "pencil")
        }
        Button {
            navigateToChat(item: item)
        } label: {
            Label("Go to Chat", systemImage: "bubble.left.and.bubble.right")
        }
        Divider()
        Button(role: .destructive) {
            galleryService.deleteItem(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private var shouldShowImageCreateCard: Bool {
        creationService.hasOpenAIKey && (selectedFilter == .all || selectedFilter == .type(.photo))
    }
    private var shouldShowAudioCreateCard: Bool {
        !creationService.availableTTSProviders.isEmpty && (selectedFilter == .all || selectedFilter == .type(.audio))
    }
    private var shouldShowVideoCreateCard: Bool {
        (videoService.hasGeminiKey || videoService.hasOpenAIKey) && (selectedFilter == .all || selectedFilter == .type(.video))
    }
    private var hasAnyCreateCard: Bool {
        shouldShowImageCreateCard || shouldShowAudioCreateCard || shouldShowVideoCreateCard || selectedFilter == .views
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(AppColors.signalMercury.opacity(0.08))
                    .frame(width: 88, height: 88)
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(AppColors.signalMercury.opacity(0.6))
            }
            VStack(spacing: 8) {
                Text(emptyStateTitle)
                    .font(AppTypography.titleMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)
                Text(emptyStateSubtitle)
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }
            Spacer()
        }
    }

    private var emptyStateIcon: String {
        if case .type(let type) = selectedFilter { return type.icon }
        return "paintpalette"
    }
    private var emptyStateTitle: String {
        if case .type(let type) = selectedFilter { return "No \(type.displayName) Yet" }
        return "Nothing Here Yet"
    }
    private var emptyStateSubtitle: String {
        if case .type(let type) = selectedFilter {
            return type.isAvailable ? type.emptyStateMessage : "Coming soon"
        }
        return "Generate images, audio, or videos. They'll appear here automatically."
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .tint(AppColors.signalMercury)
            Text("Loading…")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textTertiary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func navigateToChat(item: CreativeItem) {
        if conversationService.conversations.first(where: { $0.id == item.conversationId }) != nil {
            dismiss()
            NotificationCenter.default.post(
                name: .navigateToConversation,
                object: nil,
                userInfo: ["conversationId": item.conversationId, "messageId": item.messageId]
            )
        }
    }

    private func workspaceForEditor(from item: CreativeItem) -> ArtifactWorkspace? {
        guard item.type == .artifact,
              var workspace = item.artifactWorkspace else {
            return nil
        }

        workspace.title = item.displayTitle
        workspace.conversationId = item.conversationId
        workspace.messageId = item.messageId
        if let explicitEntry = item.artifactEntryPath, !explicitEntry.isEmpty {
            workspace.preview.entryPath = explicitEntry
        }
        workspace.sourceItemId = item.sourceItemId ?? (item.isEditableFork ? item.sourceItemId : item.id)
        workspace.isEditableFork = item.isEditableFork
        workspace.isReadOnlySnapshot = !item.isEditableFork
        return workspace
    }
}

// MARK: - Studio Create Card

private struct StudioCreateCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    let action: () -> Void

    /// Total card height: gradient area (72) + label area (42)
    static let gradientHeight: CGFloat = 72
    static let labelHeight: CGFloat = 42
    static let totalHeight: CGFloat = gradientHeight + labelHeight

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Icon + gradient fill
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: gradient.map { $0.opacity(0.85) } + [gradient.last!.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Decorative circles
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 70, height: 70)
                        .offset(x: 72, y: -18)

                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 44, height: 44)
                        .offset(x: 96, y: 26)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.leading, 14)
                        .padding(.bottom, 12)
                }
                .frame(width: 130, height: StudioCreateCard.gradientHeight)
                .clipped()

                // Label area
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodyMedium(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(width: 130, height: StudioCreateCard.labelHeight, alignment: .leading)
                .background(AppColors.substrateSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 130)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
        .shadow(color: gradient.first!.opacity(0.2), radius: 8, x: 0, y: 4)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Studio Filter Tab

private struct StudioFilterTab: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var isComingSoon: Bool = false
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
                }
                Text(title)
                    .font(AppTypography.labelMedium(isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)

                if count > 0 || isComingSoon {
                    Text(isComingSoon ? "Soon" : "\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? .white : AppColors.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? AppColors.signalMercury : AppColors.substrateTertiary)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppColors.signalMercury.opacity(0.25) : AppColors.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Studio Gallery Card (Grid)

private struct StudioGalleryCard: View {
    let item: CreativeItem

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
            thumbnailView
                .frame(height: 148)
                .frame(maxWidth: .infinity)
                .clipped()

            // Info strip
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(AppTypography.labelSmall(.medium))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(item.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                Spacer()
                Image(systemName: item.type.icon)
                    .font(.system(size: 11))
                    .foregroundColor(accentColor.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(AppColors.substrateSecondary)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.shadow.opacity(0.4), radius: 6, x: 0, y: 3)
    }

    private var accentColor: Color {
        switch item.type {
        case .photo: return AppColors.signalMercury
        case .audio: return AppColors.signalLichen
        case .video: return AppColors.signalCopper
        case .artifact: return AppColors.signalHematite
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        switch item.type {
        case .photo: photoThumbnail
        case .video: videoThumbnail
        case .audio: audioThumbnail
        case .artifact: artifactThumbnail
        }
    }

    private var photoThumbnail: some View {
        Group {
            if let base64 = item.contentBase64 ?? item.thumbnailBase64,
               let data = Data(base64Encoded: base64),
               let image = PlatformImageCodec.image(from: data) {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFill()
                #elseif canImport(AppKit)
                Image(nsImage: image).resizable().scaledToFill()
                #endif
            } else if let urlString = item.contentURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: iconPlaceholder("exclamationmark.triangle")
                    case .empty: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default: iconPlaceholder("photo")
                    }
                }
            } else {
                iconPlaceholder("photo")
            }
        }
    }

    private var videoThumbnail: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.signalCopper.opacity(0.25), AppColors.signalCopperDark.opacity(0.4)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "play.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        }
    }

    private var audioThumbnail: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.signalLichen.opacity(0.2), AppColors.signalLichenDark.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            HStack(spacing: 3) {
                ForEach(0..<18, id: \.self) { i in
                    let heights: [CGFloat] = [14, 28, 42, 22, 50, 18, 36, 48, 20, 44, 16, 38, 52, 24, 40, 18, 34, 28]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.signalLichen.opacity(0.7))
                        .frame(width: 4, height: heights[i % heights.count])
                }
            }
        }
    }

    private var artifactThumbnail: some View {
        ZStack {
            AppColors.substrateTertiary
            VStack(alignment: .leading, spacing: 5) {
                if let language = item.language {
                    Text(language.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.signalHematite)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(AppColors.signalHematite.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                ForEach(0..<5, id: \.self) { i in
                    let widths: [CGFloat] = [90, 60, 110, 40, 80]
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.textTertiary.opacity(0.25))
                            .frame(width: CGFloat(i % 2) * 14, height: 7)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.textTertiary.opacity(0.35))
                            .frame(width: widths[i], height: 7)
                        Spacer()
                    }
                }
            }
            .padding(12)
        }
    }

    private func iconPlaceholder(_ icon: String) -> some View {
        ZStack {
            AppColors.substrateTertiary
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(AppColors.textTertiary)
        }
    }
}

// MARK: - Studio Gallery List Row

private struct StudioGalleryListRow: View {
    let item: CreativeItem

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppColors.glassBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: item.type.icon)
                        .font(.system(size: 11))
                        .foregroundColor(accentColor.opacity(0.8))
                    Text(item.type.displayName)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                    Text("·")
                        .foregroundColor(AppColors.textTertiary)
                    Text(item.createdAt, style: .relative)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }

                if let prompt = item.prompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(AppTypography.bodySmall())
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
    }

    private var accentColor: Color {
        switch item.type {
        case .photo: return AppColors.signalMercury
        case .audio: return AppColors.signalLichen
        case .video: return AppColors.signalCopper
        case .artifact: return AppColors.signalHematite
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        switch item.type {
        case .photo: photoThumbnail
        case .video: videoThumbnail
        case .audio: audioThumbnail
        case .artifact: artifactThumbnail
        }
    }

    private var photoThumbnail: some View {
        Group {
            if let base64 = item.contentBase64 ?? item.thumbnailBase64,
               let data = Data(base64Encoded: base64),
               let image = PlatformImageCodec.image(from: data) {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFill()
                #elseif canImport(AppKit)
                Image(nsImage: image).resizable().scaledToFill()
                #endif
            } else if let urlString = item.contentURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: iconPlaceholder("photo")
                    }
                }
            } else {
                iconPlaceholder("photo")
            }
        }
    }

    private var videoThumbnail: some View {
        ZStack {
            LinearGradient(colors: [AppColors.signalCopper.opacity(0.3), AppColors.signalCopperDark.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "play.fill").font(.system(size: 18)).foregroundColor(.white.opacity(0.85))
        }
    }

    private var audioThumbnail: some View {
        ZStack {
            LinearGradient(colors: [AppColors.signalLichen.opacity(0.25), AppColors.signalLichenDark.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "waveform").font(.system(size: 22)).foregroundColor(AppColors.signalLichen)
        }
    }

    private var artifactThumbnail: some View {
        ZStack {
            AppColors.substrateTertiary
            Image(systemName: "doc.text").font(.system(size: 22)).foregroundColor(AppColors.textTertiary)
        }
    }

    private func iconPlaceholder(_ icon: String) -> some View {
        ZStack {
            AppColors.substrateTertiary
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(AppColors.textTertiary)
        }
    }
}

// MARK: - Create Action Card / Row (kept for external use)

struct CreateActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                VStack(spacing: 4) {
                    Text(title).font(AppTypography.labelSmall()).foregroundColor(color)
                    Text(subtitle).font(.system(size: 10)).foregroundColor(color.opacity(0.8))
                }
                .frame(height: 50)
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)).frame(height: 80)
                    Image(systemName: icon).font(.system(size: 24, weight: .medium)).foregroundColor(color)
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .background(AppColors.substrateTertiary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
    }
}

struct CreateActionListRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)).frame(width: 60, height: 60)
                    Image(systemName: icon).font(.system(size: 24)).foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(AppTypography.bodyMedium(.medium)).foregroundColor(color)
                    Text(subtitle).font(AppTypography.bodySmall()).foregroundColor(color.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .medium)).foregroundColor(color.opacity(0.6))
            }
            .padding(12)
        }
        .buttonStyle(.plain)
        .background(AppColors.substrateTertiary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let navigateToConversation = Notification.Name("navigateToConversation")
}

// MARK: - Preview

#Preview {
    CreateGalleryView()
}
