//
//  AxonApp.swift
//  Axon
//
//  Created by Tom on 10/29/25.
//

import SwiftUI
import CoreData
import Combine

@main
struct AxonApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var settingsViewModel = SettingsViewModel.shared
    @StateObject private var biometricService = BiometricAuthService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showLaunchScreen = true
    @State private var launchScreenOpacity: Double = 1.0
    @State private var mainAppOpacity: Double = 0.0
    @State private var blackOverlayOpacity: Double = 0.0
    @State private var isUnlocked = false
    @State private var showPrivacyBlur = false
    @State private var lastBackgroundTime: Date?

    /// Computed property to determine if app lock overlay should show
    private var showAppLockOverlay: Bool {
        !showLaunchScreen && settingsViewModel.settings.appLockEnabled && !isUnlocked
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Main app (underneath)
                // Local-first: No auth required. Go straight to app after onboarding.
                if !showLaunchScreen {
                    if !settingsViewModel.settings.hasCompletedOnboarding {
                        OnboardingView {
                            // Callback triggers view refresh via @Published settings
                        }
                        .opacity(mainAppOpacity)
                    } else {
                        // Local-first mode: Go directly to app
                        AppContainerView()
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

                // App Lock overlay (shown after launch if enabled)
                // Use opacity instead of conditional to prevent view recreation loops
                AppLockView(isUnlocked: $isUnlocked)
                    .opacity(showAppLockOverlay ? 1 : 0)
                    .allowsHitTesting(showAppLockOverlay)
                    .zIndex(100)

                // Privacy blur for app switcher
                PrivacyBlurView()
                    .opacity(showPrivacyBlur && settingsViewModel.settings.hideContentInAppSwitcher ? 1 : 0)
                    .allowsHitTesting(showPrivacyBlur)
                    .zIndex(101)
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
                AutoSyncOrchestrator.shared.handleScenePhaseChange(newPhase)
            }
            .onAppear {
                // Start auto-sync orchestrator (iCloud pull on launch/foreground)
                AutoSyncOrchestrator.shared.start()

                // If app lock is disabled, mark as unlocked
                if !settingsViewModel.settings.appLockEnabled {
                    isUnlocked = true
                }
            }
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // App became active
            withAnimation(.easeInOut(duration: 0.2)) {
                showPrivacyBlur = false
            }

            // Check if we need to re-lock based on timeout
            if settingsViewModel.settings.appLockEnabled {
                if let lastTime = lastBackgroundTime {
                    let timeout = settingsViewModel.settings.lockTimeout.seconds
                    let elapsed = Int(Date().timeIntervalSince(lastTime))

                    if elapsed >= timeout && timeout != Int.max {
                        isUnlocked = false
                    }
                }
            }

        case .inactive:
            // App going to background (app switcher)
            if settingsViewModel.settings.hideContentInAppSwitcher {
                withAnimation(.easeInOut(duration: 0.1)) {
                    showPrivacyBlur = true
                }
            }

        case .background:
            // App fully in background
            lastBackgroundTime = Date()

        @unknown default:
            break
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

// MARK: - App Delegate

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Local-first mode: Firebase is optional
        // Firebase will only be initialized if user configures a backend that uses it
        #if DEBUG
        print("[AppDelegate] Axon starting in local-first mode")
        #endif

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
#endif
