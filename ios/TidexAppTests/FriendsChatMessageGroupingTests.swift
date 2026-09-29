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

  func testStandaloneOutgoingContextDoesNotShowBottomTail() {
    let context = FriendsChatMessageGroupContext(position: .standalone, isCurrentUser: true)

    XCTAssertFalse(context.showsOutgoingBottomTail)
  }

  func testIncomingContextDoesNotShowOutgoingBottomTail() {
    let context = FriendsChatMessageGroupContext(position: .standalone, isCurrentUser: false)

    XCTAssertFalse(context.showsOutgoingBottomTail)
  }

  func testStandaloneIncomingContextDoesNotShowBottomTail() {
    let context = FriendsChatMessageGroupContext(position: .standalone, isCurrentUser: false)

    XCTAssertFalse(context.showsIncomingBottomTail)
  }

  func testOutgoingContextDoesNotShowIncomingBottomTail() {
    let context = FriendsChatMessageGroupContext(position: .standalone, isCurrentUser: true)

    XCTAssertFalse(context.showsIncomingBottomTail)
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

  func testReplyMessagesDoNotJoinAdjacentMessages() {
    let previous = makeMessage(
      id: "message-1",
      senderUserId: "friend-1",
      timestamp: 1_700_000_000
    )
    let reply = makeMessage(
      id: "message-2",
      senderUserId: "friend-1",
      timestamp: 1_700_000_030,
      replyToMessageId: "message-0"
    )
    let next = makeMessage(
      id: "message-3",
      senderUserId: "friend-1",
      timestamp: 1_700_000_060
    )

    let context = FriendsChatMessageGrouping.context(
      for: reply,
      previous: previous,
      next: next,
      viewerUserId: "viewer-1"
    )

    XCTAssertFalse(FriendsChatMessageGrouping.shouldGroup(previous, reply))
    XCTAssertFalse(FriendsChatMessageGrouping.shouldGroup(reply, next))
    XCTAssertEqual(context.position, .standalone)
  }

  func testMessagesWithAttachmentsStartTheirOwnGroupFromPreviousMessages() {
    let previous = makeMessage(
      id: "message-1",
      senderUserId: "friend-1",
      timestamp: 1_700_000_000
    )
    let attachmentMessage = makeMessage(
      id: "message-2",
      senderUserId: "friend-1",
      timestamp: 1_700_000_030,
      body: nil,
      attachments: [makeImageAttachment(id: "image-1")]
    )
    let next = makeMessage(
      id: "message-3",
      senderUserId: "friend-1",
      timestamp: 1_700_000_060
    )

    let context = FriendsChatMessageGrouping.context(
      for: attachmentMessage,
      previous: previous,
      next: next,
      viewerUserId: "viewer-1"
    )

    XCTAssertFalse(FriendsChatMessageGrouping.shouldGroup(previous, attachmentMessage))
    XCTAssertTrue(FriendsChatMessageGrouping.shouldGroup(attachmentMessage, next))
    XCTAssertEqual(context.position, .leading)
  }

  func testCaptionedAttachmentMessagesDoNotJoinFollowingMessages() {
    let attachmentMessage = makeMessage(
      id: "message-1",
      senderUserId: "friend-1",
      timestamp: 1_700_000_000,
      body: "Caption",
      attachments: [makeImageAttachment(id: "image-1")]
    )
    let next = makeMessage(
      id: "message-2",
      senderUserId: "friend-1",
      timestamp: 1_700_000_030
    )

    XCTAssertFalse(FriendsChatMessageGrouping.shouldGroup(attachmentMessage, next))
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
    body: String? = "Hello",
    metadataData: Data? = nil,
    replyToMessageId: String? = nil,
    attachments: [FriendMessageAttachment] = []
  ) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: "thread-1",
      senderUserId: senderUserId,
      messageType: .user,
      body: body,
      clientId: "client-\(id)",
      replyToMessageId: replyToMessageId,
      createdAt: Date(timeIntervalSince1970: timestamp),
      editedAt: nil,
      deletedAt: nil,
      metadataData: metadataData,
      attachments: attachments
    )
  }

  private func makeImageAttachment(id: String) -> FriendMessageAttachment {
    FriendMessageAttachment(
      id: id,
      attachmentIndex: 0,
      kind: .image,
      storageBucket: "message-attachments",
      storagePath: "thread-1/\(id).jpeg",
      mimeType: "image/jpeg",
      byteSize: 1_024,
      width: 1_200,
      height: 900,
      createdAt: Date(timeIntervalSince1970: 1_700_000_030)
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

final class FriendsChatMessageAccessibilityTests: XCTestCase {
  func testJoinSkipsEmptyAndMissingParts() {
    let label = FriendsChatMessageAccessibility.join(["Anna", nil, "  ", "See you at 9", ""])

    XCTAssertEqual(label, "Anna, See you at 9")
  }

  func testDetailsLabelKeepsTimeStatusEditedAndReactionsInOrder() {
    let label = FriendsChatMessageAccessibility.detailsLabel(
      time: "10:32",
      status: .read,
      isEdited: true,
      reactions: [
        FriendMessageReaction(emoji: "👍", count: 2, viewerHasReacted: false),
        FriendMessageReaction(emoji: "❤️", count: 1, viewerHasReacted: true),
      ]
    )

    XCTAssertEqual(
      label,
      [
        "10:32",
        String(localized: .friendsChatStatusRead),
        String(localized: .friendsChatEdited),
        String(localized: .friendsAccessibilityReactions("👍 2, ❤️")),
      ].joined(separator: ", ")
    )
  }

  func testDetailsLabelIsJustTheTimeForIncomingMessagesWithoutExtras() {
    let label = FriendsChatMessageAccessibility.detailsLabel(
      time: "10:32", status: nil, isEdited: false, reactions: [])

    XCTAssertEqual(label, "10:32")
  }
}
