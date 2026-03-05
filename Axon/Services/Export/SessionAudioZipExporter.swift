//
//  SessionAudioZipExporter.swift
//  Axon
//
//  Builds a ZIP bundle containing any generated TTS audio for a conversation.
//

import Foundation

/// Exports generated TTS audio files for a conversation.
///
/// Two modes:
/// - cachedOnly: only include files already present in Documents/AudioCache
/// - includeRemoteIfAvailable: if audio metadata exists and is synced, fetch missing files from CloudKit (AudioSyncService)
struct SessionAudioZipExporter {

    enum Mode {
        case cachedOnly
        case includeRemoteIfAvailable

        var manifestMode: String {
            switch self {
            case .cachedOnly: return "cached_only"
            case .includeRemoteIfAvailable: return "cache_plus_remote"
            }
        }
    }

    struct Manifest: Codable {
        let schemaVersion: Int
        let exportedAt: Date
        let conversationId: String
        let mode: String
        let entries: [Entry]

        struct Entry: Codable {
            let messageId: String
            let cacheKey: String
            let provider: String?
            let voiceId: String?
            let voiceName: String?
            let format: String
            let relativePath: String
            let source: String // "cache" | "remote"
        }
    }

    private struct AudioCandidate: Hashable {
        let messageId: String
        let cacheKey: String
        let format: String
    }

    func buildZip(conversationId: String, messages: [Message], mode: Mode) async throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("AxonExports", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        let exportFolder = base.appendingPathComponent("session-audio_\(conversationId)_\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        if fm.fileExists(atPath: exportFolder.path) {
            try? fm.removeItem(at: exportFolder)
        }
        try fm.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        let audioFolder = exportFolder.appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: audioFolder, withIntermediateDirectories: true)

        // Candidate cache keys: messageId-only + 4 combinations for toggles used in key.
        // This is a best-effort enumeration; the true key is deterministic but depends on per-generation settings.
        let candidates = enumerateCandidates(messages: messages)

        var manifestEntries: [Manifest.Entry] = []

        for candidate in candidates {
            if let localURL = findLocalAudioURL(cacheKey: candidate.cacheKey, format: candidate.format) {
                let rel = "audio/\(candidate.cacheKey).\(candidate.format)"
                try copyIfNeeded(from: localURL, to: exportFolder.appendingPathComponent(rel))

                manifestEntries.append(.init(
                    messageId: candidate.messageId,
                    cacheKey: candidate.cacheKey,
                    provider: nil,
                    voiceId: nil,
                    voiceName: nil,
                    format: candidate.format,
                    relativePath: rel,
                    source: "cache"
                ))
                continue
            }

            guard mode == .includeRemoteIfAvailable else { continue }

            // If remote audio exists, fetch and write to disk inside export.
            if await AudioSyncService.shared.hasRemoteAudio(for: candidate.cacheKey) {
                if let data = try await AudioSyncService.shared.fetchRemoteAudio(for: candidate.cacheKey) {
                    let rel = "audio/\(candidate.cacheKey).\(candidate.format)"
                    let dest = exportFolder.appendingPathComponent(rel)
                    try data.write(to: dest, options: .atomic)

                    manifestEntries.append(.init(
                        messageId: candidate.messageId,
                        cacheKey: candidate.cacheKey,
                        provider: nil,
                        voiceId: nil,
                        voiceName: nil,
                        format: candidate.format,
                        relativePath: rel,
                        source: "remote"
                    ))
                }
            }
        }

        let manifest = Manifest(
            schemaVersion: 1,
            exportedAt: Date(),
            conversationId: conversationId,
            mode: mode.manifestMode,
            entries: manifestEntries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: exportFolder.appendingPathComponent("manifest.json"), options: .atomic)

        // Zip it
        let zipURL = exportFolder.deletingLastPathComponent().appendingPathComponent("session-audio_\(conversationId)_\(Int(manifest.exportedAt.timeIntervalSince1970)).zip")
        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }

        #if os(macOS)
        try runZipCommand(folderURL: exportFolder, outputZipURL: zipURL)
        #else
        // iOS: we don’t have a guaranteed zip tool. For now, export the manifest as a stand-in.
        // (Future improvement: add pure-Swift ZIP writer.)
        try manifestData.write(to: zipURL, options: .atomic)
        #endif

        return zipURL
    }

    // MARK: - Candidate enumeration

    private func enumerateCandidates(messages: [Message]) -> [AudioCandidate] {
        var set = Set<AudioCandidate>()

        let togglePairs: [(strip: Bool, friendly: Bool)] = [
            (false, false),
            (true, false),
            (false, true),
            (true, true)
        ]

        for message in messages {
            let messageId = message.id

            // Legacy key
            for format in ["mp3", "wav", "m4a"] {
                set.insert(.init(messageId: messageId, cacheKey: messageId, format: format))
            }

            // New key structure
            for pair in togglePairs {
                let key = "\(messageId)_md\(pair.strip ? "1" : "0")_sf\(pair.friendly ? "1" : "0")"
                for format in ["mp3", "wav", "m4a"] {
                    set.insert(.init(messageId: messageId, cacheKey: key, format: format))
                }
            }
        }

        // Deterministic ordering for stable exports
        return set.sorted { a, b in
            if a.messageId != b.messageId { return a.messageId < b.messageId }
            if a.cacheKey != b.cacheKey { return a.cacheKey < b.cacheKey }
            return a.format < b.format
        }
    }

    // MARK: - Local AudioCache

    private func documentsAudioCacheDirectory() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("AudioCache", isDirectory: true)
    }

    private func findLocalAudioURL(cacheKey: String, format: String) -> URL? {
        let url = documentsAudioCacheDirectory().appendingPathComponent("\(cacheKey).\(format)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func copyIfNeeded(from: URL, to: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: to.path) {
            return
        }
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: from, to: to)
    }

    #if os(macOS)
    private func runZipCommand(folderURL: URL, outputZipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = folderURL.deletingLastPathComponent()

        process.arguments = [
            "-r",
            outputZipURL.path,
            folderURL.lastPathComponent
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "zip failed"
            throw NSError(domain: "SessionAudioZipExporter", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
    #endif
}
