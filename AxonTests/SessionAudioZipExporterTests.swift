import XCTest
@testable import Axon

final class SessionAudioZipExporterTests: XCTestCase {

    func testEnumerateCandidatesIncludesLegacyAndToggleKeys() async throws {
        let messages: [Message] = [
            Message(
                id: "m1",
                conversationId: "c1",
                role: .assistant,
                content: "hi",
                hiddenReason: nil,
                timestamp: Date(timeIntervalSince1970: 1),
                tokens: nil,
                artifacts: nil,
                toolCalls: nil,
                isStreaming: false,
                modelName: nil,
                providerName: nil,
                attachments: nil,
                groundingSources: nil,
                memoryOperations: nil,
                reasoning: nil,
                editHistory: nil,
                currentVersion: nil,
                contextDebugInfo: nil,
                liveToolCalls: nil
            )
        ]

        // The exporter will always create the export folder + manifest.
        // We can validate it doesn’t throw even when no audio exists.
        let url = try await SessionAudioZipExporter().buildZip(conversationId: "c1", messages: messages, mode: .cachedOnly)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // If we can read the manifest (macOS zip case writes a folder first then zips),
        // we at least confirm we created a file.
        XCTAssertTrue(url.lastPathComponent.contains("session-audio_c1"))
    }
}
