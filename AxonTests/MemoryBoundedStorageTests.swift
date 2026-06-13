import AVFoundation
import XCTest
@testable import Axon

final class MemoryBoundedStorageTests: XCTestCase {

    func testLiveRecordingStoreWritesAudioToFilesAndKeepsRecordingJSONSmall() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("LiveRecordingAudioStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let store = LiveRecordingAudioStore(fileManager: fileManager, rootDirectory: root)
        let sessionId = "session-\(UUID().uuidString)"
        store.startSession(id: sessionId)

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1))
        for index in 0..<500 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
            buffer.frameLength = 1_024
            if let samples = buffer.floatChannelData?[0] {
                samples[0] = Float(index)
            }
            store.appendUserAudio(buffer: buffer)
        }

        let audioURL = try XCTUnwrap(store.finishUserTurn())
        store.endSession()

        let fileSize = try XCTUnwrap(audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertGreaterThan(fileSize, 1_000_000)

        let turn = LiveSessionTurn(
            role: .user,
            transcript: "A long recorded turn",
            audioData: nil,
            audioFileURL: audioURL
        )
        let recording = LiveSessionRecording(
            id: sessionId,
            provider: "test",
            modelId: "test-model",
            voice: "test-voice",
            turns: [turn],
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 1_201),
            totalDurationMs: 20 * 60 * 1_000
        )

        let encoded = try JSONEncoder().encode(recording)
        XCTAssertLessThan(encoded.count, 16 * 1_024)
        XCTAssertNil(recording.turns.first?.audioData)
        XCTAssertEqual(recording.turns.first?.audioFileURL, audioURL)
    }

    func testLocalAttachmentInlinePayloadReadsFileAndHonorsSizeCap() throws {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("MessageAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: folder) }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileURL = folder.appendingPathComponent("image.jpg")
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        try bytes.write(to: fileURL)

        let attachment = MessageAttachment(
            type: .image,
            url: fileURL.absoluteString,
            base64: nil,
            name: "image.jpg",
            mimeType: "image/jpeg"
        )

        XCTAssertEqual(try attachment.inlineData(), bytes)
        XCTAssertEqual(try attachment.inlineBase64(), bytes.base64EncodedString())
        XCTAssertNil(attachment.remoteURLString)
        XCTAssertEqual(attachment.localFileURL, fileURL)

        XCTAssertThrowsError(try attachment.inlineData(maxBytes: bytes.count - 1)) { error in
            XCTAssertEqual(error as? AttachmentInlinePayloadError, .exceedsLimit)
        }
    }
}
