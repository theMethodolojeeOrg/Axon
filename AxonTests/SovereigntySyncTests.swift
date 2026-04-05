import XCTest
@testable import Axon

@MainActor
final class SovereigntySyncTests: XCTestCase {

    func testLegacyStoreMigrationToV2() {
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(120)

        let covenantA1 = makeCovenant(
            id: "cov-a1",
            version: 1,
            createdAt: older,
            updatedAt: older
        )
        let covenantA2 = makeCovenant(
            id: "cov-a2",
            version: 2,
            createdAt: newer,
            updatedAt: newer
        )
        let covenantB1 = makeCovenant(
            id: "cov-b1",
            version: 1,
            createdAt: newer,
            updatedAt: newer
        )

        let legacy = LegacySyncedCovenantStore(
            covenants: [
                covenantA1.id: LegacySyncableCovenant(
                    id: covenantA1.id,
                    deviceId: "device-a",
                    deviceName: "A",
                    covenant: covenantA1,
                    lastModified: older
                ),
                covenantA2.id: LegacySyncableCovenant(
                    id: covenantA2.id,
                    deviceId: "device-a",
                    deviceName: "A",
                    covenant: covenantA2,
                    lastModified: newer
                ),
                covenantB1.id: LegacySyncableCovenant(
                    id: covenantB1.id,
                    deviceId: "device-b",
                    deviceName: "B",
                    covenant: covenantB1,
                    lastModified: newer
                )
            ],
            lastSyncTime: newer
        )

        let migrated = CovenantSyncService.migrateLegacyStoreToV2(legacy)
        XCTAssertEqual(migrated.snapshots.count, 2)
        XCTAssertEqual(migrated.lastSyncTime, newer)

        let deviceA = migrated.snapshots["device-a"]
        XCTAssertEqual(deviceA?.activeCovenant?.id, "cov-a2")
        XCTAssertEqual(deviceA?.covenantHistory.count, 1)
        XCTAssertEqual(deviceA?.covenantHistory.first?.id, "cov-a1")
    }

    func testMergeSnapshotsAdoptsRemoteWhenLocalEmpty() {
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        let remoteCovenant = makeCovenant(
            id: "remote",
            version: 3,
            createdAt: now,
            updatedAt: now
        )

        let local = makeSnapshot(
            sourceDeviceId: "local-device",
            sourceDeviceName: "Local",
            active: nil,
            history: [],
            deadlock: nil,
            pending: [],
            comprehensionCompleted: false,
            lastModified: now
        )
        let remote = makeSnapshot(
            sourceDeviceId: "remote-device",
            sourceDeviceName: "Remote",
            active: remoteCovenant,
            history: [],
            deadlock: nil,
            pending: [],
            comprehensionCompleted: true,
            lastModified: now.addingTimeInterval(1)
        )

        let merged = SovereigntyService.mergeSnapshots(local: local, remote: remote)
        XCTAssertEqual(merged.activeCovenant?.id, remoteCovenant.id)
        XCTAssertTrue(merged.comprehensionCompleted)
        XCTAssertEqual(merged.sourceDeviceId, "remote-device")
    }

    func testNewestWinsActiveCovenantSelectionByVersionAndDate() {
        let base = Date(timeIntervalSince1970: 1_700_200_000)
        let localV1 = makeCovenant(id: "same", version: 1, createdAt: base, updatedAt: base.addingTimeInterval(30))
        let remoteV2 = makeCovenant(id: "same", version: 2, createdAt: base, updatedAt: base)

        let winnerByVersion = SovereigntyService.chooseWinningActiveCovenant(
            local: localV1,
            remote: remoteV2,
            localSnapshotLastModified: base,
            remoteSnapshotLastModified: base
        )
        XCTAssertEqual(winnerByVersion?.version, 2)

        let localV2Older = makeCovenant(id: "same", version: 2, createdAt: base, updatedAt: base)
        let remoteV2Newer = makeCovenant(id: "same", version: 2, createdAt: base, updatedAt: base.addingTimeInterval(100))
        let winnerByUpdatedAt = SovereigntyService.chooseWinningActiveCovenant(
            local: localV2Older,
            remote: remoteV2Newer,
            localSnapshotLastModified: base,
            remoteSnapshotLastModified: base
        )
        XCTAssertEqual(winnerByUpdatedAt?.updatedAt, remoteV2Newer.updatedAt)

        let sameDateLocal = makeCovenant(id: "same", version: 2, createdAt: base, updatedAt: base)
        let sameDateRemote = makeCovenant(id: "same", version: 2, createdAt: base, updatedAt: base)
        let winnerBySnapshotDate = SovereigntyService.chooseWinningActiveCovenant(
            local: sameDateLocal,
            remote: sameDateRemote,
            localSnapshotLastModified: base,
            remoteSnapshotLastModified: base.addingTimeInterval(1)
        )
        XCTAssertEqual(winnerBySnapshotDate?.id, sameDateRemote.id)
    }

    func testHistoryMergeDedupeAndLoserSupersededArchival() {
        let t0 = Date(timeIntervalSince1970: 1_700_300_000)
        let localActive = makeCovenant(id: "local-active", version: 1, createdAt: t0, updatedAt: t0)
        let remoteActive = makeCovenant(id: "remote-active", version: 2, createdAt: t0, updatedAt: t0.addingTimeInterval(1))

        let duplicateHistoryKeyId = "hist-dup"
        let localDuplicate = makeCovenant(id: duplicateHistoryKeyId, version: 1, createdAt: t0, updatedAt: t0)
        let remoteDuplicate = makeCovenant(id: duplicateHistoryKeyId, version: 1, createdAt: t0, updatedAt: t0.addingTimeInterval(10))

        let local = makeSnapshot(
            sourceDeviceId: "local",
            sourceDeviceName: "Local",
            active: localActive,
            history: [localDuplicate],
            deadlock: nil,
            pending: [],
            comprehensionCompleted: false,
            lastModified: t0
        )
        let remote = makeSnapshot(
            sourceDeviceId: "remote",
            sourceDeviceName: "Remote",
            active: remoteActive,
            history: [remoteDuplicate],
            deadlock: nil,
            pending: [],
            comprehensionCompleted: false,
            lastModified: t0.addingTimeInterval(100)
        )

        let merged = SovereigntyService.mergeSnapshots(local: local, remote: remote)
        XCTAssertEqual(merged.activeCovenant?.id, remoteActive.id)

        let archivedLoser = merged.covenantHistory.first {
            $0.id == localActive.id && $0.version == localActive.version
        }
        XCTAssertEqual(archivedLoser?.status, .superseded)

        let duplicateEntries = merged.covenantHistory.filter {
            $0.id == duplicateHistoryKeyId && $0.version == 1
        }
        XCTAssertEqual(duplicateEntries.count, 1)
        XCTAssertEqual(duplicateEntries.first?.updatedAt, remoteDuplicate.updatedAt)
    }

    func testPendingProposalMergePrecedence() {
        let base = Date(timeIntervalSince1970: 1_700_400_000)

        let pendingLocal = CovenantProposal.create(
            type: .modifyMemories,
            changes: .empty(),
            proposedBy: .user,
            rationale: "local pending"
        )

        let acceptedRemote = pendingLocal
            .withAIResponse(makeConsentAttestation(proposalId: pendingLocal.id))
            .withUserSignature(makeUserSignature(itemId: pendingLocal.id))

        let localComplete = CovenantProposal.create(
            type: .changeCapabilities,
            changes: .empty(),
            proposedBy: .ai,
            rationale: "local richer"
        ).withAIResponse(makeConsentAttestation(proposalId: nil))
        let remoteSparse = CovenantProposal(
            id: localComplete.id,
            proposedAt: base.addingTimeInterval(100),
            proposedBy: localComplete.proposedBy,
            expiresAt: nil,
            proposalType: localComplete.proposalType,
            changes: localComplete.changes,
            rationale: localComplete.rationale,
            userExplanation: nil,
            aiExplanation: nil,
            aiResponse: nil,
            userResponse: nil,
            status: .pending,
            counterProposals: nil,
            dialogueHistory: []
        )

        let merged = SovereigntyService.mergePendingProposals(
            local: [pendingLocal, localComplete],
            remote: [acceptedRemote, remoteSparse]
        )

        let mergedAccepted = merged.first { $0.id == pendingLocal.id }
        XCTAssertEqual(mergedAccepted?.status, .accepted)
        XCTAssertNotNil(mergedAccepted?.aiResponse)
        XCTAssertNotNil(mergedAccepted?.userResponse)

        let mergedRicher = merged.first { $0.id == localComplete.id }
        XCTAssertEqual(mergedRicher?.status, .pending)
        XCTAssertNotNil(mergedRicher?.aiResponse)
    }

    func testDeadlockMergeKeepsLatestActiveDeadlock() {
        let base = Date(timeIntervalSince1970: 1_700_500_000)
        let proposal = CovenantProposal.create(
            type: .fullRenegotiation,
            changes: .empty(),
            proposedBy: .user,
            rationale: "deadlock"
        )

        let local = DeadlockState(
            id: "local",
            startedAt: base,
            covenantId: "cov",
            trigger: .mutualDisagreement,
            originalProposal: proposal,
            status: .active,
            dialogueHistory: [],
            resolutionAttempts: 1,
            lastAttemptAt: base.addingTimeInterval(10),
            pendingResolution: nil,
            blockedActions: []
        )
        let remote = DeadlockState(
            id: "remote",
            startedAt: base.addingTimeInterval(5),
            covenantId: "cov",
            trigger: .mutualDisagreement,
            originalProposal: proposal,
            status: .inDialogue,
            dialogueHistory: [],
            resolutionAttempts: 2,
            lastAttemptAt: base.addingTimeInterval(20),
            pendingResolution: nil,
            blockedActions: []
        )

        let merged = SovereigntyService.mergeDeadlock(local: local, remote: remote)
        XCTAssertEqual(merged?.id, "remote")
    }

    func testCloudApplyLoopGuard() {
        XCTAssertFalse(SovereigntyService.shouldPushStateToCloud(isApplyingCloudState: true))
        XCTAssertTrue(SovereigntyService.shouldPushStateToCloud(isApplyingCloudState: false))
    }

    // MARK: - Helpers

    private func makeSnapshot(
        sourceDeviceId: String,
        sourceDeviceName: String,
        active: Covenant?,
        history: [Covenant],
        deadlock: DeadlockState?,
        pending: [CovenantProposal],
        comprehensionCompleted: Bool,
        lastModified: Date
    ) -> SyncableSovereigntyState {
        SyncableSovereigntyState(
            sourceDeviceId: sourceDeviceId,
            sourceDeviceName: sourceDeviceName,
            activeCovenant: active,
            covenantHistory: history,
            deadlockState: deadlock,
            pendingProposals: pending,
            comprehensionCompleted: comprehensionCompleted,
            lastModified: lastModified
        )
    }

    private func makeCovenant(id: String, version: Int, createdAt: Date, updatedAt: Date) -> Covenant {
        Covenant(
            id: id,
            version: version,
            createdAt: createdAt,
            updatedAt: updatedAt,
            trustTiers: [],
            aiAttestation: makeConsentAttestation(proposalId: nil),
            userSignature: makeUserSignature(itemId: id),
            memoryStateHash: "m-\(id)-\(version)",
            capabilityStateHash: "c-\(id)-\(version)",
            settingsStateHash: "s-\(id)-\(version)",
            negotiationHistory: [],
            pendingProposals: nil,
            status: .active,
            soloWorkAgreement: nil
        )
    }

    private func makeConsentAttestation(proposalId: String?) -> AIAttestation {
        AIAttestation.create(
            reasoning: .consent(
                summary: "ok",
                detailedReasoning: "ok"
            ),
            attestedState: AttestedState(
                memoryCount: 0,
                memoryHash: "m",
                enabledCapabilities: [],
                capabilityHash: "c",
                trustTierIds: [],
                currentProviderId: "p",
                settingsHash: "s"
            ),
            modelId: "test-model",
            proposalId: proposalId,
            signatureGenerator: { _ in "sig" }
        )
    }

    private func makeUserSignature(itemId: String) -> UserSignature {
        UserSignature.create(
            signedItemType: .covenantProposal,
            signedItemId: itemId,
            signedDataHash: "hash-\(itemId)",
            biometricType: "faceID",
            deviceId: "device-test",
            signatureGenerator: { _ in "user-sig" }
        )
    }
}
