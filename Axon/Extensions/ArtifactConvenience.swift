//
//  ArtifactConvenience.swift
//  Axon
//
//  Backward-compatible computed-property wrappers that delegate to the
//  Axon-Artifacts package using the app's shared ArtifactEnvironmentLoader.
//

import Foundation
import AxonArtifacts

// MARK: - Axon-specific ArtifactEnvironmentLoader configuration

/// Call once at app launch to inject Axon's app support directory.
enum AxonArtifactEnvironmentBootstrap {
    static func configure() {
        ArtifactEnvironmentLoader.shared = ArtifactEnvironmentLoader(
            appSupportDirectoryProvider: {
                FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("Axon", isDirectory: true)
            }
        )
    }
}

// MARK: - ArtifactWorkspaceFile convenience

extension ArtifactWorkspaceFile {
    var inferredLanguage: String {
        inferredLanguage(using: ArtifactEnvironmentLoader.shared.baseResolver())
    }

    var isHTMLLike: Bool {
        isHTMLLike(using: ArtifactEnvironmentLoader.shared.baseResolver())
    }
}

// MARK: - ArtifactWorkspace convenience

extension ArtifactWorkspace {
    var entryPath: String? {
        entryPath(using: .shared)
    }

    var hasRenderableWebContent: Bool {
        hasRenderableWebContent(using: .shared)
    }

    var resolvedEntryPath: String? {
        resolvedEntryPath(using: .shared)
    }
}

// MARK: - CodeArtifact convenience

extension CodeArtifact {
    var fileExtension: String {
        fileExtension(using: ArtifactEnvironmentLoader.shared.baseResolver())
    }

    var exportFileURL: URL {
        let base = (title.isEmpty ? "code" : title)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = "\(base).\(fileExtension)"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? code.data(using: .utf8)?.write(to: url, options: [.atomic])
        return url
    }
}
