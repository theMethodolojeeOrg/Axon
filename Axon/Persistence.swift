//
//  Persistence.swift
//  Axon
//
//  Created by Tom on 10/29/25.
//

import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true, useCloudKit: false)
        let viewContext = controller.container.viewContext
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
        return controller
    }()

    let container: NSPersistentCloudKitContainer

    /// True if the container was configured with CloudKit enabled.
    let isCloudKitEnabled: Bool

    private init() {
        let settings = SettingsStorage.shared.loadSettings() ?? AppSettings()
        let wantsCloudKit = (settings.deviceModeConfig.cloudSyncProvider == .iCloud)

        self.isCloudKitEnabled = wantsCloudKit
        self.container = CoreDataCloudKitStack.makeContainer(inMemory: false, useCloudKit: wantsCloudKit)

        // Subscribe to save notifications from background contexts to merge changes into viewContext
        // This is critical: background contexts created via newBackgroundContext() are siblings of viewContext,
        // not children. automaticallyMergesChangesFromParent only works for parent-child relationships.
        // Without this, saves in background contexts won't be visible in viewContext until restart.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )

        print("[Persistence] Initialized. CloudKitEnabled=\(wantsCloudKit)")
    }

    private init(inMemory: Bool, useCloudKit: Bool) {
        self.isCloudKitEnabled = useCloudKit
        self.container = CoreDataCloudKitStack.makeContainer(inMemory: inMemory, useCloudKit: useCloudKit)

        // Also set up merging for preview/test contexts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )

        print("[Persistence] Initialized (preview). CloudKitEnabled=\(useCloudKit)")
    }

    /// Merge changes from background context saves into the view context.
    /// This ensures the UI sees changes made by sync operations.
    @objc private func contextDidSave(_ notification: Notification) {
        guard let savedContext = notification.object as? NSManagedObjectContext,
              savedContext != container.viewContext,
              savedContext.persistentStoreCoordinator == container.persistentStoreCoordinator else {
            return
        }

        // Extract info about what was saved for logging
        let userInfo = notification.userInfo ?? [:]
        let insertedCount = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
        let updatedCount = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0
        let deletedCount = (userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>)?.count ?? 0

        print("[Persistence] 🔄 Merging background context save: \(insertedCount) inserted, \(updatedCount) updated, \(deletedCount) deleted")

        // Merge on the main thread to avoid concurrency issues with UI
        DispatchQueue.main.async { [weak self] in
            self?.container.viewContext.mergeChanges(fromContextDidSave: notification)
            print("[Persistence] ✅ Merged changes into viewContext")
        }
    }

    /// Create a new background context for sync operations.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    /// Save a context if it has changes.
    func saveContext(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
