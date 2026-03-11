import XCTest

@testable import Tidex

@MainActor
final class FriendsThreadShareVisibilityResolverTests: XCTestCase {
  func testReturnsOutgoingShareEarningsVisibilityAndCachesResult() async throws {
    let provider = MockShareRelationshipProvider(
      friends: [
        Friend(
          id: "friend-1",
          email: "friend@example.com",
          phone: nil,
          firstName: "Friend",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharesWithMe: nil,
          iShareWith: Friend.IShareWith(
            showEarningsToThem: true,
            sharedAt: "2026-03-11",
            ownerMuted: false
          )
        )
      ]
    )
    let resolver = FriendsThreadShareVisibilityResolver(sharingService: provider)

    let firstResult = try await resolver.canCounterpartSeeOwnerEarnings(
      counterpartUserId: "friend-1")
    let secondResult = try await resolver.canCounterpartSeeOwnerEarnings(
      counterpartUserId: "friend-1")

    XCTAssertTrue(firstResult)
    XCTAssertTrue(secondResult)
    XCTAssertEqual(provider.fetchCount, 1)
  }

  func testReturnsFalseWhenCounterpartHasNoOutgoingShare() async throws {
    let provider = MockShareRelationshipProvider(friends: [])
    let resolver = FriendsThreadShareVisibilityResolver(sharingService: provider)

    let result = try await resolver.canCounterpartSeeOwnerEarnings(counterpartUserId: "missing")

    XCTAssertFalse(result)
  }

  func testInvalidatingCachedVisibilityFetchesFreshRelationshipState() async throws {
    let provider = MockShareRelationshipProvider(
      friends: [
        Friend(
          id: "friend-1",
          email: "friend@example.com",
          phone: nil,
          firstName: "Friend",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharesWithMe: nil,
          iShareWith: Friend.IShareWith(
            showEarningsToThem: true,
            sharedAt: "2026-03-11",
            ownerMuted: false
          )
        )
      ]
    )
    let resolver = FriendsThreadShareVisibilityResolver(sharingService: provider)

    let initialResult = try await resolver.canCounterpartSeeOwnerEarnings(
      counterpartUserId: "friend-1")
    provider.friends = [
      Friend(
        id: "friend-1",
        email: "friend@example.com",
        phone: nil,
        firstName: "Friend",
        profilePictureUrl: nil,
        oauthAvatarUrl: nil,
        sharesWithMe: nil,
        iShareWith: Friend.IShareWith(
          showEarningsToThem: false,
          sharedAt: "2026-03-11",
          ownerMuted: false
        )
      )
    ]

    resolver.invalidateCachedVisibility(counterpartUserId: "friend-1")
    let refreshedResult = try await resolver.canCounterpartSeeOwnerEarnings(
      counterpartUserId: "friend-1")

    XCTAssertTrue(initialResult)
    XCTAssertFalse(refreshedResult)
    XCTAssertEqual(provider.fetchCount, 2)
  }
}

@MainActor
private final class MockShareRelationshipProvider: FriendsThreadShareRelationshipProviding {
  var friends: [Friend]
  private(set) var fetchCount = 0

  init(friends: [Friend]) {
    self.friends = friends
  }

  func fetchAllFriends() async throws -> (
    friends: [Friend],
    blockedFriends: [Friend],
    capacity: ShareCapacity
  ) {
    fetchCount += 1
    await Task.yield()
    return (
      friends: friends,
      blockedFriends: [],
      capacity: ShareCapacity(canAdd: true, currentCount: friends.count, limit: 10)
    )
  }
}
