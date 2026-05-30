import Foundation
import UIKit
import UserNotifications
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "Notifications")

/// Handles push notification permission and registration
/// Call `requestPermissionAndRegister()` only after the user explicitly opts in.
@MainActor
final class NotificationService {
  static let shared = NotificationService()
  static let threadMessageCategoryIdentifier = "THREAD_MESSAGE"
  static let threadMessageReplyActionIdentifier = "THREAD_MESSAGE_REPLY"
  static let threadMessageMarkReadActionIdentifier = "THREAD_MESSAGE_MARK_READ"
  static let wageyResponseCategoryIdentifier = "WAGEY_RESPONSE"

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

  /// Register for APNs only when the user has already granted notification permission.
  /// Use during sign-in/startup so first-run onboarding is not interrupted by a system prompt.
  func registerIfPermissionAlreadyGranted() async {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()

    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      registerForRemoteNotifications()
    case .denied:
      PushNotificationManager.shared.permissionDenied()
    case .notDetermined:
      break
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

  func registerNotificationCategories() {
    let center = UNUserNotificationCenter.current()
    let replyTitle = String(localized: "friends.chat.action.reply", table: "Localizable")
    let replyPlaceholder = String(
      localized: "notifications.chat.action.reply_placeholder",
      table: "Localizable"
    )
    let markReadTitle = String(
      localized: "notifications.chat.action.mark_read",
      table: "Localizable"
    )

    let categories: Set<UNNotificationCategory> = [
      UNNotificationCategory(
        identifier: Self.threadMessageCategoryIdentifier,
        actions: [
          UNTextInputNotificationAction(
            identifier: Self.threadMessageReplyActionIdentifier,
            title: replyTitle,
            options: [],
            textInputButtonTitle: replyTitle,
            textInputPlaceholder: replyPlaceholder
          ),
          UNNotificationAction(
            identifier: Self.threadMessageMarkReadActionIdentifier,
            title: markReadTitle,
            options: []
          ),
        ],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
      UNNotificationCategory(
        identifier: "SHIFT_REMINDER",
        actions: [],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
      UNNotificationCategory(
        identifier: "SMART_PROMPT",
        actions: [],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
      UNNotificationCategory(
        identifier: Self.wageyResponseCategoryIdentifier,
        actions: [],
        intentIdentifiers: [],
        options: [.customDismissAction]
      ),
    ]

    center.setNotificationCategories(categories)
  }

  func scheduleWageyResponseNotification(body: String, conversationId: String?) async {
    let notificationBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !notificationBody.isEmpty else { return }

    let content = UNMutableNotificationContent()
    content.title = "Wagey"
    content.body = notificationBody
    content.sound = .default
    content.categoryIdentifier = Self.wageyResponseCategoryIdentifier
    content.userInfo = [
      "type": "wagey_response",
      "conversation_id": conversationId ?? "",
    ]

    let identifier = "wagey-response-\(conversationId ?? UUID().uuidString)"
    let request = UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: nil
    )

    do {
      try await UNUserNotificationCenter.current().add(request)
    } catch {
      logger.error("Failed to schedule Wagey response notification: \(error.localizedDescription)")
    }
  }

  func setApplicationBadgeCount(_ count: Int) {
    let sanitizedCount = max(0, count)

    if #available(iOS 17.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(sanitizedCount) { error in
        if let error {
          logger.error("Failed to update app badge count: \(error.localizedDescription)")
        }
      }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = sanitizedCount
    }
  }

  func refreshApplicationBadgeCount(viewerUserId: String?) async {
    guard let viewerUserId, !viewerUserId.isEmpty else {
      setApplicationBadgeCount(0)
      return
    }

    do {
      let snapshot = try await FriendsMessagingService.shared.fetchInboxSyncSnapshotV2(
        limit: 1,
        before: nil
      )
      setApplicationBadgeCount(snapshot.unreadDirectMessageCount)
    } catch {
      logger.error("Failed to refresh app badge count: \(error.localizedDescription)")
    }
  }

  func handleThreadMessageMarkRead(threadId: String, messageId: String) async {
    guard !threadId.isEmpty, !messageId.isEmpty else { return }

    do {
      let state = try await FriendsMessagingService.shared.markThreadRead(
        threadId: threadId,
        throughMessageId: messageId
      )
      await FriendsMessagesRepository.shared.saveThreadState(state)
      await refreshApplicationBadgeCount(viewerUserId: AppCoordinator.shared.getCurrentUserId())
      await clearDeliveredFriendChatNotifications(for: threadId)
    } catch {
      logger.error("Failed to mark notification thread as read: \(error.localizedDescription)")
    }
  }

  func handleThreadMessageReply(threadId: String, messageId: String?, body: String) async {
    let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !threadId.isEmpty, !trimmedBody.isEmpty else { return }

    do {
      if let messageId, !messageId.isEmpty {
        let state = try await FriendsMessagingService.shared.markThreadRead(
          threadId: threadId,
          throughMessageId: messageId
        )
        await FriendsMessagesRepository.shared.saveThreadState(state)
      }

      _ = try await FriendsMessagingService.shared.sendMessage(
        threadId: threadId,
        clientId: UUID().uuidString.lowercased(),
        body: trimmedBody,
        replyToMessageId: nil,
        attachments: [],
        metadataData: nil
      )
      await refreshApplicationBadgeCount(viewerUserId: AppCoordinator.shared.getCurrentUserId())
      await clearDeliveredFriendChatNotifications(for: threadId)
    } catch {
      logger.error("Failed to send quick reply from notification: \(error.localizedDescription)")
    }
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

  /// Remove delivered shared-shift notifications for a friend after their calendar is opened.
  func clearDeliveredSharedShiftNotifications(for ownerId: String) async {
    guard !ownerId.isEmpty else { return }

    let center = UNUserNotificationCenter.current()
    let identifiers = await deliveredSharedShiftNotificationIdentifiers(
      for: ownerId,
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
          guard
            type == "thread_message" || type == "thread_screenshot"
              || type == "thread_typing" || type == "thread_reaction"
          else {
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

  private func deliveredSharedShiftNotificationIdentifiers(
    for ownerId: String,
    center: UNUserNotificationCenter
  ) async -> [String] {
    await withCheckedContinuation { continuation in
      center.getDeliveredNotifications { notifications in
        let identifiers = notifications.compactMap { notification -> String? in
          let userInfo = notification.request.content.userInfo
          let type = userInfo["type"] as? String ?? ""
          guard type.hasPrefix("shared_shift_") else {
            return nil
          }

          guard let notificationOwnerId = userInfo["owner_id"] as? String,
            notificationOwnerId == ownerId
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
