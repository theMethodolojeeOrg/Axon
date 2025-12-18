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

        print("[Persistence] Initialized. CloudKitEnabled=\(wantsCloudKit)")
    }

    private init(inMemory: Bool, useCloudKit: Bool) {
        self.isCloudKitEnabled = useCloudKit
        self.container = CoreDataCloudKitStack.makeContainer(inMemory: inMemory, useCloudKit: useCloudKit)
        print("[Persistence] Initialized (preview). CloudKitEnabled=\(useCloudKit)")
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
