//
//  NotificationHandler.swift
//  Axon
//
//  V2 Handler for notify_user tool
//

import Foundation
import UserNotifications
import os.log

/// Handler for notify_user tool
///
/// Registered handlers:
/// - `notification` → notify_user
@MainActor
final class NotificationHandler: ToolHandlerV2 {
    
    let handlerId = "notification"
    
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.axon",
        category: "NotificationHandler"
    )
    
    // MARK: - ToolHandlerV2
    
    func executeV2(
        inputs: [String: Any],
        manifest: ToolManifest,
        context: ToolContextV2
    ) async throws -> ToolResultV2 {
        let toolId = manifest.tool.id
        
        switch toolId {
        case "notify_user":
            return await executeNotifyUser(inputs: inputs)
        default:
            throw ToolExecutionErrorV2.executionFailed("Unknown notification tool: \(toolId)")
        }
    }
    
    // MARK: - notify_user
    
    private func executeNotifyUser(inputs: [String: Any]) async -> ToolResultV2 {
        // Parse JSON query if provided
        let parsedInputs: [String: Any]
        if let query = inputs["query"] as? String,
           let data = query.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parsedInputs = json
        } else {
            parsedInputs = inputs
        }
        
        guard let title = parsedInputs["title"] as? String else {
            return ToolResultV2.failure(
                toolId: "notify_user",
                error: "Missing 'title' parameter"
            )
        }
        
        guard let body = parsedInputs["body"] as? String else {
            return ToolResultV2.failure(
                toolId: "notify_user",
                error: "Missing 'body' parameter"
            )
        }
        
        logger.info("Sending notification: \(title)")
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        if let subtitle = parsedInputs["subtitle"] as? String {
            content.subtitle = subtitle
        }
        
        // Create a unique identifier
        let identifier = "axon-\(UUID().uuidString)"
        
        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            
            return ToolResultV2.success(
                toolId: "notify_user",
                output: "Notification sent.\nTitle: \(title)\nBody: \(body)",
                structured: [
                    "notificationId": identifier
                ]
            )
        } catch {
            logger.error("Failed to send notification: \(error.localizedDescription)")
            return ToolResultV2.failure(
                toolId: "notify_user",
                error: "Failed to send notification: \(error.localizedDescription)"
            )
        }
    }
}
