import XCTest
@testable import Axon
import AxonArtifacts

final class ArtifactWorkspaceTests: XCTestCase {
    func testCreativeItemWorkspaceFieldsCodableRoundTrip() throws {
        let workspace = ArtifactWorkspace(
            id: "ws",
            title: "WS",
            files: [ArtifactWorkspaceFile(path: "index.html", content: "<html></html>")],
            isEditableFork: true,
            isReadOnlySnapshot: false
        )
        let workspaceData = try JSONEncoder().encode(workspace)
        let workspaceJSON = String(data: workspaceData, encoding: .utf8)

        let item = CreativeItem(
            id: "artifact_1",
            type: .artifact,
            conversationId: "c1",
            messageId: "m1",
            mimeType: "application/json",
            title: "Code Workspace",
            language: "workspace",
            artifactBundleJSON: workspaceJSON,
            artifactEntryPath: "index.html",
            sourceItemId: "source_1",
            isEditableFork: true
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(CreativeItem.self, from: data)
        XCTAssertEqual(decoded.artifactEntryPath, "index.html")
        XCTAssertEqual(decoded.sourceItemId, "source_1")
        XCTAssertTrue(decoded.isEditableFork)
        XCTAssertNotNil(decoded.artifactWorkspace)
    }

    @MainActor
    func testCreateEditableForkWorkspace() {
        let snapshot = ArtifactWorkspace(
            id: "snapshot_ws",
            title: "Snapshot",
            files: [ArtifactWorkspaceFile(path: "index.html", content: "<html></html>")],
            conversationId: "c1",
            messageId: "m1",
            sourceItemId: "m1_bundle",
            isEditableFork: false,
            isReadOnlySnapshot: true
        )

        let fork = CreativeGalleryService.shared.createEditableForkWorkspace(from: snapshot)
        XCTAssertNotNil(fork)
        XCTAssertTrue(fork?.isEditableFork == true)
        XCTAssertTrue(fork?.isReadOnlySnapshot == false)
        XCTAssertEqual(fork?.sourceItemId, "m1_bundle")
    }
}
