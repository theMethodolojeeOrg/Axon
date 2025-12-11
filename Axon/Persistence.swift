//
//  Persistence.swift
//  Axon
//
//  Created by Tom on 10/29/25.
//

import CoreData

struct PersistenceController {
    // Default to CloudKit disabled - users can enable via Settings once they set up their Apple Developer account
    // This ensures the app works out of the box without CloudKit entitlements
    static let shared = PersistenceController(useCloudKit: false)

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true, useCloudKit: false)
        let viewContext = result.container.viewContext
        for _ in 0..<10 {
            let newItem = Item(context: viewContext)
            newItem.timestamp = Date()
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false, useCloudKit: Bool = true) {
        container = NSPersistentCloudKitContainer(name: "Axon")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        // Configure the store description
        if let storeDescription = container.persistentStoreDescriptions.first {
            // Enable history tracking for sync
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // Disable CloudKit sync if not needed (local-only mode)
            // This prevents the entitlement error when CloudKit isn't configured
            if !useCloudKit {
                storeDescription.cloudKitContainerOptions = nil
                print("[Persistence] CloudKit sync DISABLED - running in local-only mode")
            } else {
                print("[Persistence] CloudKit sync ENABLED")
            }
        }

        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Log the error but don't crash - fall back gracefully
                print("[Persistence] Error loading persistent store: \(error), \(error.userInfo)")

                // Check if it's a CloudKit-related error
                if error.domain == NSCocoaErrorDomain && error.code == 134060 {
                    print("[Persistence] CloudKit integration error - this may require entitlements setup")
                    print("[Persistence] For local-only operation, set useCloudKit: false")
                }

                // In production, you might want to handle this more gracefully
                // For now, we'll still crash to surface the issue during development
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Create a new background context for sync operations
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    /// Save a context if it has changes
    func saveContext(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
