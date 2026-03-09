import Foundation

/// Stores local visibility preferences for friend relationships that are not server-backed.
final class FriendsVisibilityStore {
  static let shared = FriendsVisibilityStore()

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func hiddenOutgoingFriendIds(for viewerId: String) -> Set<String> {
    let ids = defaults.stringArray(forKey: hiddenOutgoingFriendIdsKey(for: viewerId)) ?? []
    return Set(ids)
  }

  func setOutgoingFriendHidden(_ hidden: Bool, friendId: String, viewerId: String) {
    var hiddenIds = hiddenOutgoingFriendIds(for: viewerId)

    if hidden {
      hiddenIds.insert(friendId)
    } else {
      hiddenIds.remove(friendId)
    }

    defaults.set(Array(hiddenIds).sorted(), forKey: hiddenOutgoingFriendIdsKey(for: viewerId))
  }

  private func hiddenOutgoingFriendIdsKey(for viewerId: String) -> String {
    "friends.hiddenOutgoingFriendIds.\(viewerId)"
  }
}
