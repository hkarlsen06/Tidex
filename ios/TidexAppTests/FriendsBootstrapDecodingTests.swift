import XCTest

@testable import Tidex

final class FriendsBootstrapDecodingTests: XCTestCase {
  func testDecodesBlockedFriendsWhenPresent() throws {
    let data = Data(
      """
      {
        "sharers": [],
        "friends": [],
        "previewPayloads": [],
        "blockedFriends": [
          {
            "id": "friend-1",
            "email": "friend@example.com",
            "phone": null,
            "firstName": "Friend",
            "profilePictureUrl": null,
            "oauthAvatarUrl": null,
            "sharesWithMe": {
              "blocked": true,
              "showEarningsToMe": true,
              "sharedAt": "2026-03-09T00:00:00Z",
              "notificationFrequency": "instant"
            },
            "iShareWith": {
              "showEarningsToThem": false,
              "sharedAt": "2026-03-09T00:00:00Z",
              "ownerMuted": false
            }
          }
        ]
      }
      """.utf8
    )

    let response = try JSONDecoder().decode(FriendsTabBootstrapRPCResponse.self, from: data)

    XCTAssertEqual(response.friends.count, 0)
    XCTAssertEqual(response.blockedFriends?.count, 1)
    XCTAssertEqual(response.blockedFriends?.first?.id, "friend-1")
    XCTAssertTrue(response.blockedFriends?.first?.sharesWithMe?.hidden ?? false)
  }

  /// The server keeps sending a `capacity` stub for older app builds, and may drop it later.
  /// The bootstrap payload has to decode either way.
  func testBootstrapDecodesWithAndWithoutLegacyCapacity() throws {
    let withoutCapacity = Data(
      #"{"sharers": [], "friends": [], "blockedFriends": [], "previewPayloads": []}"#.utf8)
    let withCapacity = Data(
      #"""
      {"sharers": [], "friends": [], "blockedFriends": [], "previewPayloads": [],
       "capacity": {"canAdd": true, "currentCount": 7, "limit": 0}}
      """#.utf8)

    for data in [withoutCapacity, withCapacity] {
      let response = try JSONDecoder().decode(FriendsTabBootstrapRPCResponse.self, from: data)
      XCTAssertTrue(response.friends.isEmpty)
      XCTAssertEqual(response.blockedFriends?.count, 0)
    }
  }
}
