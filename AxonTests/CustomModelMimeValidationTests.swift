import XCTest
@testable import Axon

final class CustomModelMimeValidationTests: XCTestCase {

    func testValidPatternsPassValidation() {
        let patterns = ["image/*", "application/pdf", "audio/mpeg"]
        XCTAssertTrue(AttachmentMimePolicyService.invalidMimePatterns(patterns).isEmpty)
    }

    func testInvalidPatternsAreDetected() {
        let patterns = ["image", "application", "*/json", "nope"]
        let invalid = AttachmentMimePolicyService.invalidMimePatterns(patterns)
        XCTAssertEqual(invalid.count, 4)
    }

    func testLegacyCustomModelDecodeWithoutMimeField() throws {
        let json = """
        {
          "id": "7C3A6AA4-2F18-47EB-8E27-F95B7F3AAB10",
          "modelCode": "legacy-model",
          "contextWindow": 128000,
          "friendlyName": "Legacy"
        }
        """

        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(CustomModelConfig.self, from: data)
        XCTAssertNil(decoded.acceptedAttachmentMimeTypes)
    }
}
