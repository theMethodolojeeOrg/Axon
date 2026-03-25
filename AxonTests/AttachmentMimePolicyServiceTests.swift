import XCTest
@testable import Axon

final class AttachmentMimePolicyServiceTests: XCTestCase {

    func testExactMatchAcceptance() {
        let policy = AttachmentMimePolicy(
            provider: "test",
            modelId: "m1",
            providerName: "Test",
            allowedPatternsByType: [
                .image: [],
                .document: ["application/pdf"],
                .audio: [],
                .video: []
            ]
        )

        let attachment = MessageAttachment(
            type: .document,
            base64: "ZmFrZQ==",
            name: "file.pdf",
            mimeType: "application/pdf"
        )

        let result = AttachmentMimePolicyService.validate(attachments: [attachment], policy: policy)
        XCTAssertEqual(result, .accepted)
    }

    func testWildcardAcceptance() {
        let policy = AttachmentMimePolicy(
            provider: "test",
            modelId: "m2",
            providerName: "Test",
            allowedPatternsByType: [
                .image: ["image/*"],
                .document: [],
                .audio: [],
                .video: []
            ]
        )

        let attachment = MessageAttachment(
            type: .image,
            base64: "ZmFrZQ==",
            name: "file.webp",
            mimeType: "image/webp"
        )

        let result = AttachmentMimePolicyService.validate(attachments: [attachment], policy: policy)
        XCTAssertEqual(result, .accepted)
    }

    func testAliasNormalizationForAudioMp3() {
        XCTAssertTrue(
            AttachmentMimePolicyService.isMimeAllowed(
                mime: "audio/mp3",
                patterns: ["audio/mpeg"]
            )
        )
    }

    func testProviderResolutionGrokRejectsWebP() {
        var settings = AppSettings()
        settings.defaultProvider = .xai
        settings.defaultModel = "grok-4-fast-reasoning"

        let policy = AttachmentMimePolicyService.resolvePolicy(conversationId: nil, settings: settings)
        XCTAssertFalse(
            AttachmentMimePolicyService.isMimeAllowed(
                mime: "image/webp",
                patterns: policy.patterns(for: .image)
            )
        )
    }

    func testProviderResolutionOpenAINon4oRejectsAudio() {
        var settings = AppSettings()
        settings.defaultProvider = .openai
        settings.defaultModel = "gpt-5.2"

        let policy = AttachmentMimePolicyService.resolvePolicy(conversationId: nil, settings: settings)
        XCTAssertTrue(policy.patterns(for: .audio).isEmpty)
    }

    func testOpenAICompatibleConfiguredDocumentMimeIsFilteredByTransportParity() {
        let providerId = UUID()
        let modelId = UUID()

        var settings = AppSettings()
        settings.selectedCustomProviderId = providerId
        settings.selectedCustomModelId = modelId
        settings.customProviders = [
            CustomProviderConfig(
                id: providerId,
                providerName: "Custom",
                apiEndpoint: "https://example.com/v1",
                models: [
                    CustomModelConfig(
                        id: modelId,
                        modelCode: "model-with-audio-signature",
                        acceptedAttachmentMimeTypes: ["application/pdf", "image/*"]
                    )
                ]
            )
        ]

        let policy = AttachmentMimePolicyService.resolvePolicy(conversationId: nil, settings: settings)
        XCTAssertEqual(policy.patterns(for: .image), ["image/*"])
        XCTAssertTrue(policy.patterns(for: .document).isEmpty)
        XCTAssertTrue(policy.patterns(for: .audio).isEmpty)
        XCTAssertTrue(policy.patterns(for: .video).isEmpty)
    }

    func testResolvePolicyForEffectiveProviderSupportsRuntimeOverrideAlignment() {
        var settings = AppSettings()
        settings.defaultProvider = .anthropic
        settings.defaultModel = "claude-sonnet-4-5-20250929"

        let policy = AttachmentMimePolicyService.resolvePolicy(
            provider: "openai",
            modelId: "gpt-5.2",
            providerName: "OpenAI (GPT)",
            conversationId: nil,
            settings: settings
        )

        XCTAssertEqual(policy.provider, "openai")
        XCTAssertTrue(policy.patterns(for: .document).isEmpty)
        XCTAssertTrue(policy.patterns(for: .video).isEmpty)
        XCTAssertEqual(policy.patterns(for: .image), ["image/*"])
    }
}
