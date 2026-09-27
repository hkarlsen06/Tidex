import Foundation
import XCTest

@testable import Tidex

private enum FriendsMessagingRichContentTestValues {
  static let grossPay: Double = 1_200
  static let netPay: Double = 1_050
}

final class FriendsMessagingRichContentTests: XCTestCase {
  internal func testFriendMessageDecodesShiftSnapshotRichContent() {
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
    XCTAssertEqual(message.previewText, String(localized: .friendsChatPreviewSharedShift))
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
    XCTAssertEqual(message.previewText, String(localized: .friendsChatPreviewUnsupported))
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
    XCTAssertEqual(thread.lastMessagePreviewText, String(localized: .friendsChatPreviewSharedShift))
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
    XCTAssertEqual(preview.snippet, String(localized: .friendsChatPreviewSharedShift))
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
    XCTAssertEqual(preview.iconPreviewKind, .image)
    XCTAssertEqual(preview.snippet, String(localized: .friendsChatPreviewImage))
    XCTAssertEqual(preview.imageAttachments.map(\.id), ["attachment-1"])
  }

  func testReplyPreviewModelKeepsAllImageAttachments() {
    let message = FriendMessage(
      id: "message-multi-image",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: nil,
      clientId: "client-multi-image",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_303),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [
        makeImageAttachment(id: "attachment-2", attachmentIndex: 2),
        makeImageAttachment(id: "attachment-0", attachmentIndex: 0),
        makeImageAttachment(id: "attachment-1", attachmentIndex: 1),
      ]
    )

    let preview = FriendsChatReplyPreviewModel(senderName: "Friend", message: message)

    XCTAssertEqual(preview.previewKind, .image)
    XCTAssertEqual(preview.iconPreviewKind, .image)
    XCTAssertEqual(
      preview.imageAttachments.map(\.id), ["attachment-0", "attachment-1", "attachment-2"])
  }

  func testReplyPreviewModelKeepsImageIconForCaptionedPhoto() {
    let message = FriendMessage(
      id: "message-captioned-image",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: "Look at this",
      clientId: "client-captioned-image",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_301),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [makeImageAttachment()]
    )

    let preview = FriendsChatReplyPreviewModel(senderName: "Friend", message: message)

    XCTAssertEqual(preview.previewKind, .text)
    XCTAssertEqual(preview.iconPreviewKind, .image)
    XCTAssertEqual(preview.snippet, "Look at this")
  }

  func testReplyPreviewModelKeepsShiftIconForCaptionedShiftSnapshot() {
    let message = FriendMessage(
      id: "message-captioned-shift",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: "Can you cover this?",
      clientId: "client-captioned-shift",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_302),
      editedAt: nil,
      deletedAt: nil,
      metadataData: makeShiftSnapshotMetadataData()
    )

    let preview = FriendsChatReplyPreviewModel(senderName: "Friend", message: message)

    XCTAssertEqual(preview.previewKind, .text)
    XCTAssertEqual(preview.iconPreviewKind, .shiftSnapshot)
    XCTAssertEqual(preview.snippet, "Can you cover this?")
  }

  func testForwardedShiftSnapshotBuilderKeepsEarningsForAuthorizedOwnerRecipient() {
    let draft = ForwardedShiftSnapshotBuilder(
      snapshot: makeShiftSnapshot(ownerUserId: "viewer-1", includesEarnings: true),
      viewerUserId: "viewer-1"
    )
    .build(
      for: ShareRecipient(
        id: "recipient-1",
        displayName: "Recipient",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: true
      )
    )

    XCTAssertEqual(draft.snapshot.includesEarnings, true)
    XCTAssertEqual(draft.snapshot.grossPay, FriendsMessagingRichContentTestValues.grossPay)
    XCTAssertEqual(draft.snapshot.netPay, FriendsMessagingRichContentTestValues.netPay)
    XCTAssertTrue(draft.snapshot.taxEnabled)
  }

  func testForwardedShiftSnapshotBuilderRedactsEarningsForUnauthorizedRecipient() {
    let draft = ForwardedShiftSnapshotBuilder(
      snapshot: makeShiftSnapshot(ownerUserId: "viewer-1", includesEarnings: true),
      viewerUserId: "viewer-1"
    )
    .build(
      for: ShareRecipient(
        id: "recipient-1",
        displayName: "Recipient",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      )
    )

    XCTAssertFalse(draft.snapshot.includesEarnings)
    XCTAssertNil(draft.snapshot.grossPay)
    XCTAssertNil(draft.snapshot.netPay)
    XCTAssertFalse(draft.snapshot.taxEnabled)
  }

  func testForwardedShiftSnapshotBuilderRedactsOtherOwnersSnapshot() {
    let draft = ForwardedShiftSnapshotBuilder(
      snapshot: makeShiftSnapshot(ownerUserId: "owner-1", includesEarnings: true),
      viewerUserId: "viewer-1"
    )
    .build(
      for: ShareRecipient(
        id: "recipient-1",
        displayName: "Recipient",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: true
      )
    )

    XCTAssertFalse(draft.snapshot.includesEarnings)
    XCTAssertNil(draft.snapshot.grossPay)
    XCTAssertNil(draft.snapshot.netPay)
    XCTAssertFalse(draft.snapshot.taxEnabled)
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

private func makeShiftSnapshot(
  ownerUserId: String,
  includesEarnings: Bool
) -> FriendShiftSnapshot {
  FriendShiftSnapshot(
    schemaVersion: 1,
    ownerUserId: ownerUserId,
    ownerDisplayName: "Hjalmar",
    ownerAvatarUrl: nil,
    shiftId: "2f808874-8b4d-4f6c-ac2d-a0bfd78fbc49",
    jobName: "Cafe",
    jobColorHex: "#FFAA00",
    shiftDate: "2026-03-11",
    startTime: "09:00",
    endTime: "17:00",
    paidHours: 7.5,
    currency: "kr",
    includesEarnings: includesEarnings,
    grossPay: includesEarnings ? FriendsMessagingRichContentTestValues.grossPay : nil,
    netPay: includesEarnings ? FriendsMessagingRichContentTestValues.netPay : nil,
    taxEnabled: includesEarnings,
    source: "shift_details_sheet"
  )
}

private func makeImageAttachment(
  id: String = "attachment-1",
  attachmentIndex: Int = 0
) -> FriendMessageAttachment {
  FriendMessageAttachment(
    id: id,
    attachmentIndex: attachmentIndex,
    kind: .image,
    storageBucket: "message-attachments",
    storagePath: "thread-1/friend-1/\(id).jpeg",
    mimeType: "image/jpeg",
    byteSize: 256,
    width: 640,
    height: 480,
    createdAt: Date(timeIntervalSince1970: 1_700_000_300)
  )
}
