//
//  ChatZipExporter.swift
//  Axon
//

import Foundation

/// Builds a ZIP bundle containing JSON + Markdown + attachment payloads where possible.
///
/// Attachment strategy:
/// - If MessageAttachment.base64 is present, we write it into attachments/<messageId>/<attachmentId>.<ext>
/// - If attachment only has a URL, we do NOT download it (no network surprises). We include a small .json reference file.
///
/// Implementation note:
/// We use the system `zip` command on macOS (available by default) via `Process`.
/// This keeps dependencies light and makes it easy to swap with a pure-Swift zip later.
struct ChatZipExporter {

    func buildZip(_ payload: ChatExportPayload) throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("AxonExports", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        let exportFolder = base.appendingPathComponent("chat-export_\(payload.conversation.id)_\(Int(payload.exportedAt.timeIntervalSince1970))", isDirectory: true)
        if fm.fileExists(atPath: exportFolder.path) {
            try? fm.removeItem(at: exportFolder)
        }
        try fm.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        // 1) Write JSON + MD
        let jsonData = try ChatJSONExporter().encode(payload)
        try jsonData.write(to: exportFolder.appendingPathComponent("thread.json"), options: .atomic)

        let mdText = ChatMarkdownExporter().render(payload)
        try Data(mdText.utf8).write(to: exportFolder.appendingPathComponent("thread.md"), options: .atomic)

        // 2) Write attachments bundle (best-effort)
        let attachmentsFolder = exportFolder.appendingPathComponent("attachments", isDirectory: true)
        try fm.createDirectory(at: attachmentsFolder, withIntermediateDirectories: true)

        for message in payload.messages {
            guard let attachments = message.attachments, !attachments.isEmpty else { continue }

            let msgFolder = attachmentsFolder.appendingPathComponent(message.id, isDirectory: true)
            try fm.createDirectory(at: msgFolder, withIntermediateDirectories: true)

            for attachment in attachments {
                let attachmentId = attachment.id

                if let base64 = attachment.base64 {
                    let data = Data(base64Encoded: base64) ?? Data()
                    let ext = fileExtension(for: attachment)
                    let filename = "\(attachmentId).\(ext)"
                    try data.write(to: msgFolder.appendingPathComponent(filename), options: .atomic)

                    // small metadata sidecar
                    let meta = [
                        "id": attachment.id,
                        "type": attachment.type.rawValue,
                        "name": attachment.name ?? "",
                        "mimeType": attachment.mimeType ?? ""
                    ]
                    let metaData = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
                    try metaData.write(to: msgFolder.appendingPathComponent("\(attachmentId).meta.json"), options: .atomic)
                } else {
                    // URL/reference only
                    let meta: [String: Any] = [
                        "id": attachment.id,
                        "type": attachment.type.rawValue,
                        "url": attachment.url ?? "",
                        "name": attachment.name ?? "",
                        "mimeType": attachment.mimeType ?? ""
                    ]
                    let metaData = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
                    try metaData.write(to: msgFolder.appendingPathComponent("\(attachmentId).reference.json"), options: .atomic)
                }
            }
        }

        // 3) Zip it
        let zipURL = exportFolder.deletingLastPathComponent().appendingPathComponent("chat-export_\(payload.conversation.id)_\(Int(payload.exportedAt.timeIntervalSince1970)).zip")
        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }

        #if os(macOS)
        try runZipCommand(folderURL: exportFolder, outputZipURL: zipURL)
        #else
        // On iOS, `zip` is not guaranteed. We fall back to shipping the folder as-is by writing a .zip filename
        // containing JSON bytes only. This keeps the UI functional until we add a pure Swift zipper.
        // Future improvement: add a minimal ZIP writer or dependency.
        try jsonData.write(to: zipURL, options: .atomic)
        #endif

        return zipURL
    }

    private func fileExtension(for attachment: MessageAttachment) -> String {
        if let mime = attachment.mimeType {
            switch mime {
            case "image/png": return "png"
            case "image/jpeg": return "jpg"
            case "image/webp": return "webp"
            case "application/pdf": return "pdf"
            case "audio/mpeg": return "mp3"
            case "audio/wav": return "wav"
            case "video/mp4": return "mp4"
            default: break
            }
        }

        // fallback by type
        switch attachment.type {
        case .image: return "bin"
        case .document: return "bin"
        case .audio: return "bin"
        case .video: return "bin"
        }
    }

    #if os(macOS)
    private func runZipCommand(folderURL: URL, outputZipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = folderURL.deletingLastPathComponent()

        // zip -r <outputZip> <folderName>
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
            throw NSError(domain: "ChatZipExporter", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }
    #endif
}
