import Foundation
import UserNotifications
import UIKit

/// Handles push notification permission and registration
/// Call `requestPermissionAndRegister()` after successful authentication
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// Request notification permission and register for APNs
    /// Safe to call multiple times - will only prompt user once
    func requestPermissionAndRegister() async {
        let center = UNUserNotificationCenter.current()

        // Check current authorization status first
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            // First time - request permission
            await requestPermission()

        case .authorized, .provisional, .ephemeral:
            // Already authorized - just register for remote notifications
            registerForRemoteNotifications()

        case .denied:
            // User denied - don't bother registering
            print("[Notifications] Permission denied by user")

        @unknown default:
            break
        }
    }

    /// Request notification permission from the user
    private func requestPermission() async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

            if granted {
                print("[Notifications] Permission granted")
                registerForRemoteNotifications()
            } else {
                print("[Notifications] Permission denied")
            }
        } catch {
            print("[Notifications] Permission request failed: \(error)")
        }
    }

    /// Register with APNs to receive the device token
    /// This triggers `didRegisterForRemoteNotificationsWithDeviceToken` in AppDelegate
    private func registerForRemoteNotifications() {
        print("[Notifications] Registering for remote notifications...")
        UIApplication.shared.registerForRemoteNotifications()
    }
}
