import Foundation

@MainActor
protocol FriendsThreadShareRelationshipProviding: AnyObject {
  func fetchAllFriends() async throws -> (
    friends: [Friend],
    blockedFriends: [Friend]
  )
}

extension SharingService: FriendsThreadShareRelationshipProviding {}

@MainActor
protocol FriendsThreadShareVisibilityResolving: AnyObject {
  func canCounterpartSeeOwnerEarnings(counterpartUserId: String) async throws -> Bool
  func invalidateCachedVisibility(counterpartUserId: String?)
}

@MainActor
final class FriendsThreadShareVisibilityResolver: FriendsThreadShareVisibilityResolving {
  private let sharingService: any FriendsThreadShareRelationshipProviding
  private var cachedVisibilityByUserId: [String: Bool] = [:]

  init(sharingService: (any FriendsThreadShareRelationshipProviding)? = nil) {
    self.sharingService = sharingService ?? SharingService.shared
  }

  func canCounterpartSeeOwnerEarnings(counterpartUserId: String) async throws -> Bool {
    if let cachedVisibility = cachedVisibilityByUserId[counterpartUserId] {
      return cachedVisibility
    }

    let friends = try await sharingService.fetchAllFriends().friends
    let visibility =
      friends.first(where: { $0.id == counterpartUserId })?
      .iShareWith?.showEarningsToThem ?? false
    cachedVisibilityByUserId[counterpartUserId] = visibility
    return visibility
  }

  func invalidateCachedVisibility(counterpartUserId: String? = nil) {
    if let counterpartUserId {
      cachedVisibilityByUserId.removeValue(forKey: counterpartUserId)
    } else {
      cachedVisibilityByUserId.removeAll()
    }
  }
}
