import XCTest
@testable import Axon

@MainActor
final class VSCodeBridgeRoutingAndDebugTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ToolsV2Toggle.shared.forceV2ForTesting()
    }

    func testLegacyVscodeListFilesAliasResolvesToListDirectory() async {
        await ToolPluginLoader.shared.loadAllTools()

        let resolved = ToolRoutingService.shared.resolveToolIdForTesting("vscode_list_files")
        XCTAssertEqual(resolved, "vscode_list_directory")
    }

    func testExactVscodeReadFileIdIsNotRemapped() async {
        await ToolPluginLoader.shared.loadAllTools()

        let resolved = ToolRoutingService.shared.resolveToolIdForTesting("vscode_read_file")
        XCTAssertEqual(resolved, "vscode_read_file")
    }

    func testDebugBridgeInternalHandlerReturnsDiagnosticsWithoutBridgeMethod() async throws {
        let handler = BridgeHandler()
        let result = try await handler.executeV2(
            inputs: [:],
            manifest: try debugBridgeManifest(),
            context: .empty
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("VS Code Bridge Status"))
        XCTAssertFalse(result.output.contains("Tool missing bridge method configuration"))
    }

    func testVscodeReadFileRequiresConnectedBridgeInStrictMode() async throws {
        await BridgeConnectionManager.shared.stop()

        let handler = BridgeHandler()
        let result = try await handler.executeV2(
            inputs: ["path": "Axon/Info.plist"],
            manifest: try vscodeReadFileManifest(),
            context: .empty
        )

        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("VS Code bridge not connected"))
    }

    private func debugBridgeManifest() throws -> ToolManifest {
        let json = """
        {
          "version": "1.0.0",
          "tool": {
            "id": "debug_bridge",
            "name": "Debug Bridge",
            "description": "Debug the bridge connection and communication status.",
            "category": "system",
            "requiresApproval": false
          },
          "execution": {
            "type": "internal_handler",
            "handler": "bridge"
          }
        }
        """
        return try JSONDecoder().decode(ToolManifest.self, from: Data(json.utf8))
    }

    private func vscodeReadFileManifest() throws -> ToolManifest {
        let json = """
        {
          "version": "1.0.0",
          "tool": {
            "id": "vscode_read_file",
            "name": "VS Code Read File",
            "description": "Read file contents from VS Code workspace.",
            "category": "vscode",
            "requiresApproval": false
          },
          "parameters": {
            "path": {
              "type": "string",
              "required": true
            }
          },
          "execution": {
            "type": "bridge",
            "bridgeMethod": "file/read",
            "bridgeTarget": "vscode"
          }
        }
        """
        return try JSONDecoder().decode(ToolManifest.self, from: Data(json.utf8))
    }
}
