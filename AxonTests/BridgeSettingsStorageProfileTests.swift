import XCTest
@testable import Axon

@MainActor
final class BridgeSettingsStorageProfileTests: XCTestCase {
    private var originalSettings: BridgeSettings!

    override func setUp() {
        super.setUp()
        originalSettings = BridgeSettingsStorage.shared.settings
        BridgeSettingsStorage.shared.settings = BridgeSettings()
    }

    override func tearDown() {
        BridgeSettingsStorage.shared.settings = originalSettings
        super.tearDown()
    }

    func testCreateAndSetDefaultProfile() {
        let storage = BridgeSettingsStorage.shared

        let profile = storage.createConnectionProfile(
            name: "Office",
            host: "10.0.0.5",
            port: 8082,
            tlsEnabled: false
        )

        storage.setDefaultConnectionProfile(profile.id)

        XCTAssertEqual(storage.settings.connectionProfiles.count, 1)
        XCTAssertEqual(storage.settings.defaultConnectionProfileId, profile.id)
        XCTAssertEqual(storage.defaultConnectionProfile()?.host, "10.0.0.5")
    }

    func testApplyProfileToActiveRemoteConfig() {
        let storage = BridgeSettingsStorage.shared
        let profile = storage.createConnectionProfile(
            name: "Laptop",
            host: "192.168.0.4",
            port: 9443,
            tlsEnabled: true
        )

        let applied = storage.applyConnectionProfileToActiveRemoteConfig(profileId: profile.id)

        XCTAssertEqual(applied?.id, profile.id)
        XCTAssertEqual(storage.settings.remoteHost, "192.168.0.4")
        XCTAssertEqual(storage.settings.remotePort, 9443)
        XCTAssertTrue(storage.settings.tlsEnabled)
    }

    func testMarkConnectedAndDeleteClearsReferences() {
        let storage = BridgeSettingsStorage.shared
        let profile = storage.createConnectionProfile(
            name: "Home",
            host: "192.168.1.2",
            port: 8082,
            tlsEnabled: false
        )

        storage.setDefaultConnectionProfile(profile.id)
        storage.markConnectedProfile(profile.id)

        XCTAssertEqual(storage.settings.lastConnectedProfileId, profile.id)
        XCTAssertNotNil(storage.connectionProfile(id: profile.id)?.lastConnectedAt)

        storage.deleteConnectionProfile(id: profile.id)

        XCTAssertNil(storage.settings.defaultConnectionProfileId)
        XCTAssertNil(storage.settings.lastConnectedProfileId)
        XCTAssertTrue(storage.settings.connectionProfiles.isEmpty)
    }
}
