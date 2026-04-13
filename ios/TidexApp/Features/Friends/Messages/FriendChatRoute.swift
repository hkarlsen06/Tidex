import Foundation

struct FriendChatRoute: Hashable {
  let threadId: String
  let counterpartUserId: String
  let displayName: String
  let avatarUrl: String?
  let initialMessageId: String?
  let notificationTypingUserId: String?
  let navigationRequestId: UUID?

  init(
    thread: FriendThread,
    fallbackDisplayName: String,
    fallbackAvatarUrl: String?,
    initialMessageId: String? = nil,
    notificationSenderUserId: String? = nil,
    notificationTypingUserId: String? = nil,
    navigationRequestId: UUID? = nil
  ) {
    self.threadId = thread.id
    self.counterpartUserId = thread.counterpartUserId ?? notificationSenderUserId ?? ""
    self.displayName = thread.counterpartDisplayName ?? fallbackDisplayName
    self.avatarUrl = thread.counterpartAvatarUrl ?? fallbackAvatarUrl
    let normalizedMessageId = initialMessageId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let effectiveMessageId: String? =
      if let normalizedMessageId, !normalizedMessageId.isEmpty {
        normalizedMessageId
      } else {
        nil
      }
    self.initialMessageId = effectiveMessageId
    let normalizedTypingUserId = notificationTypingUserId?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    self.notificationTypingUserId =
      if let normalizedTypingUserId, !normalizedTypingUserId.isEmpty {
        normalizedTypingUserId
      } else {
        nil
      }
    self.navigationRequestId =
      navigationRequestId
      ?? (effectiveMessageId != nil
        || notificationSenderUserId != nil
        || self.notificationTypingUserId != nil
        ? UUID() : nil)
  }
}
