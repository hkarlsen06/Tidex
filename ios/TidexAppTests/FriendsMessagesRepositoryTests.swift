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
      LocalThreadFeedPlacement.self,
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

  func testFriendFeedPlacementPersistsWhileBaselineMessageIsUnchanged() async throws {
    let repository = try makeRepository()
    await repository.saveThread(makeThread(lastMessageId: "message-1"), for: viewerUserId)

    await repository.setFriendMovedToBottom(friendUserId: "friend-1", viewerUserId: viewerUserId)

    let bottomedIds = await repository.getActiveBottomedFriendIds(for: viewerUserId)
    XCTAssertEqual(bottomedIds, Set(["friend-1"]))
  }

  func testFriendFeedPlacementCanBeClearedManually() async throws {
    let repository = try makeRepository()
    await repository.saveThread(makeThread(lastMessageId: "message-1"), for: viewerUserId)

    await repository.setFriendMovedToBottom(friendUserId: "friend-1", viewerUserId: viewerUserId)
    await repository.clearFriendFeedPlacement(friendUserId: "friend-1", viewerUserId: viewerUserId)

    let bottomedIds = await repository.getActiveBottomedFriendIds(for: viewerUserId)
    XCTAssertEqual(bottomedIds, Set<String>())
  }

  func testFriendFeedPlacementClearsWhenThreadLastMessageChanges() async throws {
    let repository = try makeRepository()
    await repository.saveThread(makeThread(lastMessageId: "message-1"), for: viewerUserId)

    await repository.setFriendMovedToBottom(friendUserId: "friend-1", viewerUserId: viewerUserId)
    await repository.saveThread(
      makeThread(
        lastMessageId: "message-2",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100)
      ),
      for: viewerUserId
    )

    let bottomedIds = await repository.getActiveBottomedFriendIds(for: viewerUserId)
    XCTAssertEqual(bottomedIds, Set<String>())
  }

  func testFriendFeedPlacementSurvivesUnchangedThreadRefresh() async throws {
    let repository = try makeRepository()
    let lastMessageAt = Date(timeIntervalSince1970: 1_700_000_050)
    await repository.saveThread(
      makeThread(lastMessageId: "message-1", lastMessageAt: lastMessageAt),
      for: viewerUserId
    )

    await repository.setFriendMovedToBottom(friendUserId: "friend-1", viewerUserId: viewerUserId)
    await repository.saveThread(
      makeThread(lastMessageId: "message-1", lastMessageAt: lastMessageAt),
      for: viewerUserId
    )

    let bottomedIds = await repository.getActiveBottomedFriendIds(for: viewerUserId)
    XCTAssertEqual(bottomedIds, Set(["friend-1"]))
  }

  func testFriendFeedPlacementSurvivesLastMessageIdChangeAtSameTimestamp() async throws {
    let repository = try makeRepository()
    let lastMessageAt = Date(timeIntervalSince1970: 1_700_000_050)
    await repository.saveThread(
      makeThread(lastMessageId: "local-message-1", lastMessageAt: lastMessageAt),
      for: viewerUserId
    )

    await repository.setFriendMovedToBottom(friendUserId: "friend-1", viewerUserId: viewerUserId)
    await repository.saveThread(
      makeThread(lastMessageId: "message-1", lastMessageAt: lastMessageAt),
      for: viewerUserId
    )

    let bottomedIds = await repository.getActiveBottomedFriendIds(for: viewerUserId)
    XCTAssertEqual(bottomedIds, Set(["friend-1"]))
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

  func testSaveMessagesRoundTripsMessageAndAttachmentReactionsSeparately() async throws {
    let repository = try makeRepository()
    await repository.saveThread(makeThread(lastMessageId: nil), for: viewerUserId)

    let createdAt = Date(timeIntervalSince1970: 1_700_000_010)
    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-1",
          threadId: "thread-1",
          senderUserId: "friend-1",
          messageType: .user,
          body: nil,
          clientId: "client-1",
          replyToMessageId: nil,
          createdAt: createdAt,
          editedAt: nil,
          deletedAt: nil,
          metadataData: nil,
          attachments: [
            FriendMessageAttachment(
              id: "attachment-1",
              attachmentIndex: 0,
              kind: .image,
              storageBucket: "message-attachments",
              storagePath: "thread-1/friend-1/attachment-1.jpeg",
              mimeType: "image/jpeg",
              byteSize: 128,
              width: 320,
              height: 240,
              createdAt: createdAt,
              reactions: [
                FriendMessageReaction(emoji: "🔥", count: 1, viewerHasReacted: true)
              ]
            ),
            FriendMessageAttachment(
              id: "attachment-2",
              attachmentIndex: 1,
              kind: .image,
              storageBucket: "message-attachments",
              storagePath: "thread-1/friend-1/attachment-2.jpeg",
              mimeType: "image/jpeg",
              byteSize: 256,
              width: 640,
              height: 480,
              createdAt: createdAt,
              reactions: [
                FriendMessageReaction(emoji: "😂", count: 2, viewerHasReacted: false)
              ]
            ),
          ],
          reactions: [
            FriendMessageReaction(emoji: "❤️", count: 3, viewerHasReacted: true)
          ]
        )
      ],
      in: "thread-1",
      for: viewerUserId
    )

    let message = try XCTUnwrap(
      repository.getMessage(id: "message-1", viewerUserId: viewerUserId)
    )
    XCTAssertEqual(message.reactions.map(\.emoji), ["❤️"])
    XCTAssertEqual(message.attachments[0].reactions.map(\.emoji), ["🔥"])
    XCTAssertEqual(message.attachments[1].reactions.map(\.emoji), ["😂"])
  }

  private func makeThread(
    id: String = "thread-1",
    friendUserId: String = "friend-1",
    lastMessageId: String?,
    lastMessageAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    unreadCount: Int = 0,
    muted: Bool = false,
    viewerStateUpdatedAt: Date? = nil
  ) -> FriendThread {
    FriendThread(
      id: id,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: friendUserId,
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: lastMessageId,
      lastMessageSenderId: friendUserId,
      lastMessageAt: lastMessageId == nil ? nil : lastMessageAt,
      lastMessageBody: lastMessageId == nil ? nil : "Hello",
      lastMessageHasImage: false,
      unreadCount: unreadCount,
      muted: muted,
      createdAt: Date(timeIntervalSince1970: 1_699_999_900),
      viewerStateUpdatedAt: viewerStateUpdatedAt
    )
  }

  func testSaveConfirmedMessageKeepsSingleMessageAndPreservesOptimisticOrder() async throws {
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
    let optimisticCreatedAt = Date(timeIntervalSince1970: 1_700_000_050)
    let optimisticMessage = FriendMessage(
      id: "local-client-1",
      threadId: "thread-1",
      senderUserId: viewerUserId,
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: optimisticCreatedAt,
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [
        FriendMessageAttachment(
          id: "pending-attachment-1",
          attachmentIndex: 0,
          kind: .image,
          storageBucket: "message-attachments",
          storagePath: "local-pending/pending-attachment-1.jpeg",
          mimeType: "image/jpeg",
          byteSize: 128,
          width: 320,
          height: 240,
          createdAt: optimisticCreatedAt
        )
      ],
      reactions: [],
      sendState: .sending,
      failureMessage: nil
    )
    let confirmedMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: viewerUserId,
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: optimisticCreatedAt.addingTimeInterval(2),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [
        FriendMessageAttachment(
          id: "confirmed-attachment-1",
          attachmentIndex: 0,
          kind: .image,
          storageBucket: "message-attachments",
          storagePath: "thread-1/viewer-1/confirmed-attachment-1.jpeg",
          mimeType: "image/jpeg",
          byteSize: 256,
          width: 640,
          height: 480,
          createdAt: optimisticCreatedAt.addingTimeInterval(2)
        )
      ],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    await repository.saveThread(thread, for: viewerUserId)
    await repository.saveOptimisticMessage(
      optimisticMessage,
      in: "thread-1",
      for: viewerUserId
    )
    await repository.saveConfirmedMessage(
      confirmedMessage,
      replacingLocalMessageId: optimisticMessage.id,
      in: "thread-1",
      for: viewerUserId
    )

    let messages = repository.getMessages(threadId: "thread-1", viewerUserId: viewerUserId)
    let storedThread = try XCTUnwrap(
      repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    )
    let storedMessage = try XCTUnwrap(messages.first)

    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(storedMessage.id, "message-1")
    XCTAssertEqual(storedMessage.sendState, .sent)
    XCTAssertEqual(storedMessage.createdAt, optimisticCreatedAt)
    XCTAssertEqual(storedMessage.attachments.map(\.id), ["confirmed-attachment-1"])
    XCTAssertEqual(storedThread.lastMessageId, "message-1")
    XCTAssertEqual(storedThread.lastMessageAt, optimisticCreatedAt)
  }

  func testSaveMessagesPreservesOptimisticOrderAfterRealtimeResave() async throws {
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
    let optimisticCreatedAt = Date(timeIntervalSince1970: 1_700_000_050)
    let optimisticMessage = FriendMessage(
      id: "local-client-1",
      threadId: "thread-1",
      senderUserId: viewerUserId,
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: optimisticCreatedAt,
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [],
      reactions: [],
      sendState: .sending,
      failureMessage: nil
    )
    let serverCreatedAt = optimisticCreatedAt.addingTimeInterval(2)
    let confirmedMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: viewerUserId,
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: serverCreatedAt,
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )
    let laterIncomingMessage = FriendMessage(
      id: "message-2",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: "Reply",
      clientId: "client-2",
      replyToMessageId: nil,
      createdAt: optimisticCreatedAt.addingTimeInterval(1),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    await repository.saveThread(thread, for: viewerUserId)
    await repository.saveOptimisticMessage(
      optimisticMessage,
      in: "thread-1",
      for: viewerUserId
    )
    await repository.saveConfirmedMessage(
      confirmedMessage,
      replacingLocalMessageId: optimisticMessage.id,
      in: "thread-1",
      for: viewerUserId
    )
    await repository.saveMessages([confirmedMessage], in: "thread-1", for: viewerUserId)
    await repository.saveMessages([laterIncomingMessage], in: "thread-1", for: viewerUserId)

    let messages = repository.getMessages(threadId: "thread-1", viewerUserId: viewerUserId)
    let storedOutgoingMessage = try XCTUnwrap(messages.first(where: { $0.id == "message-1" }))
    let storedThread = try XCTUnwrap(
      repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    )

    XCTAssertEqual(messages.map(\.id), ["message-1", "message-2"])
    XCTAssertEqual(storedOutgoingMessage.createdAt, optimisticCreatedAt)
    XCTAssertEqual(storedThread.lastMessageId, "message-2")
    XCTAssertEqual(storedThread.lastMessageAt, laterIncomingMessage.createdAt)
  }

  func testSaveConfirmedMessageReplacesExplicitLocalMessageEvenWithoutMatchingClientId()
    async throws
  {
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
    let optimisticCreatedAt = Date(timeIntervalSince1970: 1_700_000_050)
    let optimisticMessage = FriendMessage(
      id: "local-client-1",
      threadId: "thread-1",
      senderUserId: viewerUserId,
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: optimisticCreatedAt,
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [],
      reactions: [],
      sendState: .sending,
      failureMessage: nil
    )
    let confirmedMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: viewerUserId,
      messageType: .user,
      body: "Hello",
      clientId: "",
      replyToMessageId: nil,
      createdAt: optimisticCreatedAt.addingTimeInterval(3),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    await repository.saveThread(thread, for: viewerUserId)
    await repository.saveOptimisticMessage(
      optimisticMessage,
      in: "thread-1",
      for: viewerUserId
    )
    await repository.saveConfirmedMessage(
      confirmedMessage,
      replacingLocalMessageId: optimisticMessage.id,
      in: "thread-1",
      for: viewerUserId
    )
    await repository.saveMessages([confirmedMessage], in: "thread-1", for: viewerUserId)

    let messages = repository.getMessages(threadId: "thread-1", viewerUserId: viewerUserId)
    let storedMessage = try XCTUnwrap(messages.first)

    XCTAssertEqual(messages.count, 1)
    XCTAssertEqual(storedMessage.id, "message-1")
    XCTAssertEqual(storedMessage.clientId, "client-1")
    XCTAssertEqual(storedMessage.createdAt, optimisticCreatedAt)
    XCTAssertEqual(storedMessage.sendState, .sent)
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
    XCTAssertEqual(
      storedThread.lastMessagePreviewText, String(localized: .friendsChatPreviewSharedShift))
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

  func testSaveThreadStatePreservesUnreadCountForPartialReadThread() async throws {
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
        lastMessageId: "message-2",
        lastMessageSenderId: "friend-1",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_010),
        lastMessageBody: "Still unread",
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
        updatedAt: Date(timeIntervalSince1970: 1_700_000_011)
      ))

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    let state = repository.getThreadState(threadId: "thread-1", viewerUserId: viewerUserId)

    XCTAssertEqual(thread?.unreadCount, 3)
    XCTAssertEqual(thread?.muted, true)
    XCTAssertEqual(state?.lastReadMessageId, "message-1")
    XCTAssertEqual(state?.muted, true)
  }

  func testSaveThreadStateDropsOlderServerStateThatArrivesLate() async throws {
    let repository = try makeRepository()

    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: "friend-1",
        lastReadMessageId: "message-2",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_010),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_011)
      ))
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: "friend-1",
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: true,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
      ))

    let state = repository.getThreadState(threadId: "thread-1", viewerUserId: "friend-1")

    XCTAssertEqual(state?.lastReadMessageId, "message-2")
    XCTAssertEqual(state?.muted, false)
  }

  func testSaveThreadFromStaleSnapshotKeepsNewerUnreadCount() async throws {
    let repository = try makeRepository()
    await repository.saveThread(makeThread(lastMessageId: "message-1"), for: viewerUserId)
    // A mark-read that finished while the snapshot was loading.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ))

    await repository.saveThread(
      from: FriendThreadSyncSnapshot(
        thread: makeThread(lastMessageId: "message-1", unreadCount: 1),
        viewerState: FriendThreadState(
          threadId: "thread-1",
          userId: viewerUserId,
          lastReadMessageId: nil,
          lastReadAt: nil,
          muted: false,
          updatedAt: Date(timeIntervalSince1970: 1_700_000_010)
        ),
        counterpartPresence: nil,
        messages: [],
        nextCursor: nil,
        snapshotVersion: 1,
        retainedFromVersion: 0,
        hasMore: false
      ),
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 0)
  }

  func testSaveThreadFromStaleSnapshotClearsUnreadWhenNewerStateReadItsLastMessage() async throws {
    let repository = try makeRepository()
    await repository.saveThread(
      makeThread(lastMessageId: "message-1", unreadCount: 1), for: viewerUserId)
    // A notification mark-read of message-2 before the cache has message-2.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-2",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_010),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ))

    await repository.saveThread(
      from: FriendThreadSyncSnapshot(
        thread: makeThread(
          lastMessageId: "message-2",
          lastMessageAt: Date(timeIntervalSince1970: 1_700_000_010),
          unreadCount: 2
        ),
        viewerState: FriendThreadState(
          threadId: "thread-1",
          userId: viewerUserId,
          lastReadMessageId: nil,
          lastReadAt: nil,
          muted: false,
          updatedAt: Date(timeIntervalSince1970: 1_700_000_015)
        ),
        counterpartPresence: nil,
        messages: [],
        nextCursor: nil,
        snapshotVersion: 1,
        retainedFromVersion: 0,
        hasMore: false
      ),
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.lastMessageId, "message-2")
    XCTAssertEqual(thread?.unreadCount, 0)
  }

  func testSaveThreadFromStaleSnapshotKeepsStoredCountWhenNewerStateReadAnEarlierMessage()
    async throws
  {
    let repository = try makeRepository()
    await repository.saveThread(
      makeThread(lastMessageId: "message-2", unreadCount: 1), for: viewerUserId)
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: true,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ))

    await repository.saveThread(
      from: makeSnapshot(
        thread: makeThread(lastMessageId: "message-2", unreadCount: 3),
        viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_010)
      ),
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 1)
    XCTAssertEqual(thread?.muted, true)
  }

  func testSaveThreadFromStaleSnapshotKeepsNewerStateWhenThreadIsNotCached() async throws {
    let repository = try makeRepository()
    // A notification mark-read before the thread list was ever loaded.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: true,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ))

    await repository.saveThread(
      from: makeSnapshot(
        thread: makeThread(lastMessageId: "message-1", unreadCount: 1),
        viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_010)
      ),
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 0)
    XCTAssertEqual(thread?.muted, true)
    let state = repository.getThreadState(threadId: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(state?.lastReadMessageId, "message-1")
  }

  func testSaveThreadsFromStaleInboxKeepsNewerReadState() async throws {
    let repository = try makeRepository()
    await repository.saveThread(
      makeThread(lastMessageId: "message-1", unreadCount: 1), for: viewerUserId)
    // A mark-read that finished while the inbox snapshot was loading.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ))

    await repository.saveThreads(
      [
        makeThread(
          lastMessageId: "message-1",
          unreadCount: 1,
          viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_010)
        )
      ],
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 0)
  }

  func testSaveThreadsAcceptsInboxAtTheStoredStateRevision() async throws {
    let repository = try makeRepository()
    let stateUpdatedAt = Date(timeIntervalSince1970: 1_700_000_020)
    // A cached count that drifted from the server, for example from an older unguarded save.
    await repository.saveThread(
      makeThread(lastMessageId: "message-3", unreadCount: 3), for: viewerUserId)
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-2",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: stateUpdatedAt
      ))

    // The inbox holds the count of that same state revision.
    await repository.saveThreads(
      [
        makeThread(
          lastMessageId: "message-3",
          unreadCount: 1,
          viewerStateUpdatedAt: stateUpdatedAt
        )
      ],
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 1)
  }

  func testSaveThreadFromSnapshotOlderThanInboxKeepsInboxCount() async throws {
    let repository = try makeRepository()
    await repository.saveThreads(
      [
        makeThread(
          lastMessageId: "message-2",
          unreadCount: 2,
          viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
      ],
      for: viewerUserId
    )

    // A thread snapshot that started before the inbox load and finished after it.
    await repository.saveThread(
      from: makeSnapshot(
        thread: makeThread(lastMessageId: "message-1", unreadCount: 1),
        viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ),
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 2)
  }

  func testSaveThreadFromStaleSnapshotUsesNewerStateCountWhenThreadIsNotCached() async throws {
    let repository = try makeRepository()
    // A notification mark-read of message-1 while message-2 stays unread.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020),
        unreadCount: 1
      ))

    await repository.saveThread(
      from: makeSnapshot(
        thread: makeThread(lastMessageId: "message-2", unreadCount: 2),
        viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_010)
      ),
      for: viewerUserId
    )

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 1)
  }

  func testSaveThreadStateAppliesItsUnreadCount() async throws {
    let repository = try makeRepository()
    await repository.saveThread(
      makeThread(lastMessageId: "message-3", unreadCount: 3), for: viewerUserId)

    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-2",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020),
        unreadCount: 1
      ))

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 1)
  }

  func testSaveThreadStateOlderThanInboxKeepsInboxCountButTakesReadMarker() async throws {
    let repository = try makeRepository()
    await repository.saveThreads(
      [
        makeThread(
          lastMessageId: "message-3",
          unreadCount: 2,
          muted: true,
          viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
      ],
      for: viewerUserId
    )

    // A mark-read response that finished after the newer inbox load.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_025),
        unreadCount: 0
      ))

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 2)
    XCTAssertEqual(thread?.muted, true)
    let state = repository.getThreadState(threadId: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(state?.lastReadMessageId, "message-1")
  }

  func testOlderMarkReadOfRestoredLastMessageKeepsNewerInboxCount() async throws {
    let repository = try makeRepository()
    await repository.saveThreads(
      [
        makeThread(
          lastMessageId: "m2",
          unreadCount: 1,
          viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )
      ],
      for: viewerUserId
    )
    // A snapshot from before m2 arrives late and sets the preview back to m1.
    await repository.saveThread(
      from: makeSnapshot(
        thread: makeThread(lastMessageId: "m1", unreadCount: 1),
        viewerStateUpdatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ),
      for: viewerUserId
    )

    // The mark-read of m1 was sent before m2 arrived and its response comes last.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "m1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_025),
        unreadCount: 0
      ))

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 1)
  }

  func testSaveThreadWithoutRevisionKeepsStoredServerCountAndMute() async throws {
    let repository = try makeRepository()
    await repository.saveThread(
      makeThread(lastMessageId: "message-2", unreadCount: 2), for: viewerUserId)
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: viewerUserId,
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: true,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020),
        unreadCount: 1
      ))

    // A delete_message response, which has no state revision, that was sent earlier.
    await repository.saveThread(
      makeThread(lastMessageId: "message-2", unreadCount: 2, muted: false), for: viewerUserId)

    let thread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(thread?.unreadCount, 1)
    XCTAssertEqual(thread?.muted, true)
    let state = repository.getThreadState(threadId: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(state?.muted, true)
  }

  private func makeSnapshot(thread: FriendThread, viewerStateUpdatedAt: Date)
    -> FriendThreadSyncSnapshot
  {
    FriendThreadSyncSnapshot(
      thread: thread,
      viewerState: FriendThreadState(
        threadId: thread.id,
        userId: viewerUserId,
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: thread.muted,
        updatedAt: viewerStateUpdatedAt
      ),
      counterpartPresence: nil,
      messages: [],
      nextCursor: nil,
      snapshotVersion: 1,
      retainedFromVersion: 0,
      hasMore: false
    )
  }

  func testSaveThreadStateAcceptsNewerServerStateWithEarlierReadMarker() async throws {
    let repository = try makeRepository()

    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: "friend-1",
        lastReadMessageId: "message-2",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_010),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_011)
      ))
    // The server purged message-2, which cleared the marker, and then message-1 was marked read.
    await repository.saveThreadState(
      FriendThreadState(
        threadId: "thread-1",
        userId: "friend-1",
        lastReadMessageId: "message-1",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_000),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020)
      ))

    let state = repository.getThreadState(threadId: "thread-1", viewerUserId: "friend-1")

    XCTAssertEqual(state?.lastReadMessageId, "message-1")
  }

  func testSaveMessagesUpdatesLastMessageBodyWhenLatestMessageIsEdited() async throws {
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
      lastMessageId: "message-1",
      lastMessageSenderId: "viewer-1",
      lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000),
      lastMessageBody: "Original body",
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_699_999_000)
    )

    await repository.saveThread(thread, for: viewerUserId)
    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-1",
          threadId: "thread-1",
          senderUserId: "viewer-1",
          messageType: .user,
          body: "Original body",
          clientId: "client-1",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_000),
          editedAt: nil,
          deletedAt: nil,
          metadataData: nil,
          attachments: []
        )
      ],
      in: "thread-1",
      for: viewerUserId
    )

    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-1",
          threadId: "thread-1",
          senderUserId: "viewer-1",
          messageType: .user,
          body: "Edited body",
          clientId: "client-1",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_000),
          editedAt: Date(timeIntervalSince1970: 1_700_000_100),
          deletedAt: nil,
          metadataData: nil,
          attachments: []
        )
      ],
      in: "thread-1",
      for: viewerUserId
    )

    let storedThread = repository.getThread(id: "thread-1", viewerUserId: viewerUserId)
    XCTAssertEqual(storedThread?.lastMessageBody, "Edited body")
  }

  func testDeleteSentMessagesMissingFromSnapshotOnlyPrunesTheSnapshotWindow() async throws {
    let repository = try makeRepository()
    func message(_ id: String, second: TimeInterval, sendState: FriendMessageSendState = .sent)
      -> FriendMessage
    {
      FriendMessage(
        id: id,
        threadId: "thread-1",
        senderUserId: "friend-1",
        messageType: .user,
        body: id,
        clientId: "client-\(id)",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000 + second),
        editedAt: nil,
        deletedAt: nil,
        sendState: sendState
      )
    }
    let beforeSave = Date()
    await repository.saveMessages(
      [
        message("m1", second: 1), message("m2", second: 2), message("m3", second: 3),
        message("m4", second: 4),
      ],
      in: "thread-1",
      for: viewerUserId
    )
    await repository.saveOptimisticMessage(
      message("local-q", second: 5, sendState: .sending), in: "thread-1", for: viewerUserId)
    func prune(snapshot: [FriendMessage], olderHistory: Bool, cutoff: Date) async {
      let snapshot = FriendThreadSyncSnapshot(
        thread: makeThread(lastMessageId: "m3"),
        viewerState: FriendThreadState(
          threadId: "thread-1",
          userId: viewerUserId,
          lastReadMessageId: nil,
          lastReadAt: nil,
          muted: false,
          updatedAt: Date()
        ),
        counterpartPresence: nil,
        messages: snapshot,
        nextCursor: nil,
        snapshotVersion: 1,
        retainedFromVersion: 0,
        hasMore: true
      )
      await repository.deleteSentMessagesMissingFromSnapshot(
        snapshot, includingOlderHistory: olderHistory, writtenBefore: cutoff, for: viewerUserId)
    }
    func cachedIds() -> [String] {
      repository.getMessages(threadId: "thread-1", viewerUserId: viewerUserId).map(\.id)
    }

    // Rows written after the request started can be newer than the snapshot.
    await prune(snapshot: [message("m3", second: 3)], olderHistory: false, cutoff: beforeSave)
    XCTAssertEqual(cachedIds(), ["m1", "m2", "m3", "m4", "local-q"])

    // m4 is inside the window but missing, so the server deleted it. Older rows are unknown.
    await prune(snapshot: [message("m3", second: 3)], olderHistory: false, cutoff: .distantFuture)
    XCTAssertEqual(cachedIds(), ["m1", "m2", "m3", "local-q"])

    await prune(snapshot: [message("m3", second: 3)], olderHistory: true, cutoff: .distantFuture)
    XCTAssertEqual(cachedIds(), ["m3", "local-q"])
  }

  func testDeleteSentMessagesMissingFromSnapshotKeepsOwnRowsUnlessSnapshotHasAllHistory()
    async throws
  {
    let repository = try makeRepository()
    func message(_ id: String, second: TimeInterval, senderUserId: String) -> FriendMessage {
      FriendMessage(
        id: id,
        threadId: "thread-1",
        senderUserId: senderUserId,
        messageType: .user,
        body: id,
        clientId: "client-\(id)",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000 + second),
        editedAt: nil,
        deletedAt: nil,
        sendState: .sent
      )
    }
    let serverMessage = message("m1", second: 1, senderUserId: "friend-1")
    await repository.saveMessages(
      [
        serverMessage,
        // Newer than the window start, but its device send time can differ from server time.
        message("own-2", second: 2, senderUserId: viewerUserId),
      ],
      in: "thread-1",
      for: viewerUserId
    )
    func prune(hasMore: Bool) async {
      let snapshot = FriendThreadSyncSnapshot(
        thread: makeThread(lastMessageId: "m1"),
        viewerState: FriendThreadState(
          threadId: "thread-1",
          userId: viewerUserId,
          lastReadMessageId: nil,
          lastReadAt: nil,
          muted: false,
          updatedAt: Date()
        ),
        counterpartPresence: nil,
        messages: [serverMessage],
        nextCursor: nil,
        snapshotVersion: 1,
        retainedFromVersion: 0,
        hasMore: hasMore
      )
      await repository.deleteSentMessagesMissingFromSnapshot(
        snapshot, includingOlderHistory: false, writtenBefore: .distantFuture, for: viewerUserId)
    }
    func cachedIds() -> [String] {
      repository.getMessages(threadId: "thread-1", viewerUserId: viewerUserId).map(\.id)
    }

    await prune(hasMore: true)
    XCTAssertEqual(cachedIds(), ["m1", "own-2"])

    // A snapshot without more pages holds the whole thread, so a missing row was deleted.
    await prune(hasMore: false)
    XCTAssertEqual(cachedIds(), ["m1"])
  }

  func testGetMessagesFiltersDeletedMessages() async throws {
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
        lastMessageId: "message-visible",
        lastMessageSenderId: "friend-1",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_010),
        lastMessageBody: "Visible",
        lastMessageHasImage: false,
        unreadCount: 0,
        muted: false,
        createdAt: Date(timeIntervalSince1970: 1_699_999_000)
      ),
      for: viewerUserId
    )

    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-deleted",
          threadId: "thread-1",
          senderUserId: "friend-1",
          messageType: .user,
          body: "Deleted",
          clientId: "client-deleted",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_000),
          editedAt: nil,
          deletedAt: Date(timeIntervalSince1970: 1_700_000_005),
          metadataData: nil,
          attachments: []
        ),
        FriendMessage(
          id: "message-visible",
          threadId: "thread-1",
          senderUserId: "friend-1",
          messageType: .user,
          body: "Visible",
          clientId: "client-visible",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_010),
          editedAt: nil,
          deletedAt: nil,
          metadataData: nil,
          attachments: []
        ),
      ],
      in: "thread-1",
      for: viewerUserId
    )

    XCTAssertEqual(
      repository.getMessages(threadId: "thread-1", viewerUserId: viewerUserId).map(\.id),
      ["message-visible"]
    )
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
