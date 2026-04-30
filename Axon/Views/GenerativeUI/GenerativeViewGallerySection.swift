//
//  GenerativeViewGallerySection.swift
//  Axon
//
//  Gallery section displaying saved generative views
//  Integrates with CreateGalleryView
//

import SwiftUI

/// Grid/list display of generative views for the Create gallery
struct GenerativeViewGallerySection: View {
    @StateObject private var storageService = GenerativeViewStorageService.shared
    @State private var selectedView: GenerativeViewDefinition?
    @State private var showingCanvas = false
    @State private var showingViewer = false
    @State private var editingView: GenerativeViewDefinition?

    let viewMode: GalleryViewMode
    let searchText: String

    private var filteredViews: [GenerativeViewDefinition] {
        if searchText.isEmpty {
            return storageService.allViews
        }
        return storageService.allViews.filter { view in
            view.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            // Create new view card
            if viewMode == .grid {
                CreateActionCard(
                    title: "Create a view",
                    subtitle: "with Generative UI",
                    icon: "plus",
                    color: AppColors.signalLichen
                ) {
                    createNewView()
                }
            } else {
                CreateActionListRow(
                    title: "Create a view",
                    subtitle: "with Generative UI",
                    icon: "plus.circle.fill",
                    color: AppColors.signalLichen
                ) {
                    createNewView()
                }
            }

            // Existing views
            ForEach(filteredViews) { view in
                if viewMode == .grid {
                    GenerativeViewCard(view: view)
                        .onTapGesture {
                            selectedView = view
                            showingViewer = true
                        }
                        .contextMenu {
                            viewContextMenu(for: view)
                        }
                } else {
                    GenerativeViewRow(view: view)
                        .onTapGesture {
                            selectedView = view
                            showingViewer = true
                        }
                        .contextMenu {
                            viewContextMenu(for: view)
                        }
                }
            }
        }
        .task {
            await storageService.loadAllViews()
        }
#if os(iOS) || os(tvOS)
        .fullScreenCover(isPresented: $showingCanvas) {
            if let view = editingView {
                GenerativeViewCanvas(
                    initialView: view,
                    onSave: { savedView in
                        try? storageService.saveUserView(savedView)
                        showingCanvas = false
                        editingView = nil
                    },
                    onCancel: {
                        showingCanvas = false
                        editingView = nil
                    }
                )
            }
        }
#else
        .sheet(isPresented: $showingCanvas) {
            Group {
            if let view = editingView {
                GenerativeViewCanvas(
                    initialView: view,
                    onSave: { savedView in
                        try? storageService.saveUserView(savedView)
                        showingCanvas = false
                        editingView = nil
                    },
                    onCancel: {
                        showingCanvas = false
                        editingView = nil
                    }
                )
            }

            }
            .appSheetMaterial()
}
#endif
        .sheet(isPresented: $showingViewer) {
            Group {
            if let view = selectedView {
                GenerativeViewViewer(
                    view: view,
                    onEdit: {
                        showingViewer = false
                        editingView = view
                        showingCanvas = true
                    }
                )
            }

            }
            .appSheetMaterial()
}
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func viewContextMenu(for view: GenerativeViewDefinition) -> some View {
        Button {
            editingView = view
            showingCanvas = true
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button {
            duplicateView(view)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        if view.source == .userCreated {
            Divider()

            Button(role: .destructive) {
                deleteView(view)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func createNewView() {
        do {
            let newView = try storageService.createNewView()
            editingView = newView
            showingCanvas = true
        } catch {
            print("[GenerativeViewGallery] Failed to create new view: \(error)")
        }
    }

    private func duplicateView(_ view: GenerativeViewDefinition) {
        do {
            let copy = try storageService.duplicateView(view)
            editingView = copy
            showingCanvas = true
        } catch {
            print("[GenerativeViewGallery] Failed to duplicate view: \(error)")
        }
    }

    private func deleteView(_ view: GenerativeViewDefinition) {
        do {
            try storageService.deleteUserView(id: view.id)
        } catch {
            print("[GenerativeViewGallery] Failed to delete view: \(error)")
        }
    }
}

// MARK: - Grid Card

struct GenerativeViewCard: View {
    let view: GenerativeViewDefinition

    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            thumbnailView
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()

            // Info bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(view.name)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        if view.source == .bundle {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text("Template")
                                .font(.system(size: 10))
                        } else {
                            Text(view.updatedAt, style: .relative)
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundColor(AppColors.textTertiary)
                }

                Spacer()

                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.signalLichen)
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
        if let base64 = view.thumbnailBase64,
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
        } else {
            // Render a mini preview
            ZStack {
                AppColors.substratePrimary

                GenerativeUIRenderer.render(view.root)
                    .scaleEffect(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }
}

// MARK: - List Row

struct GenerativeViewRow: View {
    let view: GenerativeViewDefinition

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(view.name)
                    .font(AppTypography.bodyMedium(.medium))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if view.source == .bundle {
                        Label("Template", systemImage: "doc.text")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.signalMercury)
                    } else {
                        Label("\(view.nodeCount) nodes", systemImage: "square.stack.3d.up")
                            .font(AppTypography.labelSmall())
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Text("•")
                        .foregroundColor(AppColors.textTertiary)

                    Text(view.updatedAt, style: .relative)
                        .font(AppTypography.labelSmall())
                        .foregroundColor(AppColors.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.textTertiary)
        }
        .padding(12)
        .background(AppColors.substrateSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            AppColors.substrateTertiary

            if let base64 = view.thumbnailBase64,
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
            } else {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 24))
                    .foregroundColor(AppColors.signalLichen)
            }
        }
    }
}

// Note: CreateActionListRow is defined in CreateGalleryView.swift

