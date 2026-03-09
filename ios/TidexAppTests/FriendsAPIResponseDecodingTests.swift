import XCTest

@testable import Tidex

final class FriendsAPIResponseDecodingTests: XCTestCase {
  func testDecodesBlockedFriendsWhenPresent() throws {
    let data = Data(
      """
      {
        "friends": [],
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
        ],
        "capacity": {
          "canAdd": true,
          "currentCount": 1,
          "limit": 5
        }
      }
      """.utf8
    )

    let response = try JSONDecoder().decode(FriendsAPIResponse.self, from: data)

    XCTAssertEqual(response.friends.count, 0)
    XCTAssertEqual(response.blockedFriends?.count, 1)
    XCTAssertEqual(response.blockedFriends?.first?.id, "friend-1")
    XCTAssertTrue(response.blockedFriends?.first?.sharesWithMe?.hidden ?? false)
  }

  func testDecodesLegacyResponseWithoutBlockedFriends() throws {
    let data = Data(
      """
      {
        "friends": [],
        "capacity": {
          "canAdd": true,
          "currentCount": 0,
          "limit": 5
        }
      }
      """.utf8
    )

    let response = try JSONDecoder().decode(FriendsAPIResponse.self, from: data)

    XCTAssertEqual(response.friends.count, 0)
    XCTAssertNil(response.blockedFriends)
  }
}
