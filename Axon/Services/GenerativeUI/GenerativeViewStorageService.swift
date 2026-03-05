//
//  GenerativeViewStorageService.swift
//  Axon
//
//  Storage service for generative views
//  Handles bundled templates and user-created views in Documents
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class GenerativeViewStorageService: ObservableObject {
    static let shared = GenerativeViewStorageService()

    // MARK: - Published State

    @Published private(set) var bundledTemplates: [GenerativeViewDefinition] = []
    @Published private(set) var userViews: [GenerativeViewDefinition] = []
    @Published private(set) var isLoading = false

    /// All views combined, sorted by date (newest first)
    var allViews: [GenerativeViewDefinition] {
        (bundledTemplates + userViews).sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Private

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var userViewsDirectory: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("GenerativeViews", isDirectory: true)
    }

    // MARK: - Initialization

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Ensure user views directory exists
        createUserViewsDirectoryIfNeeded()
    }

    // MARK: - Loading

    /// Load all views (bundled templates + user views)
    func loadAllViews() async {
        isLoading = true
        defer { isLoading = false }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadBundledTemplates() }
            group.addTask { await self.loadUserViews() }
        }
    }

    /// Load bundled templates from Resources/GenerativeUI/Templates/
    func loadBundledTemplates() async {
        var templates: [GenerativeViewDefinition] = []

        // Try to load templates from bundle
        guard let templatesURL = Bundle.main.url(
            forResource: "Templates",
            withExtension: nil,
            subdirectory: "GenerativeUI"
        ) else {
            // No templates directory - check for individual files
            templates = loadIndividualBundleTemplates()
            await MainActor.run { bundledTemplates = templates }
            return
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: templatesURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for fileURL in contents where fileURL.pathExtension == "json" {
                if let template = loadTemplateFromURL(fileURL) {
                    templates.append(template)
                }
            }
        } catch {
            print("[GenerativeViewStorage] Failed to load templates directory: \(error)")
            templates = loadIndividualBundleTemplates()
        }

        await MainActor.run { bundledTemplates = templates }
    }

    /// Fallback: load individual template files from bundle
    private func loadIndividualBundleTemplates() -> [GenerativeViewDefinition] {
        var templates: [GenerativeViewDefinition] = []

        let templateNames = ["blank", "card", "list_item", "dashboard"]

        for name in templateNames {
            if let url = Bundle.main.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "GenerativeUI/Templates"
            ), let template = loadTemplateFromURL(url) {
                templates.append(template)
            }
        }

        return templates
    }

    /// Load a single template from a URL
    private func loadTemplateFromURL(_ url: URL) -> GenerativeViewDefinition? {
        do {
            let data = try Data(contentsOf: url)

            // Try to decode as GenerativeViewFile first (has version wrapper)
            if let viewFile = try? decoder.decode(GenerativeViewFile.self, from: data) {
                var definition = viewFile.definition
                // Force bundle source for bundled templates
                definition = GenerativeViewDefinition(
                    id: definition.id,
                    name: definition.name,
                    createdAt: definition.createdAt,
                    updatedAt: definition.updatedAt,
                    root: definition.root,
                    source: .bundle,
                    thumbnailBase64: definition.thumbnailBase64
                )
                return definition
            }

            // Fall back to raw GenerativeUINode (simple template format)
            let node = try decoder.decode(GenerativeUINode.self, from: data)
            let name = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "_", with: " ")
                .capitalized

            return GenerativeViewDefinition.fromBundle(
                id: UUID(uuidString: "template-\(name.lowercased())") ?? UUID(),
                name: name,
                root: node
            )
        } catch {
            print("[GenerativeViewStorage] Failed to load template \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Load user-created views from Documents/GenerativeViews/
    func loadUserViews() async {
        guard let directory = userViewsDirectory else {
            await MainActor.run { userViews = [] }
            return
        }

        var views: [GenerativeViewDefinition] = []

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            for fileURL in contents where fileURL.pathExtension == "json" {
                if let view = loadUserViewFromURL(fileURL) {
                    views.append(view)
                }
            }
        } catch {
            print("[GenerativeViewStorage] Failed to load user views: \(error)")
        }

        await MainActor.run { userViews = views }
    }

    /// Load a single user view from URL
    private func loadUserViewFromURL(_ url: URL) -> GenerativeViewDefinition? {
        do {
            let data = try Data(contentsOf: url)
            let viewFile = try decoder.decode(GenerativeViewFile.self, from: data)
            return viewFile.definition
        } catch {
            print("[GenerativeViewStorage] Failed to load user view \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    // MARK: - Saving

    /// Save a user view to Documents
    func saveUserView(_ view: GenerativeViewDefinition) throws {
        guard let directory = userViewsDirectory else {
            throw StorageError.directoryNotFound
        }

        let fileURL = directory.appendingPathComponent("\(view.id.uuidString).json")
        let viewFile = GenerativeViewFile(definition: view)
        let data = try encoder.encode(viewFile)
        try data.write(to: fileURL)

        // Update in-memory list
        if let index = userViews.firstIndex(where: { $0.id == view.id }) {
            userViews[index] = view
        } else {
            userViews.append(view)
        }

        print("[GenerativeViewStorage] Saved view: \(view.name) (\(view.id))")
    }

    /// Create and save a new user view
    func createNewView(name: String = "Untitled View") throws -> GenerativeViewDefinition {
        var view = GenerativeViewDefinition.newUserView(name: name)
        try saveUserView(view)
        return view
    }

    /// Duplicate a view (creates a user copy)
    func duplicateView(_ view: GenerativeViewDefinition) throws -> GenerativeViewDefinition {
        var newView = GenerativeViewDefinition(
            id: UUID(),
            name: "\(view.name) Copy",
            createdAt: Date(),
            updatedAt: Date(),
            root: view.root,
            source: .userCreated,
            thumbnailBase64: view.thumbnailBase64
        )
        try saveUserView(newView)
        return newView
    }

    // MARK: - Deleting

    /// Delete a user view
    func deleteUserView(id: UUID) throws {
        guard let directory = userViewsDirectory else {
            throw StorageError.directoryNotFound
        }

        let fileURL = directory.appendingPathComponent("\(id.uuidString).json")

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        // Remove from in-memory list
        userViews.removeAll { $0.id == id }

        print("[GenerativeViewStorage] Deleted view: \(id)")
    }

    // MARK: - Lookup

    /// Find a view by ID
    func view(for id: UUID) -> GenerativeViewDefinition? {
        allViews.first { $0.id == id }
    }

    // MARK: - Thumbnail Generation

    /// Generate a thumbnail for a view (call from main actor)
    @MainActor
    func generateThumbnail(for view: GenerativeViewDefinition) -> Data? {
        let renderer = ImageRenderer(content:
            GenerativeUIRenderer.render(view.root)
                .frame(width: 200, height: 150)
                .background(AppColors.substratePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        )
        renderer.scale = 2.0

        #if os(iOS)
        return renderer.uiImage?.pngData()
        #else
        if let cgImage = renderer.cgImage {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 150))
            return nsImage.tiffRepresentation
        }
        return nil
        #endif
    }

    /// Update thumbnail for a view and save
    func updateThumbnail(for viewId: UUID) async {
        guard var view = view(for: viewId), view.source == .userCreated else { return }

        if let thumbnailData = generateThumbnail(for: view) {
            view.thumbnailBase64 = thumbnailData.base64EncodedString()
            try? saveUserView(view)
        }
    }

    // MARK: - Private Helpers

    private func createUserViewsDirectoryIfNeeded() {
        guard let directory = userViewsDirectory else { return }

        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                print("[GenerativeViewStorage] Created user views directory: \(directory.path)")
            } catch {
                print("[GenerativeViewStorage] Failed to create directory: \(error)")
            }
        }
    }

    // MARK: - Errors

    enum StorageError: LocalizedError {
        case directoryNotFound
        case encodingFailed
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .directoryNotFound: return "User views directory not found"
            case .encodingFailed: return "Failed to encode view data"
            case .decodingFailed: return "Failed to decode view data"
            }
        }
    }
}
