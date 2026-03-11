import Foundation
import XCTest

@testable import Tidex

final class FriendsMessagingRichContentTests: XCTestCase {
  func testFriendMessageDecodesShiftSnapshotRichContent() throws {
    let message = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: nil,
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      editedAt: nil,
      deletedAt: nil,
      metadataData: makeShiftSnapshotMetadataData()
    )

    XCTAssertEqual(message.richContentKind, .shiftSnapshot)
    XCTAssertEqual(message.previewKind, .shiftSnapshot)
    XCTAssertEqual(message.previewText, "Shared a shift")
    XCTAssertEqual(message.shiftSnapshot?.ownerDisplayName, "Hjalmar")
    XCTAssertEqual(message.shiftSnapshot?.jobName, "Cafe")
  }

  func testFriendMessageFallsBackToUnknownPreviewForUnsupportedRichContent() {
    let message = FriendMessage(
      id: "message-unsupported",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: nil,
      clientId: "client-unsupported",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_100),
      editedAt: nil,
      deletedAt: nil,
      metadataData: Data(
        """
        {
          "content": {
            "kind": "mystery_card"
          }
        }
        """.utf8
      )
    )

    XCTAssertEqual(message.richContentKind, .unsupported("mystery_card"))
    XCTAssertEqual(message.previewKind, .unknown)
    XCTAssertEqual(message.previewText, "Unsupported message")
    XCTAssertNil(message.richContent)
  }

  func testFriendThreadUsesExplicitPreviewKindForFallbackText() {
    let thread = FriendThread(
      id: "thread-1",
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: "message-1",
      lastMessageSenderId: "friend-1",
      lastMessageAt: Date(timeIntervalSince1970: 1_700_000_200),
      lastMessageBody: nil,
      lastMessagePreviewKind: .shiftSnapshot,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    XCTAssertEqual(thread.resolvedLastMessagePreviewKind, .shiftSnapshot)
    XCTAssertEqual(thread.lastMessagePreviewText, "Shared a shift")
  }

  func testReplyPreviewModelUsesShiftSnapshotFallback() {
    let message = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: nil,
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      editedAt: nil,
      deletedAt: nil,
      metadataData: makeShiftSnapshotMetadataData()
    )

    let preview = FriendsChatReplyPreviewModel(senderName: "Hjalmar", message: message)

    XCTAssertEqual(preview.previewKind, .shiftSnapshot)
    XCTAssertEqual(preview.snippet, "Shared a shift")
  }

  func testReplyPreviewModelUsesImageFallback() {
    let message = FriendMessage(
      id: "message-image",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: nil,
      clientId: "client-image",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_300),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [makeImageAttachment()]
    )

    let preview = FriendsChatReplyPreviewModel(senderName: "Friend", message: message)

    XCTAssertEqual(preview.previewKind, .image)
    XCTAssertEqual(preview.snippet, "Photo")
  }
}

private func makeShiftSnapshotMetadataData() -> Data {
  Data(
    """
    {
      "content": {
        "kind": "shift_snapshot",
        "shift_snapshot": {
          "schema_version": 1,
          "owner_user_id": "032d8c2a-9af6-4777-99f0-24e2c4058bf3",
          "owner_display_name": "Hjalmar",
          "owner_avatar_url": null,
          "shift_id": "2f808874-8b4d-4f6c-ac2d-a0bfd78fbc49",
          "job_name": "Cafe",
          "job_color_hex": "#FFAA00",
          "shift_date": "2026-03-11",
          "start_time": "09:00",
          "end_time": "17:00",
          "paid_hours": 7.5,
          "currency": "kr",
          "includes_earnings": true,
          "gross_pay": 1200.0,
          "net_pay": 1050.0,
          "tax_enabled": true,
          "source": "shift_details_sheet"
        }
      }
    }
    """.utf8
  )
}

private func makeImageAttachment() -> FriendMessageAttachment {
  FriendMessageAttachment(
    id: "attachment-1",
    attachmentIndex: 0,
    kind: .image,
    storageBucket: "message-attachments",
    storagePath: "thread-1/friend-1/attachment-1.jpeg",
    mimeType: "image/jpeg",
    byteSize: 256,
    width: 640,
    height: 480,
    createdAt: Date(timeIntervalSince1970: 1_700_000_300)
  )
}
