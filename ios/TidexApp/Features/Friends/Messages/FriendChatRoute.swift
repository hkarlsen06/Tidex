import Foundation

struct FriendChatRoute: Hashable {
  let threadId: String
  let counterpartUserId: String
  let displayName: String
  let avatarUrl: String?

  init(thread: FriendThread, fallbackDisplayName: String, fallbackAvatarUrl: String?) {
    self.threadId = thread.id
    self.counterpartUserId = thread.counterpartUserId ?? ""
    self.displayName = thread.counterpartDisplayName ?? fallbackDisplayName
    self.avatarUrl = thread.counterpartAvatarUrl ?? fallbackAvatarUrl
  }
}
