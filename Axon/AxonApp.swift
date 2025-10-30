//
//  AxonApp.swift
//  Axon
//
//  Created by Tom on 10/29/25.
//

import SwiftUI
import CoreData
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@main
struct AxonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authService = AuthenticationService.shared

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                AppContainerView()
            } else {
                AuthenticationView()
            }
        }
    }
}

// MARK: - App Delegate for Firebase

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize Firebase
        FirebaseApp.configure()

        #if DEBUG
        print("[AppDelegate] Firebase configured in DEBUG mode")
        // Note: Emulator configuration can be enabled in FirebaseConfig
        #else
        print("[AppDelegate] Firebase configured in PRODUCTION mode")
        #endif

        // Configure Firestore settings with cache options compatible across SDK versions
        let firestore = Firestore.firestore()
        let settings = firestore.settings

        // Prefer an in-memory cache with an explicit size if supported; otherwise, fall back to persistent cache
        if let MemoryCacheSettingsType = NSClassFromString("FIRMemoryCacheSettings") as? NSObject.Type,
           let memoryCache = MemoryCacheSettingsType.init() as? NSObject {
            // Use KVC to set sizeBytes if available to avoid compile-time symbol dependency
            let desiredSize = 40 * 1024 * 1024 // 40 MB
            if memoryCache.responds(to: Selector(("setSizeBytes:"))) {
                memoryCache.setValue(desiredSize, forKey: "sizeBytes")
            }
            settings.setValue(memoryCache, forKey: "cacheSettings")
        } else {
            // Fallback to persistent cache with default settings
            let persistentCache = PersistentCacheSettings()
            settings.cacheSettings = persistentCache
        }

        firestore.settings = settings

        return true
    }
}

