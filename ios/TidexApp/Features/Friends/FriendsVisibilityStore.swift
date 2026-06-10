import Foundation

/// Stores local visibility preferences for friend relationships that are not server-backed.
internal final class FriendsVisibilityStore {
  internal static let shared: FriendsVisibilityStore = .init()

  private let defaults: UserDefaults

  internal init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  internal func hiddenOutgoingFriendIds(for viewerId: String) -> Set<String> {
    let ids: [String] =
      defaults.stringArray(forKey: hiddenOutgoingFriendIdsKey(for: viewerId)) ?? []
    return Set(ids)
  }

  internal func setOutgoingFriendHidden(_ hidden: Bool, friendId: String, viewerId: String) {
    var hiddenIds: Set<String> = hiddenOutgoingFriendIds(for: viewerId)

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

  deinit {
    // No cleanup is required.
  }
}
