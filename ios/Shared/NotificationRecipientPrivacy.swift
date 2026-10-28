import Foundation
import UserNotifications

/// Keeps recipient-bound notification content private after an account switch or sign-out.
enum NotificationRecipientPrivacy {
  static func redactedContent(
    userInfo: [AnyHashable: Any], signedInUserId: String?
  ) -> UNNotificationContent? {
    guard let recipient = userInfo["recipient_user_id"] as? String,
      !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    let normalizedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let signedIn = signedInUserId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalizedRecipient != signedIn else { return nil }
    // Empty content requires Apple's filtering entitlement to suppress an alert. A neutral
    // alert avoids returning the other account's content when that entitlement isn't present.
    let content = UNMutableNotificationContent()
    content.title = "Tidex"
    return content
  }
}
