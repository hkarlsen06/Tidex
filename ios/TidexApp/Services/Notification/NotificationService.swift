import Foundation
import UIKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "Notifications")

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
      logger.info("Permission denied by user")
      PushNotificationManager.shared.permissionDenied()

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
        logger.info("Permission granted")
        registerForRemoteNotifications()
      } else {
        logger.info("Permission denied")
        PushNotificationManager.shared.permissionDenied()
      }
    } catch {
      logger.error("Permission request failed: \(error.localizedDescription)")
      PushNotificationManager.shared.apnsRegistrationFailed(error)
    }
  }

  /// Register with APNs to receive the device token
  /// This triggers `didRegisterForRemoteNotificationsWithDeviceToken` in AppDelegate
  private func registerForRemoteNotifications() {
    UIApplication.shared.registerForRemoteNotifications()
  }

  /// Remove delivered friend-chat notifications for a thread after the user opens it.
  func clearDeliveredFriendChatNotifications(for threadId: String) async {
    guard !threadId.isEmpty else { return }

    let center = UNUserNotificationCenter.current()
    let identifiers = await deliveredFriendChatNotificationIdentifiers(
      for: threadId,
      center: center
    )
    guard !identifiers.isEmpty else { return }

    center.removeDeliveredNotifications(withIdentifiers: identifiers)
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }

  private func deliveredFriendChatNotificationIdentifiers(
    for threadId: String,
    center: UNUserNotificationCenter
  ) async -> [String] {
    await withCheckedContinuation { continuation in
      center.getDeliveredNotifications { notifications in
        let identifiers = notifications.compactMap { notification -> String? in
          let userInfo = notification.request.content.userInfo
          let type = userInfo["type"] as? String ?? ""
          guard type == "thread_message" || type == "thread_screenshot" else {
            return nil
          }

          guard let notificationThreadId = userInfo["thread_id"] as? String,
            notificationThreadId == threadId
          else {
            return nil
          }

          return notification.request.identifier
        }

        continuation.resume(returning: identifiers)
      }
    }
  }
}
