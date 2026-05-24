import XCTest

@testable import Tidex

final class FriendsChatMessageGroupingTests: XCTestCase {
  func testShouldGroupMessagesFromSameSenderWithinFiveMinutes() {
    let first = makeMessage(
      id: "message-1",
      senderUserId: "friend-1",
      timestamp: 1_700_000_000
    )
    let second = makeMessage(
      id: "message-2",
      senderUserId: "friend-1",
      timestamp: 1_700_000_240
    )

    XCTAssertTrue(FriendsChatMessageGrouping.shouldGroup(first, second))
  }

  func testShouldNotGroupMessagesOutsideGroupingWindow() {
    let first = makeMessage(
      id: "message-1",
      senderUserId: "friend-1",
      timestamp: 1_700_000_000
    )
    let second = makeMessage(
      id: "message-2",
      senderUserId: "friend-1",
      timestamp: 1_700_000_301
    )

    XCTAssertFalse(FriendsChatMessageGrouping.shouldGroup(first, second))
  }

  func testContextUsesLeadingAndTrailingPositionsForIncomingMessageGroup() {
    let first = makeMessage(
      id: "message-1",
      senderUserId: "friend-1",
      timestamp: 1_700_000_000
    )
    let second = makeMessage(
      id: "message-2",
      senderUserId: "friend-1",
      timestamp: 1_700_000_120
    )

    let leadingContext = FriendsChatMessageGrouping.context(
      for: first,
      previous: nil,
      next: second,
      viewerUserId: "viewer-1"
    )
    let trailingContext = FriendsChatMessageGrouping.context(
      for: second,
      previous: first,
      next: nil,
      viewerUserId: "viewer-1"
    )

    XCTAssertEqual(leadingContext.position, .leading)
    XCTAssertTrue(leadingContext.showsAvatar)
    XCTAssertTrue(leadingContext.showsSenderLabel)
    XCTAssertEqual(trailingContext.position, .trailing)
    XCTAssertFalse(trailingContext.showsAvatar)
    XCTAssertFalse(trailingContext.showsSenderLabel)
  }

  func testOutgoingMessagesDoNotShowAvatarOrSenderLabel() {
    let first = makeMessage(
      id: "message-1",
      senderUserId: "viewer-1",
      timestamp: 1_700_000_000
    )
    let second = makeMessage(
      id: "message-2",
      senderUserId: "viewer-1",
      timestamp: 1_700_000_030
    )

    let context = FriendsChatMessageGrouping.context(
      for: second,
      previous: first,
      next: nil,
      viewerUserId: "viewer-1"
    )

    XCTAssertEqual(context.position, .trailing)
    XCTAssertFalse(context.showsAvatar)
    XCTAssertFalse(context.showsSenderLabel)
  }

  func testShiftSnapshotMessagesDoNotJoinAdjacentMessages() {
    let previous = makeMessage(
      id: "message-1",
      senderUserId: "friend-1",
      timestamp: 1_700_000_000
    )
    let shiftSnapshot = makeMessage(
      id: "message-2",
      senderUserId: "friend-1",
      timestamp: 1_700_000_030,
      metadataData: makeShiftSnapshotMetadataData()
    )
    let next = makeMessage(
      id: "message-3",
      senderUserId: "friend-1",
      timestamp: 1_700_000_060
    )

    let context = FriendsChatMessageGrouping.context(
      for: shiftSnapshot,
      previous: previous,
      next: next,
      viewerUserId: "viewer-1"
    )

    XCTAssertFalse(FriendsChatMessageGrouping.shouldGroup(previous, shiftSnapshot))
    XCTAssertFalse(FriendsChatMessageGrouping.shouldGroup(shiftSnapshot, next))
    XCTAssertEqual(context.position, .standalone)
    XCTAssertTrue(context.showsAvatar)
    XCTAssertTrue(context.showsSenderLabel)
  }

  func testInitialsUseFirstTwoWordsWhenAvailable() {
    XCTAssertEqual(FriendsChatMessageGrouping.initials(from: "Ada Lovelace"), "AL")
    XCTAssertEqual(FriendsChatMessageGrouping.initials(from: "Friend"), "FR")
    XCTAssertEqual(FriendsChatMessageGrouping.initials(from: " "), "?")
  }

  private func makeMessage(
    id: String,
    senderUserId: String,
    timestamp: TimeInterval,
    metadataData: Data? = nil
  ) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: "thread-1",
      senderUserId: senderUserId,
      messageType: .user,
      body: "Hello",
      clientId: "client-\(id)",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: timestamp),
      editedAt: nil,
      deletedAt: nil,
      metadataData: metadataData,
      attachments: []
    )
  }

  private func makeShiftSnapshotMetadataData() -> Data {
    Data(
      """
      {
        "content": {
          "kind": "shift_snapshot",
          "shift_snapshot": {
            "schema_version": 1,
            "owner_user_id": "owner-1",
            "owner_display_name": "Owner",
            "owner_avatar_url": null,
            "shift_id": "shift-1",
            "job_name": "Cafe",
            "job_color_hex": null,
            "shift_date": "2026-03-11",
            "start_time": "09:00",
            "end_time": "17:00",
            "paid_hours": 7.5,
            "currency": "kr",
            "includes_earnings": false,
            "gross_pay": null,
            "net_pay": null,
            "tax_enabled": false,
            "source": "tests"
          }
        }
      }
      """.utf8
    )
  }
}
