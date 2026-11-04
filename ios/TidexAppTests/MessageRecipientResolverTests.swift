import XCTest

@testable import Tidex

/// Siri may only message friends the server lists as messageable, and one at a time.
final class MessageRecipientResolverTests: XCTestCase {
  private let ola = recipient(id: "ola", name: "Ola Nordmann")
  private let kari = recipient(id: "kari", name: "Kari Nordmann")

  func testAnIdOutsideTheFriendListNeverResolves() {
    let resolution = MessageRecipientResolver.resolve(
      [.userId("stranger")], among: [ola, kari])

    XCTAssertEqual(resolution, .unknown)
  }

  func testAFriendsIdResolvesRegardlessOfCase() {
    let resolution = MessageRecipientResolver.resolve([.userId("OLA")], among: [ola, kari])

    XCTAssertEqual(resolution, .recipient(ola))
  }

  func testASpokenNameMatchingOneFriendResolvesToThatFriend() {
    let resolution = MessageRecipientResolver.resolve([.name("kari")], among: [ola, kari])

    XCTAssertEqual(resolution, .recipient(kari))
  }

  func testASharedSurnameAsksWhichFriend() {
    let resolution = MessageRecipientResolver.resolve([.name("Nordmann")], among: [ola, kari])

    XCTAssertEqual(resolution, .ambiguous([kari, ola]))
  }

  func testSeveralRecipientsAreRefusedEvenWhenAllAreFriends() {
    let resolution = MessageRecipientResolver.resolve(
      [.userId("ola"), .userId("kari")], among: [ola, kari])

    XCTAssertEqual(resolution, .severalPeople)
  }

  private static func recipient(id: String, name: String) -> ShareRecipient {
    ShareRecipient(
      id: id, displayName: name, avatarURL: nil, statusText: nil, canSeeOwnerEarnings: false)
  }
}
