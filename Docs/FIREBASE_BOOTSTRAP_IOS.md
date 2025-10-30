# Firebase Bootstrap Guide for iOS (SwiftUI)

A comprehensive plug-and-play guide for integrating Firebase services with your NeurXAxonChat iOS application. This document provides copy-paste ready implementations for authentication, database, storage, and Cloud Functions integration.

---

## Table of Contents

1. [Project Setup](#project-setup)
2. [Environment Configuration](#environment-configuration)
3. [Firebase Initialization](#firebase-initialization)
4. [Authentication Service](#authentication-service)
5. [Firestore Database Service](#firestore-database-service)
6. [Cloud Storage Service](#cloud-storage-service)
7. [Cloud Functions Integration](#cloud-functions-integration)
8. [API Client with Firebase](#api-client-with-firebase)
9. [Security Rules Overview](#security-rules-overview)
10. [Keychain Integration](#keychain-integration)
11. [Error Handling & Retry Logic](#error-handling--retry-logic)
12. [Testing Configuration](#testing-configuration)
13. [Deployment Checklist](#deployment-checklist)

---

## Project Setup

### 1. Add Firebase to Your Xcode Project

```bash
# Via CocoaPods (recommended for iOS)
pod repo update
pod install
```

**Podfile** (`./Podfile`):

```ruby
platform :ios, '14.0'

target 'NeurXAxonChat' do
  # Firebase dependencies
  pod 'Firebase/Core'
  pod 'Firebase/Auth'
  pod 'Firebase/Firestore'
  pod 'Firebase/Storage'
  pod 'Firebase/Functions'
  pod 'Firebase/Messaging'

  # Additional utilities
  pod 'KeychainAccess'
  pod 'CryptoKit'

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      flutter_additional_ios_build_settings(target)
      target.build_configurations.each do |config|
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
          '$(inherited)',
          'FIREBASE_ANALYTICS_COLLECTION_ENABLED=1'
        ]
      end
    end
  end
end
```

### 2. Download GoogleService-Info.plist

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: **neurx-8f122**
3. Download `GoogleService-Info.plist`
4. Add to Xcode: Drag into project root, ensure it's in "Copy Bundle Resources" build phase

### 3. Update Info.plist

Add these keys to your `Info.plist`:

```xml
<key>FirebaseAppID</key>
<string>1:YOUR_APP_ID:ios:YOUR_IOS_APP_ID</string>

<key>FirebaseAPIKey</key>
<string>YOUR_API_KEY</string>

<key>FirebaseProjectID</key>
<string>neurx-8f122</string>

<key>FirebaseMessageSenderID</key>
<string>YOUR_SENDER_ID</string>

<key>FirebaseStorageBucket</key>
<string>neurx-8f122.appspot.com</string>

<key>NSLocalNetworkUsageDescription</key>
<string>This app needs to access your local network to sync data with Firebase.</string>

<key>NSBonjourServices</key>
<array>
  <string>_firebase._tcp</string>
</array>
```

---

## Environment Configuration

### 1. Create Configuration Manager

**Files/Config/FirebaseConfig.swift**:

```swift
import Foundation
import Firebase

enum FirebaseEnvironment {
    case development
    case staging
    case production

    var projectID: String {
        switch self {
        case .development, .staging: return "neurx-8f122"
        case .production: return "neurx-8f122"  // or separate production project
        }
    }

    var apiURL: URL {
        switch self {
        case .development:
            return URL(string: "http://localhost:5001/neurx-8f122/us-central1")!
        case .staging:
            return URL(string: "https://staging-api.neurx.org")!
        case .production:
            return URL(string: "https://api.neurx.org")!
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
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }()

    var adminAPIKey: String {
        ProcessInfo.processInfo.environment["ADMIN_API_KEY"] ?? ""
    }

    private init() {
        configureEmulator()
    }

    private func configureEmulator() {
        #if DEBUG
        // Use Firestore emulator in development
        let settings = Firestore.firestore().settings
        settings.host = "localhost:8080"
        settings.isPersistenceEnabled = false
        Firestore.firestore().settings = settings

        // Use Functions emulator in development
        Functions.functions().useEmulator(withHost: "localhost", port: 5001)
        #endif
    }
}
```

### 2. Environment Variables

**Build Settings** (Xcode: Target → Build Settings → Search "User-Defined"):

```
ADMIN_API_KEY = your_admin_api_key_here
```

Or create `.xcconfig` file:

```bash
// Build/Development.xcconfig
ADMIN_API_KEY = dev_key_12345
FIREBASE_PROJECT_ID = neurx-8f122
FIRESTORE_EMULATOR_HOST = localhost:8080

// Build/Production.xcconfig
ADMIN_API_KEY = prod_key_xyz789
FIREBASE_PROJECT_ID = neurx-8f122-prod
```

---

## Firebase Initialization

### 1. Configure in App Delegate

**App.swift** (SwiftUI):

```swift
import SwiftUI
import Firebase
import FirebaseAuth

@main
struct NeurXAxonChatApp: App {
    @StateObject private var authService = AuthenticationService.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
    }
}

// App Delegate for Firebase configuration
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize Firebase
        FirebaseApp.configure()

        // Configure Firebase settings
        let settings = Firestore.firestore().settings
        settings.isPersistenceEnabled = true
        settings.cacheSizeBytes = FirestoreCacheSizeBytes.unlimited
        Firestore.firestore().settings = settings

        // Enable offline persistence
        do {
            try Firestore.firestore().enablePersistence()
        } catch let error as NSError {
            if error.code == FirestoreErrorCode.failedPrecondition.rawValue {
                // Multiple tabs open, persistence already enabled
                print("Firestore persistence already enabled")
            } else if error.code == FirestoreErrorCode.unimplemented.rawValue {
                // Running on device without persistent storage
                print("Firestore persistence not supported on this device")
            } else {
                print("Firestore error enabling persistence: \(error.localizedDescription)")
            }
        }

        // Configure remote notifications
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
            let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
            UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in }
            application.registerForRemoteNotifications()
        } else {
            let settings: UIUserNotificationSettings =
                UIUserNotificationSettings(types: [.alert, .badge, .sound], categories: nil)
            application.registerUserNotificationSettings(settings)
        }

        Messaging.messaging().delegate = self

        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let messageID = userInfo["gcm.message_id"] {
            print("Message ID: \(messageID)")
        }
        completionHandler(UIBackgroundFetchResult.newData)
    }
}

// MARK: - Messaging Delegate
extension AppDelegate: MessagingDelegate {
    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        let dataDict: [String: String] = ["token": fcmToken ?? ""]
        NotificationCenter.default.post(
            name: NSNotification.Name("FCMToken"),
            object: nil,
            userInfo: dataDict
        )
        print("FCM Token: \(fcmToken ?? "")")
    }
}

// MARK: - Notification Delegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if let messageID = userInfo["gcm.message_id"] {
            print("Message ID: \(messageID)")
        }
        completionHandler([[.banner, .sound]])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let messageID = userInfo["gcm.message_id"] {
            print("Message ID: \(messageID)")
        }
        completionHandler()
    }
}
```

---

## Authentication Service

### 1. Core Authentication Service

**Services/AuthenticationService.swift**:

```swift
import SwiftUI
import Firebase
import FirebaseAuth

@MainActor
class AuthenticationService: NSObject, ObservableObject {
    static let shared = AuthenticationService()

    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: AuthError?
    @Published var authToken: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    override private init() {
        super.init()
        setupAuthStateListener()
    }

    // MARK: - Setup

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthenticated = user != nil

                // Refresh ID token when user changes
                if let user = user {
                    do {
                        let token = try await user.getIDToken(forcingRefresh: true)
                        self?.authToken = token
                    } catch {
                        print("Error getting ID token: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let authResult = try await Auth.auth().createUser(
                withEmail: email,
                password: password
            )

            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()

            // Create user profile in Firestore
            try await FirebaseDatabase.shared.createUserProfile(
                userId: authResult.user.uid,
                email: email,
                displayName: displayName
            )

            self.user = authResult.user
            self.isAuthenticated = true
        } catch {
            self.error = .signUpFailed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let authResult = try await Auth.auth().signIn(
                withEmail: email,
                password: password
            )

            self.user = authResult.user
            self.isAuthenticated = true

            // Refresh token
            let token = try await authResult.user.getIDToken(forcingRefresh: true)
            self.authToken = token
        } catch {
            self.error = .signInFailed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        do {
            try Auth.auth().signOut()
            self.user = nil
            self.isAuthenticated = false
            self.authToken = nil
            self.error = nil
        } catch {
            self.error = .signOutFailed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            self.error = .resetPasswordFailed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Token Management

    func refreshToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }

        let token = try await user.getIDToken(forcingRefresh: true)
        self.authToken = token
        return token
    }

    func getIdToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notAuthenticated
        }

        return try await user.getIDToken(forcingRefresh: false)
    }

    // MARK: - Cleanup

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case notAuthenticated
    case signUpFailed(String)
    case signInFailed(String)
    case signOutFailed(String)
    case resetPasswordFailed(String)
    case tokenRefreshFailed(String)
    case invalidCredentials
    case userAlreadyExists
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .signUpFailed(let message):
            return "Sign up failed: \(message)"
        case .signInFailed(let message):
            return "Sign in failed: \(message)"
        case .signOutFailed(let message):
            return "Sign out failed: \(message)"
        case .resetPasswordFailed(let message):
            return "Password reset failed: \(message)"
        case .tokenRefreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .invalidCredentials:
            return "Invalid email or password"
        case .userAlreadyExists:
            return "User with this email already exists"
        case .networkError:
            return "Network connection error"
        }
    }
}
```

### 2. Secure Token Storage

**Services/SecureTokenStorage.swift**:

```swift
import Foundation
import KeychainAccess

class SecureTokenStorage {
    static let shared = SecureTokenStorage()

    private let keychain = Keychain(service: "com.neurx.axonchat.firebase")

    private enum KeychainKeys: String {
        case idToken = "firebase_id_token"
        case refreshToken = "firebase_refresh_token"
        case apiKey = "admin_api_key"
    }

    // MARK: - ID Token

    func saveIdToken(_ token: String) throws {
        try keychain.set(token, key: KeychainKeys.idToken.rawValue)
    }

    func getIdToken() throws -> String? {
        try keychain.get(KeychainKeys.idToken.rawValue)
    }

    func deleteIdToken() throws {
        try keychain.remove(KeychainKeys.idToken.rawValue)
    }

    // MARK: - API Key

    func saveApiKey(_ key: String) throws {
        try keychain.set(key, key: KeychainKeys.apiKey.rawValue)
    }

    func getApiKey() throws -> String? {
        try keychain.get(KeychainKeys.apiKey.rawValue)
    }

    func deleteApiKey() throws {
        try keychain.remove(KeychainKeys.apiKey.rawValue)
    }

    // MARK: - Clear All

    func clearAll() throws {
        try keychain.removeAll()
    }
}
```

---

## Firestore Database Service

### 1. Core Firestore Service

**Services/FirebaseDatabase.swift**:

```swift
import Foundation
import Firebase
import FirebaseFirestore

@MainActor
class FirebaseDatabase: NSObject, ObservableObject {
    static let shared = FirebaseDatabase()

    private let db = Firestore.firestore()

    // MARK: - User Profile

    func createUserProfile(
        userId: String,
        email: String,
        displayName: String
    ) async throws {
        let userProfile: [String: Any] = [
            "userId": userId,
            "email": email,
            "displayName": displayName,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await db.collection("users").document(userId).setData(userProfile)
    }

    func getUserProfile(userId: String) async throws -> [String: Any]? {
        let document = try await db.collection("users").document(userId).getDocument()
        return document.data()
    }

    func updateUserProfile(
        userId: String,
        updates: [String: Any]
    ) async throws {
        var mutableUpdates = updates
        mutableUpdates["updatedAt"] = FieldValue.serverTimestamp()

        try await db.collection("users").document(userId).updateData(mutableUpdates)
    }

    // MARK: - Memory Operations

    func createMemory(
        userId: String,
        memory: [String: Any]
    ) async throws -> String {
        var mutableMemory = memory
        mutableMemory["userId"] = userId
        mutableMemory["createdAt"] = FieldValue.serverTimestamp()
        mutableMemory["updatedAt"] = FieldValue.serverTimestamp()

        let docRef = try await db.collection("users")
            .document(userId)
            .collection("memories")
            .addDocument(data: mutableMemory)

        return docRef.documentID
    }

    func getMemories(
        userId: String,
        limit: Int = 50,
        startAfter: DocumentSnapshot? = nil
    ) async throws -> [DocumentSnapshot] {
        var query: Query = db.collection("users")
            .document(userId)
            .collection("memories")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)

        if let startAfter = startAfter {
            query = query.start(afterDocument: startAfter)
        }

        let snapshot = try await query.getDocuments()
        return snapshot.documents
    }

    func getMemory(userId: String, memoryId: String) async throws -> [String: Any]? {
        let document = try await db.collection("users")
            .document(userId)
            .collection("memories")
            .document(memoryId)
            .getDocument()

        return document.data()
    }

    func updateMemory(
        userId: String,
        memoryId: String,
        updates: [String: Any]
    ) async throws {
        var mutableUpdates = updates
        mutableUpdates["updatedAt"] = FieldValue.serverTimestamp()

        try await db.collection("users")
            .document(userId)
            .collection("memories")
            .document(memoryId)
            .updateData(mutableUpdates)
    }

    func deleteMemory(userId: String, memoryId: String) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("memories")
            .document(memoryId)
            .delete()
    }

    // MARK: - Conversation Operations

    func createConversation(
        userId: String,
        conversation: [String: Any]
    ) async throws -> String {
        var mutableConversation = conversation
        mutableConversation["userId"] = userId
        mutableConversation["createdAt"] = FieldValue.serverTimestamp()
        mutableConversation["updatedAt"] = FieldValue.serverTimestamp()

        let docRef = try await db.collection("users")
            .document(userId)
            .collection("conversations")
            .addDocument(data: mutableConversation)

        return docRef.documentID
    }

    func getConversations(userId: String) async throws -> [DocumentSnapshot] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("conversations")
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents
    }

    func getConversation(
        userId: String,
        conversationId: String
    ) async throws -> [String: Any]? {
        let document = try await db.collection("users")
            .document(userId)
            .collection("conversations")
            .document(conversationId)
            .getDocument()

        return document.data()
    }

    func addMessage(
        userId: String,
        conversationId: String,
        message: [String: Any]
    ) async throws -> String {
        var mutableMessage = message
        mutableMessage["createdAt"] = FieldValue.serverTimestamp()

        let docRef = try await db.collection("users")
            .document(userId)
            .collection("conversations")
            .document(conversationId)
            .collection("messages")
            .addDocument(data: mutableMessage)

        return docRef.documentID
    }

    func getMessages(
        userId: String,
        conversationId: String,
        limit: Int = 50
    ) async throws -> [DocumentSnapshot] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents
    }

    // MARK: - Settings

    func getSettings(userId: String) async throws -> [String: Any]? {
        let document = try await db.collection("users")
            .document(userId)
            .collection("settings")
            .document("preferences")
            .getDocument()

        return document.data()
    }

    func updateSettings(
        userId: String,
        settings: [String: Any]
    ) async throws {
        try await db.collection("users")
            .document(userId)
            .collection("settings")
            .document("preferences")
            .setData(settings, merge: true)
    }

    // MARK: - Batch Operations

    func batchWrite(
        _ operations: [(type: OperationType, path: String, data: [String: Any]?)]
    ) async throws {
        let batch = db.batch()

        for operation in operations {
            let docRef = db.document(operation.path)

            switch operation.type {
            case .set:
                if let data = operation.data {
                    batch.setData(data, forDocument: docRef, merge: true)
                }
            case .update:
                if let data = operation.data {
                    batch.updateData(data, forDocument: docRef)
                }
            case .delete:
                batch.deleteDocument(docRef)
            }
        }

        try await batch.commit()
    }

    enum OperationType {
        case set, update, delete
    }

    // MARK: - Listening to Changes

    func listenToMemories(
        userId: String,
        onUpdate: @escaping ([DocumentSnapshot]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        return db.collection("users")
            .document(userId)
            .collection("memories")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    onError(error)
                } else if let snapshot = snapshot {
                    onUpdate(snapshot.documents)
                }
            }
    }

    func listenToConversations(
        userId: String,
        onUpdate: @escaping ([DocumentSnapshot]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        return db.collection("users")
            .document(userId)
            .collection("conversations")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    onError(error)
                } else if let snapshot = snapshot {
                    onUpdate(snapshot.documents)
                }
            }
    }
}
```

---

## Cloud Storage Service

### 1. Cloud Storage Integration

**Services/FirebaseStorage.swift**:

```swift
import Foundation
import Firebase
import FirebaseStorage

@MainActor
class FirebaseStorageService: ObservableObject {
    static let shared = FirebaseStorageService()

    private let storage = Storage.storage()

    // MARK: - Audio Upload

    func uploadAudio(
        userId: String,
        conversationId: String,
        data: Data,
        fileName: String
    ) async throws -> String {
        let path = "users/\(userId)/audio/\(conversationId)/\(fileName)"
        let storageRef = storage.reference().child(path)

        let metadata = StorageMetadata()
        metadata.contentType = "audio/mpeg"

        _ = try await storageRef.putDataAsync(data, metadata: metadata)

        return path
    }

    // MARK: - Download URL

    func getDownloadUrl(
        userId: String,
        conversationId: String,
        fileName: String,
        expirationTime: TimeInterval = 7 * 24 * 60 * 60  // 7 days
    ) async throws -> URL {
        let path = "users/\(userId)/audio/\(conversationId)/\(fileName)"
        let storageRef = storage.reference().child(path)

        let url = try await storageRef.downloadURL()
        return url
    }

    // MARK: - Generate Signed URLs

    func generateSignedUrl(
        path: String,
        expirationTime: TimeInterval = 7 * 24 * 60 * 60
    ) async throws -> URL {
        let storageRef = storage.reference().child(path)
        let url = try await storageRef.downloadURL()
        return url
    }

    // MARK: - Delete File

    func deleteFile(_ path: String) async throws {
        let storageRef = storage.reference().child(path)
        try await storageRef.delete()
    }

    // MARK: - Get File Metadata

    func getFileMetadata(_ path: String) async throws -> StorageMetadata {
        let storageRef = storage.reference().child(path)
        return try await storageRef.getMetadata()
    }

    // MARK: - List Files

    func listFiles(
        userId: String,
        conversationId: String
    ) async throws -> [StorageReference] {
        let path = "users/\(userId)/audio/\(conversationId)"
        let storageRef = storage.reference().child(path)

        let result = try await storageRef.listAsync(maxResults: 100)
        return result.items
    }

    // MARK: - Download Data

    func downloadData(
        path: String,
        maxSize: Int64 = 1024 * 1024 * 10  // 10 MB
    ) async throws -> Data {
        let storageRef = storage.reference().child(path)
        let data = try await storageRef.data(maxSize: maxSize)
        return data
    }
}
```

---

## Cloud Functions Integration

### 1. Cloud Functions Service

**Services/CloudFunctionsService.swift**:

```swift
import Foundation
import Firebase
import FirebaseFunctions

@MainActor
class CloudFunctionsService: ObservableObject {
    static let shared = CloudFunctionsService()

    private let functions = Functions.functions()

    @Published var isLoading = false
    @Published var error: String?

    override init() {
        super.init()
        #if DEBUG
        // Connect to local emulator in debug mode
        functions.useEmulator(withHost: "localhost", port: 5001)
        #endif
    }

    // MARK: - Generic Callable Function

    func callFunction<T: Decodable>(
        name: String,
        data: [String: Any]
    ) async throws -> T {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let result = try await functions.httpsCallable(name).call(data)

        guard let resultData = result.data as? [String: Any] else {
            throw FunctionError.invalidResponse
        }

        let jsonData = try JSONSerialization.data(withJSONObject: resultData)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        return try decoder.decode(T.self, from: jsonData)
    }

    // MARK: - Chat Function

    func chat(providerId: String, messages: [[String: Any]]) async throws -> ChatResponse {
        let data: [String: Any] = [
            "providerId": providerId,
            "request": [
                "messages": messages
            ]
        ]

        let result = try await functions.httpsCallable("chat").call(data)
        guard let resultData = result.data as? [String: Any] else {
            throw FunctionError.invalidResponse
        }

        let jsonData = try JSONSerialization.data(withJSONObject: resultData)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        return try decoder.decode(ChatResponse.self, from: jsonData)
    }

    // MARK: - Get Available Providers

    func listProviders() async throws -> [Provider] {
        let result = try await functions.httpsCallable("listProviders").call()

        guard let data = result.data as? [String: Any],
              let providersData = data["providers"] as? [[String: Any]] else {
            throw FunctionError.invalidResponse
        }

        let jsonData = try JSONSerialization.data(withJSONObject: providersData)
        let decoder = JSONDecoder()

        return try decoder.decode([Provider].self, from: jsonData)
    }
}

// MARK: - Models

struct ChatResponse: Codable {
    let content: String
    let role: String
    let tokens: TokenUsage?
}

struct TokenUsage: Codable {
    let input: Int
    let output: Int
    let total: Int
}

struct Provider: Codable, Identifiable {
    let id: String
    let name: String
}

enum FunctionError: LocalizedError {
    case invalidResponse
    case functionNotFound(String)
    case functionExecutionError(String)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received invalid response from function"
        case .functionNotFound(let name):
            return "Function '\(name)' not found"
        case .functionExecutionError(let message):
            return "Function execution error: \(message)"
        case .invalidData:
            return "Invalid data provided to function"
        }
    }
}
```

---

## API Client with Firebase

### 1. REST API Client (with Firebase Auth)

**Services/APIClient.swift**:

```swift
import Foundation
import Firebase
import FirebaseAuth

@MainActor
class APIClient: ObservableObject {
    static let shared = APIClient()

    private let session: URLSession
    private let config = FirebaseConfig.shared

    @Published var isLoading = false
    @Published var error: APIError?

    private var authService: AuthenticationService { AuthenticationService.shared }
    private var tokenStorage: SecureTokenStorage { SecureTokenStorage.shared }

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .returnCacheDataElseLoad

        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Generic Request Method

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .get,
        body: Encodable? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard var urlComponents = URLComponents(
            url: config.environment.apiURL.appendingPathComponent(endpoint),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        // Add API key to query parameters
        var queryItems = urlComponents.queryItems ?? []
        if let apiKey = try? tokenStorage.getApiKey() {
            queryItems.append(URLQueryItem(name: "apiKey", value: apiKey))
        }
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Add Firebase ID token
        if let token = authService.authToken {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add custom headers
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let headers = headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }

        // Add request body
        if let body = body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            request.httpBody = try encoder.encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Handle status codes
            switch httpResponse.statusCode {
            case 200...299:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                return try decoder.decode(T.self, from: data)

            case 401:
                // Token expired, refresh and retry
                _ = try await authService.refreshToken()
                return try await request(endpoint: endpoint, method: method, body: body, headers: headers)

            case 403:
                throw APIError.forbidden

            case 404:
                throw APIError.notFound

            case 500...599:
                throw APIError.serverError(httpResponse.statusCode)

            default:
                throw APIError.httpError(httpResponse.statusCode)
            }
        } catch let error as APIError {
            self.error = error
            throw error
        } catch {
            let apiError = APIError.networkError(error.localizedDescription)
            self.error = apiError
            throw apiError
        }
    }

    // MARK: - Convenience Methods

    func get<T: Decodable>(_ endpoint: String) async throws -> T {
        try await request(endpoint: endpoint, method: .get)
    }

    func post<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        try await request(endpoint: endpoint, method: .post, body: body)
    }

    func put<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        try await request(endpoint: endpoint, method: .put, body: body)
    }

    func delete<T: Decodable>(_ endpoint: String) async throws -> T {
        try await request(endpoint: endpoint, method: .delete)
    }

    func patch<T: Decodable>(_ endpoint: String, body: Encodable) async throws -> T {
        try await request(endpoint: endpoint, method: .patch, body: body)
    }
}

// MARK: - HTTP Methods

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case forbidden
    case notFound
    case unauthorized
    case serverError(Int)
    case httpError(Int)
    case networkError(String)
    case decodingError(String)
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidData:
            return "Invalid data in response"
        case .forbidden:
            return "Access forbidden"
        case .notFound:
            return "Resource not found"
        case .unauthorized:
            return "Unauthorized access"
        case .serverError(let code):
            return "Server error: \(code)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication token"
        }
    }
}
```

### 2. Endpoint-Specific Services

**Services/MemoryService.swift**:

```swift
import Foundation

@MainActor
class MemoryService: ObservableObject {
    static let shared = MemoryService()

    private let apiClient = APIClient.shared

    @Published var memories: [Memory] = []
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Create Memory

    func createMemory(
        content: String,
        type: String,
        confidence: Double
    ) async throws -> Memory {
        struct CreateMemoryRequest: Encodable {
            let content: String
            let type: String
            let confidence: Double
            let tags: [String]
            let metadata: [String: AnyCodable]
        }

        let request = CreateMemoryRequest(
            content: content,
            type: type,
            confidence: confidence,
            tags: [],
            metadata: [:]
        )

        let response: Memory = try await apiClient.post("/api/memory", body: request)
        return response
    }

    // MARK: - Get Memories

    func getMemories(limit: Int = 50) async throws -> [Memory] {
        let response: MemoriesResponse = try await apiClient.get("/api/memories?limit=\(limit)")
        self.memories = response.memories
        return response.memories
    }

    // MARK: - Get Single Memory

    func getMemory(id: String) async throws -> Memory {
        try await apiClient.get("/api/memory/\(id)")
    }

    // MARK: - Update Memory

    func updateMemory(id: String, updates: [String: AnyCodable]) async throws -> Memory {
        struct UpdateMemoryRequest: Encodable {
            let updates: [String: AnyCodable]
        }

        let request = UpdateMemoryRequest(updates: updates)
        let response: Memory = try await apiClient.put("/api/memory/\(id)", body: request)
        return response
    }

    // MARK: - Delete Memory

    func deleteMemory(id: String) async throws {
        struct EmptyResponse: Decodable {}
        let _: EmptyResponse = try await apiClient.delete("/api/memory/\(id)")
    }
}

// MARK: - Models

struct Memory: Codable, Identifiable {
    let id: String
    let userId: String
    let content: String
    let type: String  // fact, procedure, context, relationship
    let confidence: Double  // 0.0-1.0
    let tags: [String]
    let metadata: [String: AnyCodable]
    let createdAt: Date
    let updatedAt: Date
}

struct MemoriesResponse: Codable {
    let memories: [Memory]
    let total: Int
    let hasMore: Bool
}

// MARK: - AnyCodable Helper

enum AnyCodable: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }
}
```

---

## Security Rules Overview

### 1. Firestore Security Rules Summary

Your current rules (`firestore.rules`) enforce:

- **User Data Isolation**: Each user can only access their own `/users/{userId}` collection
- **Sub-collections**: All sub-collections (memories, conversations, artifacts, settings) require user ownership
- **Project Access**: Users can only access projects they own
- **Admin Operations**: Specific endpoints for user role management (read-only for server)
- **Rate Limiting**: Server-side only writes to prevent client manipulation
- **Super Admin Collections**: Separate collections for super admin audit logs

### 2. Storage Rules Summary

Your current rules (`storage.rules`) enforce:

- **Audio Files**: Users can only read/write their own audio files at `/users/{userId}/audio/{allPaths}`
- **Default Deny**: All other access is denied by default

### 3. Implementing Custom Claims

```swift
// Server-side only (Cloud Functions)
// Adds role to user's custom claims

// Client-side usage
extension AuthenticationService {
    var userRole: String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return user.customClaims?["role"] as? String
    }

    var isAdmin: Bool {
        let role = userRole
        return role == "admin" || role == "superadmin"
    }
}
```

---

## Error Handling & Retry Logic

### 1. Retry with Exponential Backoff

**Utils/RetryableTask.swift**:

```swift
import Foundation

actor RetryableTask {
    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval

    init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 32.0
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    func execute<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch let error as URLError {
                // Only retry on network errors
                guard error.code == .timedOut ||
                      error.code == .networkConnectionLost ||
                      error.code == .notConnectedToInternet else {
                    throw error
                }

                lastError = error

                if attempt < maxRetries - 1 {
                    let delay = min(
                        baseDelay * pow(2.0, Double(attempt)),
                        maxDelay
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? APIError.networkError("Max retries exceeded")
    }
}
```

### 2. Global Error Handler

**Utils/ErrorHandler.swift**:

```swift
import Foundation

class ErrorHandler {
    static func handle(
        _ error: Error,
        context: String = ""
    ) {
        let errorMessage: String

        if let apiError = error as? APIError {
            errorMessage = apiError.localizedDescription
        } else if let authError = error as? AuthError {
            errorMessage = authError.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }

        print("[\(context)] Error: \(errorMessage)")

        // Send to analytics
        #if DEBUG
        // Log to console
        #else
        // Send to crash reporting service (e.g., Crashlytics)
        #endif
    }
}
```

---

## Testing Configuration

### 1. Firebase Emulator Setup

**For Local Development:**

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Start emulator suite
firebase emulators:start

# In your app (AppDelegate), connect to emulator in DEBUG mode
```

### 2. Unit Testing with Mocks

**Tests/MockFirebaseService.swift**:

```swift
import Foundation
@testable import NeurXAxonChat

class MockFirebaseDatabase: ObservableObject {
    var memories: [Memory] = []
    var shouldFail = false

    func createMemory(userId: String, memory: [String: Any]) async throws -> String {
        if shouldFail {
            throw NSError(domain: "MockError", code: -1)
        }
        return UUID().uuidString
    }

    func getMemories(userId: String, limit: Int = 50, startAfter: Any? = nil) async throws -> [Any] {
        if shouldFail {
            throw NSError(domain: "MockError", code: -1)
        }
        return memories
    }
}

// MARK: - Test Example

class MemoryServiceTests: XCTestCase {
    var sut: MemoryService!
    var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        sut = MemoryService(apiClient: mockAPIClient)
    }

    func testCreateMemory() async throws {
        // Arrange
        let memory = Memory(
            id: "1",
            userId: "user1",
            content: "Test",
            type: "fact",
            confidence: 0.8,
            tags: [],
            metadata: [:],
            createdAt: Date(),
            updatedAt: Date()
        )
        mockAPIClient.mockResponse = memory

        // Act
        let result = try await sut.createMemory(content: "Test", type: "fact", confidence: 0.8)

        // Assert
        XCTAssertEqual(result.id, "1")
        XCTAssertEqual(result.content, "Test")
    }
}
```

---

## Keychain Integration

### 1. Complete Keychain Wrapper

**Utils/KeychainManager.swift**:

```swift
import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.neurx.axonchat"
    private let group = "group.com.neurx.axonchat"

    // MARK: - Save

    func save(_ value: String, forKey key: String) throws {
        let data = value.data(using: .utf8)!

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Retrieve

    func retrieve(forKey key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrieveFailed(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }

        return string
    }

    // MARK: - Delete

    func delete(forKey key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Clear All

    func clearAll() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.clearFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case clearFailed(OSStatus)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .retrieveFailed(let status):
            return "Failed to retrieve from keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        case .clearFailed(let status):
            return "Failed to clear keychain: \(status)"
        case .decodingFailed:
            return "Failed to decode keychain data"
        }
    }
}
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Firebase project created (neurx-8f122)
- [ ] GoogleService-Info.plist downloaded and added to Xcode
- [ ] iOS deployment target set to 14.0+
- [ ] Pods installed via CocoaPods
- [ ] Environment variables configured in build settings
- [ ] API key stored securely in Keychain
- [ ] Firebase authentication enabled (Email/Password)
- [ ] Firestore database created and rules deployed
- [ ] Cloud Storage bucket created and rules deployed
- [ ] Cloud Functions deployed with all 49 endpoints

### Testing

- [ ] Unit tests passing (authentication, database, storage)
- [ ] Integration tests passing (Firebase emulator)
- [ ] Error handling tested (network failures, auth expiration)
- [ ] Offline persistence tested
- [ ] Keychain storage verified
- [ ] Token refresh working correctly
- [ ] API key injection confirmed

### Production Deployment

- [ ] Firebase project switched to production
- [ ] CORS rules updated to include iOS app domain
- [ ] Firebase Analytics enabled
- [ ] Crash reporting enabled (Crashlytics)
- [ ] Production API key configured
- [ ] Production Firestore security rules deployed
- [ ] Production Cloud Storage rules deployed
- [ ] Rate limiting configured
- [ ] Monitoring and alerts configured

### Post-Deployment

- [ ] App Store submission prepared
- [ ] TestFlight beta testing completed
- [ ] Firebase console monitoring active
- [ ] Error logs reviewed
- [ ] Performance metrics verified
- [ ] User feedback channels open

---

## Quick Reference: Common Patterns

### Authentication Flow

```swift
// Sign up
try await authService.signUp(
    email: "user@example.com",
    password: "secure_password",
    displayName: "John Doe"
)

// Sign in
try await authService.signIn(
    email: "user@example.com",
    password: "secure_password"
)

// Get token
let token = try await authService.getIdToken()

// Sign out
try authService.signOut()
```

### Firestore Operations

```swift
// Create
let memoryId = try await FirebaseDatabase.shared.createMemory(
    userId: userId,
    memory: ["content": "...", "type": "fact"]
)

// Read
let memory = try await FirebaseDatabase.shared.getMemory(
    userId: userId,
    memoryId: memoryId
)

// Update
try await FirebaseDatabase.shared.updateMemory(
    userId: userId,
    memoryId: memoryId,
    updates: ["confidence": 0.9]
)

// Delete
try await FirebaseDatabase.shared.deleteMemory(
    userId: userId,
    memoryId: memoryId
)

// Listen
let listener = FirebaseDatabase.shared.listenToMemories(
    userId: userId,
    onUpdate: { memories in
        // Handle updates
    },
    onError: { error in
        // Handle error
    }
)
```

### API Calls

```swift
// Generic request
let result: MyType = try await apiClient.request(
    endpoint: "api/endpoint",
    method: .post,
    body: myRequestBody
)

// Convenience methods
let data: MyType = try await apiClient.get("api/endpoint")
let created: MyType = try await apiClient.post("api/endpoint", body: request)
let updated: MyType = try await apiClient.put("api/endpoint", body: request)
let deleted: MyType = try await apiClient.delete("api/endpoint")
```

### Error Handling

```swift
do {
    let result = try await memoryService.createMemory(
        content: "Test",
        type: "fact",
        confidence: 0.8
    )
} catch let error as APIError {
    print("API Error: \(error.errorDescription)")
} catch let error as AuthError {
    print("Auth Error: \(error.errorDescription)")
} catch {
    print("Unknown error: \(error.localizedDescription)")
}
```

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Firebase not initializing | Ensure GoogleService-Info.plist is in bundle resources |
| Authentication failing | Check API key is set in environment variables |
| Firestore rules blocking access | Verify user ID matches security rules |
| Token expiration errors | Ensure token refresh is implemented in APIClient |
| Keychain access denied | Check app capabilities and entitlements |
| Emulator connection issues | Ensure `firebase emulators:start` is running on correct port |

### Debugging

Enable detailed logging:

```swift
// In AppDelegate
#if DEBUG
FirebaseConfiguration.shared.setLoggerLevel(.debug)
#endif
```

Monitor Firestore activity:

```swift
Firestore.firestore().settings.isPersistenceEnabled = true
Firestore.firestore().enableLogging(true)
```

---

## Additional Resources

- [Firebase iOS Documentation](https://firebase.google.com/docs/ios/setup)
- [Firestore iOS Guide](https://firebase.google.com/docs/firestore/quickstart)
- [Firebase Authentication](https://firebase.google.com/docs/auth)
- [Cloud Functions for Firebase](https://firebase.google.com/docs/functions)
- [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite)

---

**Document Version:** 1.0
**Last Updated:** October 29, 2025
**Firebase Project:** neurx-8f122
**Platform:** iOS 14.0+
