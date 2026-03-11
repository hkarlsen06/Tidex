import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class FriendsMessagesRepositoryTests: XCTestCase {
  private let viewerUserId = "viewer-1"

  private func makeRepository() throws -> FriendsMessagesRepository {
    let schema = Schema([
      LocalThread.self,
      LocalThreadState.self,
      LocalMessage.self,
      LocalMessageAttachment.self,
      LocalMessageReaction.self,
    ])

    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )

    let container = try ModelContainer(for: schema, configurations: [configuration])
    let storeActor = LocalStoreActor(modelContainer: container)
    return FriendsMessagesRepository(container: container, storeActor: storeActor)
  }

  func testSaveThreadsOrdersByLatestActivityDescending() async throws {
    let repository = try makeRepository()

    await repository.saveThreads(
      [
        FriendThread(
          id: "thread-older",
          kind: .direct,
          title: nil,
          avatarUrl: nil,
          metadataData: nil,
          counterpartUserId: "friend-1",
          counterpartDisplayName: "Older",
          counterpartProfilePictureUrl: nil,
          counterpartOAuthAvatarUrl: nil,
          lastMessageId: "message-1",
          lastMessageSenderId: "friend-1",
          lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000),
          lastMessageBody: "Older message",
          lastMessageHasImage: false,
          unreadCount: 1,
          muted: false,
          createdAt: Date(timeIntervalSince1970: 1_699_999_000)
        ),
        FriendThread(
          id: "thread-newer",
          kind: .direct,
          title: nil,
          avatarUrl: nil,
          metadataData: nil,
          counterpartUserId: "friend-2",
          counterpartDisplayName: "Newer",
          counterpartProfilePictureUrl: nil,
          counterpartOAuthAvatarUrl: nil,
          lastMessageId: "message-2",
          lastMessageSenderId: "viewer-1",
          lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
          lastMessageBody: "Newest message",
          lastMessageHasImage: false,
          unreadCount: 0,
          muted: true,
          createdAt: Date(timeIntervalSince1970: 1_699_999_500)
        ),
      ],
      for: viewerUserId
    )

    let threads = repository.getThreads(for: viewerUserId)

    XCTAssertEqual(threads.map(\.id), ["thread-newer", "thread-older"])
    XCTAssertEqual(
      repository.getThreadState(threadId: "thread-newer", viewerUserId: viewerUserId)?.muted, true)
  }

  func testSaveMessagesRoundTripsAttachmentsInAscendingOrder() async throws {
    let repository = try makeRepository()
    let thread = FriendThread(
      id: "thread-1",
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: nil,
      lastMessageSenderId: nil,
      lastMessageAt: nil,
      lastMessageBody: nil,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    await repository.saveThread(thread, for: viewerUserId)
    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-2",
          threadId: "thread-1",
          senderUserId: "friend-1",
          messageType: .user,
          body: "Later",
          clientId: "client-2",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_020),
          editedAt: nil,
          deletedAt: nil,
          metadataData: nil,
          attachments: []
        ),
        FriendMessage(
          id: "message-1",
          threadId: "thread-1",
          senderUserId: "viewer-1",
          messageType: .user,
          body: "Photo",
          clientId: "client-1",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_010),
          editedAt: nil,
          deletedAt: nil,
          metadataData: nil,
          attachments: [
            FriendMessageAttachment(
              id: "attachment-2",
              attachmentIndex: 1,
              kind: .image,
              storageBucket: "message-attachments",
              storagePath: "thread-1/viewer-1/attachment-2.jpeg",
              mimeType: "image/jpeg",
              byteSize: 256,
              width: 640,
              height: 480,
              createdAt: Date(timeIntervalSince1970: 1_700_000_010)
            ),
            FriendMessageAttachment(
              id: "attachment-1",
              attachmentIndex: 0,
              kind: .image,
              storageBucket: "message-attachments",
              storagePath: "thread-1/viewer-1/attachment-1.jpeg",
              mimeType: "image/jpeg",
              byteSize: 128,
              width: 320,
              height: 240,
              createdAt: Date(timeIntervalSince1970: 1_700_000_009)
            ),
          ]
        ),
      ],
      in: "thread-1",
      for: viewerUserId
    )

    let messages = repository.getMessages(threadId: "thread-1", viewerUserId: viewerUserId)

    XCTAssertEqual(messages.map(\.id), ["message-1", "message-2"])
    XCTAssertEqual(messages.first?.attachments.map(\.id), ["attachment-1", "attachment-2"])
    XCTAssertEqual(
      repository.getThread(id: "thread-1", viewerUserId: viewerUserId)?.lastMessageId, "message-2")
  }

  func testSaveMessagesUpdatesThreadPreviewKindForShiftSnapshot() async throws {
    let repository = try makeRepository()
    let thread = FriendThread(
      id: "thread-1",
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: nil,
      lastMessageSenderId: nil,
      lastMessageAt: nil,
      lastMessageBody: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    await repository.saveThread(thread, for: viewerUserId)
    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-shift",
          threadId: "thread-1",
          senderUserId: "friend-1",
          messageType: .user,
          body: nil,
          clientId: "client-shift",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_020),
          editedAt: nil,
          deletedAt: nil,
          metadataData: makeShiftSnapshotMetadataData()
        )
      ],
      in: "thread-1",
      for: viewerUserId
    )

    let storedThread = try XCTUnwrap(
      repository.getThread(id: "thread-1", viewerUserId: viewerUserId))
    XCTAssertEqual(storedThread.lastMessagePreviewKind, .shiftSnapshot)
    XCTAssertEqual(storedThread.lastMessagePreviewText, "Shared a shift")
    XCTAssertFalse(storedThread.lastMessageHasImage)
  }

  func testSaveThreadStateMarksThreadReadAndClearsUnreadCount() async throws {
    let repository = try makeRepository()

    await repository.saveThread(
      FriendThread(
        id: "thread-1",
        kind: .direct,
        title: nil,
        avatarUrl: nil,
        metadataData: nil,
        counterpartUserId: "friend-1",
        counterpartDisplayName: "Friend",
        counterpartProfilePictureUrl: nil,
        counterpartOAuthAvatarUrl: nil,
        lastMessageId: "message-1",
        lastMessageSenderId: "friend-1",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastMessageBody: "Unread",
        lastMessageHasImage: false,
        unreadCount: 3,
        muted: false,
        createdAt: Date(timeIntervalSince1970: 1_699_999_000)
      ),
      for: viewerUserId
    )

    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: true,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
      ))

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    let state = repository.getThreadState(threadId: "thread-1", viewerUserId: viewerUserId)

    XCTAssertEqual(thread?.unreadCount, 0)
    XCTAssertEqual(thread?.muted, true)
    XCTAssertEqual(state?.lastReadMessageId, "message-1")
    XCTAssertEqual(state?.muted, true)
  }

  func testSaveThreadsRemovesThreadsMissingFromLatestRefresh() async throws {
    let repository = try makeRepository()

    await repository.saveThreads(
      [
        FriendThread(
          id: "thread-keep",
          kind: .direct,
          title: nil,
          avatarUrl: nil,
          metadataData: nil,
          counterpartUserId: "friend-1",
          counterpartDisplayName: "Keep",
          counterpartProfilePictureUrl: nil,
          counterpartOAuthAvatarUrl: nil,
          lastMessageId: "message-keep",
          lastMessageSenderId: "friend-1",
          lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
          lastMessageBody: "Keep",
          lastMessageHasImage: false,
          unreadCount: 1,
          muted: false,
          createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        FriendThread(
          id: "thread-remove",
          kind: .direct,
          title: nil,
          avatarUrl: nil,
          metadataData: nil,
          counterpartUserId: "friend-2",
          counterpartDisplayName: "Remove",
          counterpartProfilePictureUrl: nil,
          counterpartOAuthAvatarUrl: nil,
          lastMessageId: "message-remove",
          lastMessageSenderId: "friend-2",
          lastMessageAt: Date(timeIntervalSince1970: 1_700_000_050),
          lastMessageBody: "Remove",
          lastMessageHasImage: false,
          unreadCount: 2,
          muted: false,
          createdAt: Date(timeIntervalSince1970: 1_699_999_950)
        ),
      ],
      for: viewerUserId
    )

    await repository.saveThreads(
      [
        FriendThread(
          id: "thread-keep",
          kind: .direct,
          title: nil,
          avatarUrl: nil,
          metadataData: nil,
          counterpartUserId: "friend-1",
          counterpartDisplayName: "Keep",
          counterpartProfilePictureUrl: nil,
          counterpartOAuthAvatarUrl: nil,
          lastMessageId: "message-keep",
          lastMessageSenderId: "friend-1",
          lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
          lastMessageBody: "Keep",
          lastMessageHasImage: false,
          unreadCount: 1,
          muted: false,
          createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
      ],
      for: viewerUserId
    )

    XCTAssertEqual(repository.getThreads(for: viewerUserId).map(\.id), ["thread-keep"])
    XCTAssertNil(repository.getThread(id: "thread-remove", viewerUserId: viewerUserId))
    XCTAssertNil(repository.getThreadState(threadId: "thread-remove", viewerUserId: viewerUserId))
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
