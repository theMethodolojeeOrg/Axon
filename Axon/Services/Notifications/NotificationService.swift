//
//  NotificationService.swift
//  Axon
//
//  Local notification wrapper for user prompts.
//

import Foundation
import Combine
import UserNotifications

enum NotificationError: LocalizedError {
    case notAuthorized
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Notifications are not authorized."
        case .requestFailed(let message):
            return "Notification request failed: \(message)"
        }
    }
}

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { allowed, _ in
                continuation.resume(returning: allowed)
            }
        }
        await refreshAuthorizationStatus()
        return granted
    }

    func sendLocalNotification(
        title: String,
        body: String,
        userInfo: [AnyHashable: Any] = [:]
    ) async throws -> String {
        if authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
        }

        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            throw NotificationError.notAuthorized
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let requestId = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: requestId,
            content: content,
            trigger: nil
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: NotificationError.requestFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        return requestId
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }
    
    // MARK: - Solo Thread Notifications
    
    /// Send notification based on solo thread trigger
    func sendSoloTriggerNotification(
        trigger: SoloNotificationTrigger,
        threadId: String,
        context: [String: String] = [:]
    ) async throws {
        // Check if this trigger is enabled in sovereignty settings
        guard let agreement = SovereigntyService.shared.activeCovenant?.soloWorkAgreement,
              agreement.notificationTriggers.contains(trigger) else {
            return // Trigger not enabled
        }
        
        let (title, body) = notificationContent(for: trigger, context: context)
        
        _ = try await sendLocalNotification(
            title: title,
            body: body,
            userInfo: [
                "source": "solo_thread",
                "trigger": trigger.rawValue,
                "threadId": threadId
            ]
        )
    }
    
    private func notificationContent(
        for trigger: SoloNotificationTrigger,
        context: [String: String]
    ) -> (title: String, body: String) {
        switch trigger {
        case .sessionStarted:
            return ("Solo Session Started", "Axon has started an autonomous work session.")
        case .sessionCompleted:
            return ("Solo Session Complete", context["summary"] ?? "Axon completed its work.")
        case .errorOccurred:
            return ("Solo Session Error", context["error"] ?? "An error occurred.")
        case .budgetThresholdReached:
            return ("Budget Alert", "Solo session approaching daily budget limit.")
        case .turnAllocationExhausted:
            return ("Turns Exhausted", "Axon has used all allocated turns.")
        case .axonRequestedExtension:
            return ("Extension Requested", "Axon wants to continue working.")
        }
    }
}
