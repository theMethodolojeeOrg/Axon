//
//  CoreDataCloudKitStack.swift
//  Axon
//
//  Centralizes Core Data + optional CloudKit container creation.
//
//  Important:
//  - NSPersistentCloudKitContainer must be configured at store-load time.
//  - You cannot safely toggle CloudKit on/off for the same store *without* reloading stores.
//

import Foundation
import CoreData
import CloudKit

enum CoreDataCloudKitStack {

    /// Observes CloudKit sync events and logs them for diagnostics
    private static var syncEventObserver: NSObjectProtocol?

    /// The CloudKit container identifier - must match entitlements
    private static let cloudKitContainerIdentifier = "iCloud.NeurXAxon"

    static func makeContainer(inMemory: Bool = false, useCloudKit: Bool) -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "Axon")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        if let storeDescription = container.persistentStoreDescriptions.first {
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            if !useCloudKit {
                storeDescription.cloudKitContainerOptions = nil
                print("[CloudKit] ❌ CloudKit DISABLED by settings")
            } else {
                // Explicitly set the CloudKit container options
                // This ensures the correct container is used even if not auto-configured from the model
                if storeDescription.cloudKitContainerOptions == nil {
                    print("[CloudKit] ⚠️ No container options in store description - setting explicitly")
                    storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                        containerIdentifier: cloudKitContainerIdentifier
                    )
                }

                if let options = storeDescription.cloudKitContainerOptions {
                    print("[CloudKit] ✅ CloudKit ENABLED - Container: \(options.containerIdentifier)")

                    // Log the database scope being used
                    #if DEBUG
                    print("[CloudKit] 📊 Database scope: \(options.databaseScope == .private ? "Private" : options.databaseScope == .public ? "Public" : "Shared")")
                    #endif
                } else {
                    print("[CloudKit] ❌ CRITICAL: Failed to configure CloudKit container options!")
                }
            }
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("[CloudKit] 💥 Failed to load persistent store: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }

            print("[CloudKit] 📦 Store loaded: \(storeDescription.url?.lastPathComponent ?? "unknown")")
            if let cloudKitOptions = storeDescription.cloudKitContainerOptions {
                print("[CloudKit] 📦 CloudKit container: \(cloudKitOptions.containerIdentifier)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Set up CloudKit event monitoring if enabled
        if useCloudKit {
            setupCloudKitEventMonitoring(for: container)
            checkCloudKitAccountStatus()
        }

        return container
    }

    // MARK: - CloudKit Diagnostics

    private static func setupCloudKitEventMonitoring(for container: NSPersistentCloudKitContainer) {
        // Listen for remote change notifications
        syncEventObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { notification in
            print("[CloudKit] 🔄 Remote change notification received")
            if let storeUUID = notification.userInfo?[NSStoreUUIDKey] as? String {
                print("[CloudKit] 🔄 Store UUID: \(storeUUID)")
            }
            if let historyToken = notification.userInfo?[NSPersistentHistoryTokenKey] {
                print("[CloudKit] 🔄 History token updated: \(type(of: historyToken))")
            }
        }

        print("[CloudKit] 👀 Event monitoring enabled")
    }

    private static func checkCloudKitAccountStatus() {
        CKContainer(identifier: cloudKitContainerIdentifier).accountStatus { status, error in
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("[CloudKit] ✅ iCloud account: Available")
                    // Also check the specific container
                    checkContainerPermissions()
                case .noAccount:
                    print("[CloudKit] ❌ iCloud account: Not signed in")
                case .restricted:
                    print("[CloudKit] ⚠️ iCloud account: Restricted (parental controls/MDM)")
                case .couldNotDetermine:
                    print("[CloudKit] ❓ iCloud account: Could not determine status")
                    if let error = error {
                        print("[CloudKit] ❓ Error: \(error.localizedDescription)")
                    }
                case .temporarilyUnavailable:
                    print("[CloudKit] ⏳ iCloud account: Temporarily unavailable")
                @unknown default:
                    print("[CloudKit] ❓ iCloud account: Unknown status (\(status.rawValue))")
                }
            }
        }
    }

    private static func checkContainerPermissions() {
        // Use the specific container, not the default
        let container = CKContainer(identifier: cloudKitContainerIdentifier)
        print("[CloudKit] 🔍 Checking permissions for container: \(cloudKitContainerIdentifier)")

        // Check private database access
        container.privateCloudDatabase.fetchAllRecordZones { zones, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[CloudKit] ❌ Private DB access error: \(error.localizedDescription)")
                    if let ckError = error as? CKError {
                        print("[CloudKit] ❌ CKError code: \(ckError.code.rawValue) - \(ckError.code)")
                        diagnoseCloudKitError(ckError)
                    }
                } else if let zones = zones {
                    print("[CloudKit] ✅ Private DB accessible - \(zones.count) zone(s)")
                    for zone in zones {
                        print("[CloudKit]    📁 Zone: \(zone.zoneID.zoneName)")
                    }
                }
            }
        }

        // Check user identity for sync
        container.fetchUserRecordID { recordID, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[CloudKit] ❌ User record fetch error: \(error.localizedDescription)")
                } else if let recordID = recordID {
                    print("[CloudKit] ✅ User record ID: \(recordID.recordName)")
                }
            }
        }
    }

    private static func diagnoseCloudKitError(_ error: CKError) {
        switch error.code {
        case .notAuthenticated:
            print("[CloudKit] 💡 Fix: Sign into iCloud in System Settings")
        case .networkUnavailable, .networkFailure:
            print("[CloudKit] 💡 Fix: Check network connection")
        case .quotaExceeded:
            print("[CloudKit] 💡 Fix: iCloud storage is full - free up space")
        case .partialFailure:
            if let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                print("[CloudKit] 💡 Partial failure details:")
                for (key, partialError) in partialErrors {
                    print("[CloudKit]    \(key): \(partialError.localizedDescription)")
                }
            }
        case .zoneBusy:
            print("[CloudKit] 💡 Zone busy - will retry automatically")
        case .serviceUnavailable:
            print("[CloudKit] 💡 CloudKit service temporarily unavailable")
        case .requestRateLimited:
            if let retryAfter = error.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
                print("[CloudKit] 💡 Rate limited - retry after \(retryAfter)s")
            }
        case .accountTemporarilyUnavailable:
            print("[CloudKit] 💡 Account temporarily unavailable - try again later")
        default:
            print("[CloudKit] 💡 Error code \(error.code.rawValue) - check Apple docs")
        }
    }
}
