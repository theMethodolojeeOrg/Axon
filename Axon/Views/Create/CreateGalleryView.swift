//
//  CreateGalleryView.swift
//  Axon
//
//  Main gallery view for the Create section.
//  Displays AI-generated images, audio, video, and artifacts.
//

import SwiftUI

struct CreateGalleryView: View {
    @StateObject private var galleryService = CreativeGalleryService.shared
    @StateObject private var conversationService = ConversationService.shared
    @StateObject private var creationService = DirectMediaCreationService.shared
    
    @State private var selectedFilter: GalleryFilter = .all
    @State private var selectedItem: CreativeItem?
    @State private var searchText = ""
    @State private var showingImageSheet = false
    @State private var showingAudioSheet = false
    @State private var showingVideoSheet = false
    @StateObject private var videoService = VideoGenerationService.shared
    
    @Environment(\.dismiss) private var dismiss
    
    private var filteredItems: [CreativeItem] {
        let items = galleryService.items(for: selectedFilter)
        
        if searchText.isEmpty {
            return items
        }
        
        return items.filter { item in
            item.displayTitle.localizedCaseInsensitiveContains(searchText) ||
            (item.prompt?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        ZStack {
            AppColors.substratePrimary
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search bar at top
                searchBar
                
                // Tab selector
                filterTabs
                
                Divider()
                    .background(AppColors.divider)
                
                // Content
                if galleryService.isLoading {
                    loadingView
                } else if filteredItems.isEmpty && !hasAnyCreateCard {
                    emptyStateView
                } else {
                    galleryGrid
                }
            }
        }
        .refreshable {
            await galleryService.loadAllItems()
        }
        .sheet(item: $selectedItem) { item in
            CreativeItemDetailView(item: item)
        }
        .sheet(isPresented: $showingImageSheet) {
            CreateImageSheet()
        }
        .sheet(isPresented: $showingAudioSheet) {
            CreateAudioSheet()
        }
        .sheet(isPresented: $showingVideoSheet) {
            CreateVideoSheet()
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textTertiary)
                
                TextField("Search creations...", text: $searchText)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textPrimary)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.substrateSecondary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppColors.glassBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppColors.substratePrimary)
    }
    
    // MARK: - Filter Tabs
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterTab(
                    title: "All",
                    count: galleryService.items.count,
                    isSelected: selectedFilter == .all
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = .all
                    }
                }
                
                ForEach(CreativeItemType.allCases) { type in
                    FilterTab(
                        title: type.displayName,
                        count: galleryService.count(for: type),
                        isSelected: selectedFilter == .type(type),
                        isComingSoon: !type.isAvailable
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = .type(type)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(AppColors.substrateSecondary)
    }
    
    // MARK: - Gallery Grid
    
    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 12)
                ],
                spacing: 12
            ) {
                // Create card for Photos section
                if shouldShowImageCreateCard {
                    CreateActionCard(
                        title: "Create an image",
                        subtitle: "with ChatGPT Image",
                        icon: "plus",
                        color: AppColors.signalMercury
                    ) {
                        showingImageSheet = true
                    }
                }
                
                // Create card for Audio section
                if shouldShowAudioCreateCard {
                    CreateActionCard(
                        title: "Create audio",
                        subtitle: "with Text-to-Speech",
                        icon: "plus",
                        color: AppColors.signalMercury
                    ) {
                        showingAudioSheet = true
                    }
                }
                
                // Create card for Video section
                if shouldShowVideoCreateCard {
                    CreateActionCard(
                        title: "Create a video",
                        subtitle: "with Veo or Sora",
                        icon: "plus",
                        color: AppColors.signalMercury
                    ) {
                        showingVideoSheet = true
                    }
                }
                
                ForEach(filteredItems) { item in
                    GalleryItemCard(item: item)
                        .onTapGesture {
                            selectedItem = item
                        }
                        .contextMenu {
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
                }
            }
            .padding()
        }
    }
    
    // Helpers for create card visibility
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
        shouldShowImageCreateCard || shouldShowAudioCreateCard || shouldShowVideoCreateCard
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            if case .type(let type) = selectedFilter {
                Image(systemName: type.icon)
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.textTertiary)
                
                Text(type.emptyStateMessage)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColors.textSecondary)
                
                if !type.isAvailable {
                    Text("Coming Soon")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.signalMercury)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColors.signalMercury.opacity(0.15))
                        .cornerRadius(8)
                }
            } else {
                Image(systemName: "paintpalette")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.textTertiary)
                
                Text("No Creations Yet")
                    .font(AppTypography.titleMedium())
                    .foregroundColor(AppColors.textSecondary)
                
                Text("Generate images, audio, or create artifacts in your chats. They'll appear here automatically.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Loading creations...")
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func navigateToChat(item: CreativeItem) {
        // Find and select the conversation
        if let conversation = conversationService.conversations.first(where: { $0.id == item.conversationId }) {
            dismiss()
            
            // Post notification to navigate to conversation
            NotificationCenter.default.post(
                name: .navigateToConversation,
                object: nil,
                userInfo: [
                    "conversationId": item.conversationId,
                    "messageId": item.messageId
                ]
            )
        }
    }
}

// MARK: - Filter Tab

private struct FilterTab: View {
    let title: String
    let count: Int
    let isSelected: Bool
    var isComingSoon: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(AppTypography.bodyMedium(isSelected ? .semibold : .regular))
                
                if count > 0 || isComingSoon {
                    Text(isComingSoon ? "Soon" : "\(count)")
                        .font(AppTypography.labelSmall())
                        .foregroundColor(isSelected ? .white : AppColors.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? AppColors.signalMercury : AppColors.substrateTertiary)
                        )
                }
            }
            .foregroundColor(isSelected ? AppColors.signalMercury : AppColors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? AppColors.signalMercury.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? AppColors.signalMercury.opacity(0.3) : AppColors.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gallery Item Card

private struct GalleryItemCard: View {
    let item: CreativeItem
    
    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            thumbnailView
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
            
            // Info bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                    
                    Text(item.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(AppColors.textTertiary)
                }
                
                Spacer()
                
                Image(systemName: item.type.icon)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(10)
            .background(AppColors.substrateSecondary)
        }
        .background(AppColors.substrateTertiary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        switch item.type {
        case .photo:
            photoThumbnail
        case .video:
            videoThumbnail
        case .audio:
            audioThumbnail
        case .artifact:
            artifactThumbnail
        }
    }
    
    private var photoThumbnail: some View {
        Group {
            if let base64 = item.contentBase64 ?? item.thumbnailBase64,
               let data = Data(base64Encoded: base64),
               let image = PlatformImageCodec.image(from: data) {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                #endif
            } else if let urlString = item.contentURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        imagePlaceholder(icon: "exclamationmark.triangle")
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        imagePlaceholder(icon: "photo")
                    }
                }
            } else {
                imagePlaceholder(icon: "photo")
            }
        }
    }
    
    private var videoThumbnail: some View {
        imagePlaceholder(icon: "video.fill")
            .overlay(
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white.opacity(0.8))
            )
    }
    
    private var audioThumbnail: some View {
        ZStack {
            AppColors.signalMercury.opacity(0.1)
            
            // Fake waveform visualization
            HStack(spacing: 3) {
                ForEach(0..<15, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.signalMercury)
                        .frame(width: 4, height: CGFloat.random(in: 20...60))
                }
            }
        }
    }
    
    private var artifactThumbnail: some View {
        ZStack {
            AppColors.substrateTertiary
            
            VStack(alignment: .leading, spacing: 4) {
                if let language = item.language {
                    HStack {
                        Text(language.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.signalMercury)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.signalMercury.opacity(0.15))
                            .cornerRadius(4)
                        Spacer()
                    }
                }
                
                // Code preview lines
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.textTertiary.opacity(0.3))
                            .frame(width: CGFloat.random(in: 40...120), height: 8)
                        Spacer()
                    }
                    .padding(.leading, CGFloat(i % 2) * 16)
                }
            }
            .padding(12)
        }
    }
    
    private func imagePlaceholder(icon: String) -> some View {
        ZStack {
            AppColors.substrateTertiary
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(AppColors.textTertiary)
        }
    }
}

// MARK: - Create Action Card

private struct CreateActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Title area
                VStack(spacing: 4) {
                    Text(title)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(color)
                    
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(color.opacity(0.8))
                }
                .frame(height: 50)
                
                // Plus icon area
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.1))
                        .frame(height: 80)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(color)
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

// MARK: - Notification Extension

extension Notification.Name {
    static let navigateToConversation = Notification.Name("navigateToConversation")
}

// MARK: - Preview

#Preview {
    CreateGalleryView()
}
