import XCTest
@testable import Axon

@MainActor
final class TTSPlaybackServiceExportTests: XCTestCase {
    private let service = TTSPlaybackService.shared

    override func setUp() {
        super.setUp()
        service.resetAudioExportTesting()
    }

    override func tearDown() {
        service.resetAudioExportTesting()
        super.tearDown()
    }

    func testCurrentPlaybackExportReturnsExactActiveAudio() {
        let messageId = uniqueMessageId()
        let audioData = Data([0x52, 0x49, 0x46, 0x46, 0x01, 0x02, 0x03, 0x04])

        service.setCurrentAudioForExportTesting(
            messageId: messageId,
            data: audioData,
            format: .wav
        )

        let exported = service.getCurrentAudioForExport()

        XCTAssertEqual(exported?.data, audioData)
        XCTAssertEqual(exported?.format, .wav)
        XCTAssertEqual(exported?.suggestedFilename.hasSuffix(".wav"), true)
    }

    func testSettingsKeyedCachedAudioCanBeExported() {
        let messageId = uniqueMessageId()
        let audioData = Data([0x49, 0x44, 0x33, 0x01, 0x02, 0x03])
        var settings = AppSettings()
        settings.ttsSettings.stripMarkdownBeforeTTS = true
        settings.ttsSettings.spokenFriendlyTTS = false

        service.cacheAudioForExportTesting(
            audioData,
            messageId: messageId,
            format: .mp3,
            settings: settings
        )
        defer { cleanupAudioFile(cacheKey: "\(messageId)_md1_sf0", format: .mp3) }

        let exported = service.getCurrentAudioForExport()

        XCTAssertEqual(exported?.data, audioData)
        XCTAssertEqual(exported?.format, .mp3)
        XCTAssertEqual(exported?.suggestedFilename.hasSuffix(".mp3"), true)
    }

    func testCAFFileOnDiskCanBeExported() throws {
        let messageId = uniqueMessageId()
        let cacheKey = "\(messageId)_md0_sf1"
        let audioData = Data([0x63, 0x61, 0x66, 0x66, 0x01, 0x02, 0x03])

        try writeAudioFile(data: audioData, cacheKey: cacheKey, format: .caf)
        defer { cleanupAudioFile(cacheKey: cacheKey, format: .caf) }

        service.setCurrentMessageIdForExportTesting(messageId)

        let exported = service.getCurrentAudioForExport()

        XCTAssertEqual(exported?.data, audioData)
        XCTAssertEqual(exported?.format, .caf)
        XCTAssertEqual(exported?.suggestedFilename.hasSuffix(".caf"), true)
    }

    func testClearingMemoryCacheKeepsDiskBackedAudioExportAvailable() {
        let messageId = uniqueMessageId()
        let audioData = Data([0x49, 0x44, 0x33, 0x09, 0x08, 0x07])

        service.cacheAudioForExportTesting(
            audioData,
            messageId: messageId,
            format: .mp3,
            settings: nil
        )
        defer { cleanupAudioFile(cacheKey: messageId, format: .mp3) }

        service.clearMemoryCache()
        service.setCurrentMessageIdForExportTesting(messageId)

        let exported = service.getCurrentAudioForExport()

        XCTAssertEqual(exported?.data, audioData)
        XCTAssertEqual(exported?.format, .mp3)
        XCTAssertEqual(exported?.suggestedFilename.hasSuffix(".mp3"), true)
    }

    private func uniqueMessageId() -> String {
        "tts-export-\(UUID().uuidString)"
    }

    private func writeAudioFile(data: Data, cacheKey: String, format: TTSAudioFormat) throws {
        let url = audioFileURL(cacheKey: cacheKey, format: format)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func cleanupAudioFile(cacheKey: String, format: TTSAudioFormat) {
        try? FileManager.default.removeItem(at: audioFileURL(cacheKey: cacheKey, format: format))
    }

    private func audioFileURL(cacheKey: String, format: TTSAudioFormat) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioCache", isDirectory: true)
            .appendingPathComponent("\(cacheKey).\(format.rawValue)")
    }
}
