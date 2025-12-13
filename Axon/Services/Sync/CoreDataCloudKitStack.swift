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

enum CoreDataCloudKitStack {
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
                print("[CoreDataCloudKitStack] CloudKit DISABLED")
            } else {
                // Uses CloudKit configuration embedded in the model / entitlements.
                print("[CoreDataCloudKitStack] CloudKit ENABLED")
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                print("[CoreDataCloudKitStack] Failed to load persistent store: \(error), \(error.userInfo)")
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }
}
