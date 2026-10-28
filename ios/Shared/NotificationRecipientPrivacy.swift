import Foundation
import UserNotifications

/// Keeps recipient-bound notification content private after an account switch or sign-out.
enum NotificationRecipientPrivacy {
  static func contentForDelivery(
    _ original: UNNotificationContent, signedInUserId: String?
  ) -> UNNotificationContent {
    if let redacted = redactedContent(
      userInfo: original.userInfo, signedInUserId: signedInUserId)
    {
      return redacted
    }
    guard
      let recipient = original.userInfo["recipient_user_id"] as? String,
      !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      recipient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        == signedInUserId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      let presentation = original.userInfo["notification_presentation"] as? [String: Any],
      let alert = presentation["alert"] as? [String: String],
      let content = original.mutableCopy() as? UNMutableNotificationContent
    else { return original }
    content.title = alert["title"] ?? "Tidex"
    content.subtitle = alert["subtitle"] ?? ""
    content.body = alert["body"] ?? ""
    content.badge = presentation["badge"] as? NSNumber
    if let sound = presentation["sound"] as? String {
      content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
    }
    content.categoryIdentifier = presentation["category"] as? String ?? ""
    content.threadIdentifier = presentation["thread-id"] as? String ?? ""
    content.targetContentIdentifier = presentation["target-content-id"] as? String
    if presentation["interruption-level"] as? String == "active" {
      content.interruptionLevel = .active
    }
    if let score = presentation["relevance-score"] as? Double { content.relevanceScore = score }
    return content
  }

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
