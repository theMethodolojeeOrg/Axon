//
//  FirebaseConfig.swift
//  Axon
//
//  Firebase Environment Configuration
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions

enum FirebaseEnvironment {
    case development
    case staging
    case production

    var projectID: String {
        switch self {
        case .development, .staging: return "neurx-8f122"
        case .production: return "neurx-8f122"
        }
    }

    var apiURL: URL {
        switch self {
        case .development:
            // Local emulator URL (matches Firebase Functions emulator)
            return URL(string: "http://localhost:5001/neurx-8f122/us-central1")!
        case .staging, .production:
            // Production Cloud Functions URL
            return URL(string: "https://us-central1-neurx-8f122.cloudfunctions.net")!
        }
    }

    var storageBucket: String {
        return "neurx-8f122.appspot.com"
    }

    var firestoreEmulatorHost: String? {
        #if DEBUG
        return "localhost:8080"
        #else
        return nil
        #endif
    }
}

class FirebaseConfig {
    static let shared = FirebaseConfig()

    let environment: FirebaseEnvironment = {
        // Force production mode - use .development only if you have Firebase emulator running
        // To use emulator: return .development
        return .production
    }()

    var adminAPIKey: String {
        ProcessInfo.processInfo.environment["ADMIN_API_KEY"] ?? ""
    }

    private init() {
        configureEmulator()
    }

    private func configureEmulator() {
        #if DEBUG
        // Note: Emulator configuration should happen after Firebase.configure()
        // This will be called from AppDelegate after initialization
        print("[FirebaseConfig] Running in DEBUG mode - will use emulators if available")
        #endif
    }

    func configureFirestoreEmulator() {
        #if DEBUG
        let db = Firestore.firestore()
        // Disable local persistence for emulator sessions if desired
        let settings = db.settings
        settings.isPersistenceEnabled = false
        // Apply settings before using emulator
        db.settings = settings
        // Point Firestore to the local emulator
        Firestore.firestore().useEmulator(withHost: "localhost", port: 8080)
        print("[FirebaseConfig] Firestore emulator configured")
        #endif
    }

    func configureFunctionsEmulator() {
        #if DEBUG
        Functions.functions().useEmulator(withHost: "localhost", port: 5001)
        print("[FirebaseConfig] Functions emulator configured")
        #endif
    }
}
