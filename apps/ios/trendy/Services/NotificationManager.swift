//
//  NotificationManager.swift
//  trendy
//
//  Manages local notifications for geofence events
//

import Foundation
import UserNotifications
import Observation

/// Manages local notifications for geofence entry/exit events
@Observable
class NotificationManager: NSObject {

    // MARK: - Properties

    private let notificationCenter: UNUserNotificationCenter

    /// Current authorization status for notifications
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Whether notifications are authorized
    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    // MARK: - Initialization

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()

        self.notificationCenter.delegate = self

        // Check current authorization status
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    /// Request notification authorization
    @MainActor
    func requestAuthorization() async throws {
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])

        if granted {
            print("✅ Notification authorization granted")
        } else {
            print("⚠️ Notification authorization denied")
        }

        await checkAuthorizationStatus()
    }

    /// Check current authorization status
    @MainActor
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        print("📱 Notification authorization status: \(authorizationStatus.description)")
    }

    // MARK: - Notification Delivery

    /// Send a geofence entry notification
    /// - Parameters:
    ///   - geofenceName: Name of the geofence
    ///   - eventTypeName: Name of the event type that was triggered
    func sendGeofenceEntryNotification(geofenceName: String, eventTypeName: String) async {
        guard isAuthorized else {
            print("⚠️ Cannot send notification: not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Entered \(geofenceName)"
        content.body = "Started tracking: \(eventTypeName)"
        content.sound = .default
        content.categoryIdentifier = "GEOFENCE_ENTRY"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "geofence-entry-\(UUID().uuidString)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            print("✅ Sent geofence entry notification: \(geofenceName)")
        } catch {
            print("❌ Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Send a geofence exit notification
    /// - Parameters:
    ///   - geofenceName: Name of the geofence
    ///   - eventTypeName: Name of the event type that was triggered
    ///   - duration: Duration spent in the geofence (optional)
    func sendGeofenceExitNotification(geofenceName: String, eventTypeName: String, duration: TimeInterval? = nil) async {
        guard isAuthorized else {
            print("⚠️ Cannot send notification: not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Exited \(geofenceName)"

        if let duration = duration {
            let durationString = formatDuration(duration)
            content.body = "Stopped tracking \(eventTypeName) (Duration: \(durationString))"
        } else {
            content.body = "Stopped tracking: \(eventTypeName)"
        }

        content.sound = .default
        content.categoryIdentifier = "GEOFENCE_EXIT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "geofence-exit-\(UUID().uuidString)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            print("✅ Sent geofence exit notification: \(geofenceName)")
        } catch {
            print("❌ Failed to send notification: \(error.localizedDescription)")
        }
    }

    /// Send a custom notification
    /// - Parameters:
    ///   - title: Notification title
    ///   - body: Notification body
    ///   - categoryIdentifier: Optional category identifier
    func sendNotification(title: String, body: String, categoryIdentifier: String? = nil) async {
        guard isAuthorized else {
            print("⚠️ Cannot send notification: not authorized")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let categoryIdentifier = categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "custom-\(UUID().uuidString)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await notificationCenter.add(request)
            print("✅ Sent custom notification: \(title)")
        } catch {
            print("❌ Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Notification Management

    /// Remove all delivered notifications
    func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
        print("✅ Removed all delivered notifications")
    }

    /// Remove all pending notification requests
    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        print("✅ Removed all pending notifications")
    }

    /// Get count of pending notifications
    func getPendingNotificationCount() async -> Int {
        let requests = await notificationCenter.pendingNotificationRequests()
        return requests.count
    }

    // MARK: - Helpers

    /// Format duration as human-readable string
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let categoryIdentifier = response.notification.request.content.categoryIdentifier

        print("📱 User tapped notification: \(identifier) (category: \(categoryIdentifier))")

        // Handle different notification actions
        switch categoryIdentifier {
        case "GEOFENCE_ENTRY":
            print("Geofence entry notification tapped")
            // Could navigate to event details here

        case "GEOFENCE_EXIT":
            print("Geofence exit notification tapped")
            // Could navigate to event details here

        default:
            print("Unknown notification category")
        }

        completionHandler()
    }
}

// MARK: - UNAuthorizationStatus Extension

extension UNAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "Not Determined"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
}
