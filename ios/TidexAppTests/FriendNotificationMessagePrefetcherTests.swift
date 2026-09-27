import Foundation
import XCTest

@testable import Tidex

@MainActor
final class FriendNotificationMessagePrefetcherTests: XCTestCase {
  func testBackgroundPrefetchSkipsWhenMessageIdMissing() async {
    let context = MockPrefetchContext()
    let repository = MockFriendsMessagesRepository()
    let service = MockFriendsMessagingService()
    let prefetcher = FriendNotificationMessagePrefetcher(
      context: context,
      repository: repository,
      service: service
    )

    let outcome = await prefetcher.prefetchBackgroundMessage(
      threadId: "thread-1",
      messageId: nil
    )

    XCTAssertEqual(outcome, .skipped(.missingMessageId))
    XCTAssertEqual(service.fetchMessagePayloadCallCount, 0)
  }

  func testBackgroundPrefetchRefreshesAlreadyCachedMessage() async {
    let context = MockPrefetchContext()
    let repository = MockFriendsMessagesRepository()
    let service = MockFriendsMessagingService()
    let cachedMessage = makeMessage(id: "message-1", threadId: "thread-1")
    let refreshedMessage = FriendMessage(
      id: cachedMessage.id,
      threadId: cachedMessage.threadId,
      senderUserId: cachedMessage.senderUserId,
      messageType: cachedMessage.messageType,
      body: "Updated body",
      clientId: cachedMessage.clientId,
      replyToMessageId: cachedMessage.replyToMessageId,
      createdAt: cachedMessage.createdAt,
      editedAt: Date(timeIntervalSince1970: 1_700_000_100),
      deletedAt: nil
    )
    let cachedThread = makeThread(id: "thread-1", lastMessageId: cachedMessage.id)
    repository.messages[cachedMessage.id] = cachedMessage
    repository.threads[cachedThread.id] = cachedThread
    service.messageToReturn = refreshedMessage
    let prefetcher = FriendNotificationMessagePrefetcher(
      context: context,
      repository: repository,
      service: service
    )

    let outcome = await prefetcher.prefetchBackgroundMessage(
      threadId: "thread-1",
      messageId: cachedMessage.id
    )

    XCTAssertEqual(outcome, .newData)
    XCTAssertEqual(repository.savedMessages, [refreshedMessage])
    XCTAssertEqual(repository.messages[cachedMessage.id]?.body, "Updated body")
    XCTAssertEqual(service.fetchThreadSummaryCallCount, 0)
    XCTAssertEqual(service.fetchMessagePayloadCallCount, 1)
  }

  func testBackgroundPrefetchStoresMissingMessageAndThread() async {
    let context = MockPrefetchContext()
    let repository = MockFriendsMessagesRepository()
    let service = MockFriendsMessagingService()
    let message = makeMessage(id: "message-1", threadId: "thread-1")
    let thread = makeThread(id: "thread-1", lastMessageId: "message-1")
    service.messageToReturn = message
    service.threadToReturn = thread
    let notificationCenter = NotificationCenter()
    let prefetcher = FriendNotificationMessagePrefetcher(
      context: context,
      repository: repository,
      service: service,
      notificationCenter: notificationCenter
    )

    var updatedThreadId: String?
    let token = notificationCenter.addObserver(
      forName: .friendsThreadDidUpdate,
      object: nil,
      queue: nil
    ) { notification in
      updatedThreadId = notification.userInfo?["threadId"] as? String
    }
    defer { notificationCenter.removeObserver(token) }

    let outcome = await prefetcher.prefetchBackgroundMessage(
      threadId: thread.id,
      messageId: message.id
    )

    XCTAssertEqual(outcome, .newData)
    XCTAssertEqual(repository.savedThread?.id, thread.id)
    XCTAssertEqual(repository.savedMessages, [message])
    XCTAssertEqual(updatedThreadId, thread.id)
    XCTAssertEqual(service.fetchThreadSummaryCallCount, 1)
    XCTAssertEqual(service.fetchMessagePayloadCallCount, 1)
  }

  func testBackgroundPrefetchDoesNotFetchThreadWhenLocalThreadAlreadyCurrent() async {
    let context = MockPrefetchContext()
    let repository = MockFriendsMessagesRepository()
    let service = MockFriendsMessagingService()
    let thread = makeThread(id: "thread-1", lastMessageId: "message-1")
    let message = makeMessage(id: "message-1", threadId: "thread-1")
    repository.threads[thread.id] = thread
    service.messageToReturn = message
    let prefetcher = FriendNotificationMessagePrefetcher(
      context: context,
      repository: repository,
      service: service
    )

    let outcome = await prefetcher.prefetchBackgroundMessage(
      threadId: thread.id,
      messageId: message.id
    )

    XCTAssertEqual(outcome, .newData)
    XCTAssertEqual(service.fetchThreadSummaryCallCount, 0)
    XCTAssertEqual(service.fetchMessagePayloadCallCount, 1)
  }

  func testBackgroundPrefetchSkipsWhenImpersonating() async {
    let context = MockPrefetchContext(isImpersonating: true)
    let repository = MockFriendsMessagesRepository()
    let service = MockFriendsMessagingService()
    let prefetcher = FriendNotificationMessagePrefetcher(
      context: context,
      repository: repository,
      service: service
    )

    let outcome = await prefetcher.prefetchBackgroundMessage(
      threadId: "thread-1",
      messageId: "message-1"
    )

    XCTAssertEqual(outcome, .skipped(.impersonating))
    XCTAssertEqual(service.fetchMessagePayloadCallCount, 0)
  }

  func testBackgroundPrefetchReturnsFailedOnFetchError() async {
    let context = MockPrefetchContext()
    let repository = MockFriendsMessagesRepository()
    let service = MockFriendsMessagingService()
    service.fetchMessageError = TestError.failed
    let prefetcher = FriendNotificationMessagePrefetcher(
      context: context,
      repository: repository,
      service: service
    )

    let outcome = await prefetcher.prefetchBackgroundMessage(
      threadId: "thread-1",
      messageId: "message-1"
    )

    XCTAssertEqual(outcome, .failed)
  }

  private func makeThread(id: String, lastMessageId: String?) -> FriendThread {
    FriendThread(
      id: id,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: lastMessageId,
      lastMessageSenderId: "friend-1",
      lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000),
      lastMessageBody: "Hello",
      lastMessagePreviewKind: .text,
      lastMessageHasImage: false,
      unreadCount: 1,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  private func makeMessage(id: String, threadId: String) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: threadId,
      senderUserId: "friend-1",
      messageType: .user,
      body: "Hello",
      clientId: "client-\(id)",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
      editedAt: nil,
      deletedAt: nil
    )
  }
}

@MainActor
private final class MockPrefetchContext: FriendNotificationMessagePrefetchContextProviding {
  let isImpersonating: Bool
  let userId: String?

  init(
    isImpersonating: Bool = false,
    userId: String? = "viewer-1"
  ) {
    self.isImpersonating = isImpersonating
    self.userId = userId
  }

  func currentUserId() async -> String? {
    await Task.yield()
    return userId
  }
}

@MainActor
private final class MockFriendsMessagesRepository: FriendsMessagesRepositoryProviding {
  var threads: [String: FriendThread] = [:]
  var messages: [String: FriendMessage] = [:]
  var savedThread: FriendThread?
  var savedMessages: [FriendMessage] = []

  func getThread(id: String, viewerUserId _: String) -> FriendThread? {
    threads[id]
  }

  func getMessage(id: String, viewerUserId _: String) -> FriendMessage? {
    messages[id]
  }

  func saveThreads(_ threads: [FriendThread], for _: String) async {
    await Task.yield()
    for thread in threads {
      self.threads[thread.id] = thread
    }
  }

  func saveThread(_ thread: FriendThread, for _: String) async {
    await Task.yield()
    savedThread = thread
    threads[thread.id] = thread
  }

  func saveMessages(_ messages: [FriendMessage], in _: String, for _: String)
    async
  {
    await Task.yield()
    savedMessages = messages
    for message in messages {
      self.messages[message.id] = message
    }
  }

  func saveThreadState(_: FriendThreadState) async {
    await Task.yield()
  }

  func deleteMessage(id: String, viewerUserId _: String) async {
    await Task.yield()
    messages[id] = nil
  }

  func getMessagingSyncState(viewerUserId _: String, scope _: FriendMessagingSyncScope) async
    -> FriendMessagingSyncState?
  {
    await Task.yield()
    return nil
  }

  func saveMessagingSyncState(_: FriendMessagingSyncState) async {
    await Task.yield()
  }

  func deleteThread(id: String, viewerUserId _: String) async {
    await Task.yield()
    threads[id] = nil
  }
}

@MainActor
private final class MockFriendsMessagingService: FriendsMessagingServiceProviding {
  var messageToReturn = FriendMessage(
    id: "message-1",
    threadId: "thread-1",
    senderUserId: "friend-1",
    messageType: .user,
    body: "Hello",
    clientId: "client-1",
    replyToMessageId: nil,
    createdAt: Date(timeIntervalSince1970: 1_700_000_001),
    editedAt: nil,
    deletedAt: nil
  )
  var threadToReturn = FriendThread(
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
    lastMessageAt: Date(timeIntervalSince1970: 1_700_000_000),
    lastMessageBody: "Hello",
    lastMessagePreviewKind: .text,
    lastMessageHasImage: false,
    unreadCount: 1,
    muted: false,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
  var fetchMessageError: Error?
  var fetchThreadSummaryCallCount = 0
  var fetchMessagePayloadCallCount = 0

  func fetchThreadSummary(threadId _: String) async -> FriendThread {
    await Task.yield()
    fetchThreadSummaryCallCount += 1
    return threadToReturn
  }

  func fetchMessagePayload(messageId _: String) async throws -> FriendMessage {
    await Task.yield()
    fetchMessagePayloadCallCount += 1
    if let fetchMessageError {
      throw fetchMessageError
    }
    return messageToReturn
  }

  func getOrCreateDirectThread(otherUserId _: String) async throws -> FriendThread {
    await Task.yield()
    XCTFail(
      "Unexpected call to getOrCreateDirectThread in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func listMyThreads(limit _: Int, before _: FriendThreadCursor?) async throws -> [FriendThread] {
    await Task.yield()
    XCTFail("Unexpected call to listMyThreads in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func listThreadMessages(
    threadId _: String,
    limit _: Int,
    before _: FriendMessageCursor?
  ) async throws -> [FriendMessage] {
    await Task.yield()
    XCTFail("Unexpected call to listThreadMessages in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func sendMessage(
    threadId _: String,
    clientId _: String,
    body _: String?,
    replyToMessageId _: String?,
    attachments _: [FriendOutgoingAttachment],
    metadataData _: Data?
  ) async throws -> FriendMessage {
    await Task.yield()
    XCTFail("Unexpected call to sendMessage in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func queueThreadTypingNotification(threadId _: String) async throws -> Bool {
    await Task.yield()
    XCTFail(
      "Unexpected call to queueThreadTypingNotification in FriendNotificationMessagePrefetcherTests"
    )
    throw TestError.failed
  }
  func editMessage(messageId _: String, body _: String) async throws -> FriendMessage {
    await Task.yield()
    XCTFail("Unexpected call to editMessage in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func deleteMessage(messageId _: String) async throws -> FriendThread {
    await Task.yield()
    XCTFail("Unexpected call to deleteMessage in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func markThreadRead(threadId _: String, throughMessageId _: String) async throws
    -> FriendThreadState
  {
    await Task.yield()
    XCTFail("Unexpected call to markThreadRead in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func setThreadMuted(threadId _: String, muted _: Bool) async throws -> FriendThreadState {
    await Task.yield()
    XCTFail("Unexpected call to setThreadMuted in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func fetchUnreadDirectMessageCount(userId _: String) async throws -> Int {
    await Task.yield()
    XCTFail(
      "Unexpected call to fetchUnreadDirectMessageCount in FriendNotificationMessagePrefetcherTests"
    )
    throw TestError.failed
  }
  func fetchThreadState(threadId _: String, userId _: String) async throws -> FriendThreadState? {
    await Task.yield()
    XCTFail("Unexpected call to fetchThreadState in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func listThreadStates(threadId _: String) async throws -> [FriendThreadState] {
    await Task.yield()
    XCTFail("Unexpected call to listThreadStates in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func toggleMessageReaction(
    messageId _: String,
    emoji _: String,
    attachmentId _: String?
  ) async throws -> FriendMessage {
    await Task.yield()
    XCTFail("Unexpected call to toggleMessageReaction in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func createAbuseReport(
    threadId _: String,
    reportedUserId _: String,
    messageId _: String?,
    reason _: FriendAbuseReportReason
  ) async throws {
    await Task.yield()
    XCTFail("Unexpected call to createAbuseReport in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func blockUserPair(otherUserId _: String) async throws {
    await Task.yield()
    XCTFail("Unexpected call to blockUserPair in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func uploadImageAttachment(threadId _: String, image _: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  {
    await Task.yield()
    XCTFail("Unexpected call to uploadImageAttachment in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func downloadAttachmentData(path _: String) async throws -> Data {
    await Task.yield()
    XCTFail("Unexpected call to downloadAttachmentData in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }

  func fetchInboxSyncSnapshotV2(limit _: Int, before _: FriendThreadCursor?) async throws
    -> FriendInboxSyncSnapshot
  {
    await Task.yield()
    throw TestError.failed
  }

  func listInboxEventsV2(afterVersion _: Int64, limit _: Int) async throws
    -> FriendInboxSyncEventsPage
  {
    await Task.yield()
    throw TestError.failed
  }

  func listThreadEventsV2(threadId _: String, afterVersion _: Int64, limit _: Int) async throws
    -> FriendThreadSyncEventsPage
  {
    await Task.yield()
    throw TestError.failed
  }

  func listThreadMessagesV2(threadId _: String, limit _: Int, before _: FriendMessageCursor?)
    async throws -> FriendThreadMessagesPage
  {
    await Task.yield()
    throw TestError.failed
  }

  func fetchThreadSyncSnapshotV2(threadId: String, messageLimit _: Int) async throws
    -> FriendThreadSyncSnapshot
  {
    let thread = await fetchThreadSummary(threadId: threadId)
    return FriendThreadSyncSnapshot(
      thread: thread,
      viewerState: FriendThreadState(
        threadId: threadId,
        userId: "viewer-1",
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: false,
        updatedAt: Date()
      ),
      counterpartPresence: nil,
      messages: [],
      nextCursor: nil,
      snapshotVersion: 0,
      retainedFromVersion: 0,
      hasMore: false
    )
  }

  func fetchMessageSyncPayloadV2(messageId: String) async throws -> FriendMessage {
    try await fetchMessagePayload(messageId: messageId)
  }
}

private enum TestError: Error {
  case failed
}
