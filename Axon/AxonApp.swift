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
    @State private var showLaunchScreen = true
    @State private var launchScreenOpacity: Double = 1.0
    @State private var mainAppOpacity: Double = 0.0
    @State private var blackOverlayOpacity: Double = 0.0

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app (underneath)
                if !showLaunchScreen {
                    if authService.isAuthenticated {
                        AppContainerView()
                            .opacity(mainAppOpacity)
                    } else {
                        AuthenticationView()
                            .opacity(mainAppOpacity)
                    }
                }
                
                // Launch screen (on top during animation)
                if showLaunchScreen {
                    LaunchScreenView()
                        .opacity(launchScreenOpacity)
                        .onAppear {
                            startLaunchSequence()
                        }
                }
                
                // Black overlay for transitions
                Color.black
                    .ignoresSafeArea()
                    .opacity(blackOverlayOpacity)
                    .allowsHitTesting(false)
            }
        }
    }
    
    private func startLaunchSequence() {
        // Total animation time: 1.5s fade in + 0.5s glass + 0.8s logo + 10s hold = 12.8s
        let animationDuration = 12.8
        
        // After animations complete, start fade-to-black transition
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            // Step 1: Fade launch screen to black (1.0s)
            withAnimation(.easeInOut(duration: 1.0)) {
                launchScreenOpacity = 0.0
                blackOverlayOpacity = 1.0
            }
            
            // Step 2: Hold black briefly (0.3s), then dismiss launch screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showLaunchScreen = false
                
                // Step 3: Fade main app in from black (1.0s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        mainAppOpacity = 1.0
                        blackOverlayOpacity = 0.0
                    }
                }
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

        // Start API server if enabled in settings
        Task { @MainActor in
            let settings = SettingsStorage.shared.loadSettings()
            if settings?.serverEnabled == true {
                await APIServer.shared.start(
                    port: UInt16(settings?.serverPort ?? 8080),
                    password: settings?.serverPassword,
                    allowExternal: settings?.serverAllowExternal ?? false
                )
                print("[AppDelegate] API Server started automatically")
            }
        }

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Stop API server on app termination
        Task { @MainActor in
            await APIServer.shared.stop()
            print("[AppDelegate] API Server stopped")
        }
    }
}
