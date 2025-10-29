//
//  AxonApp.swift
//  Axon
//
//  Created by Tom on 10/29/25.
//

import SwiftUI
import CoreData

@main
struct AxonApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
