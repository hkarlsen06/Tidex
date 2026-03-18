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

  func testBackgroundPrefetchSkipsAlreadyCachedMessage() async {
    let context = MockPrefetchContext()
    let repository = MockFriendsMessagesRepository()
    let service = MockFriendsMessagingService()
    let cachedMessage = makeMessage(id: "message-1", threadId: "thread-1")
    repository.messages[cachedMessage.id] = cachedMessage
    let prefetcher = FriendNotificationMessagePrefetcher(
      context: context,
      repository: repository,
      service: service
    )

    let outcome = await prefetcher.prefetchBackgroundMessage(
      threadId: "thread-1",
      messageId: cachedMessage.id
    )

    XCTAssertEqual(outcome, .skipped(.alreadyCached))
    XCTAssertEqual(service.fetchMessagePayloadCallCount, 0)
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

  func testBackgroundPrefetchSkipsWhenBiometricLocked() async {
    let context = MockPrefetchContext(isBiometricLocked: true)
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

    XCTAssertEqual(outcome, .skipped(.biometricLocked))
    XCTAssertEqual(service.fetchMessagePayloadCallCount, 0)
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
  let isBiometricLocked: Bool
  let isImpersonating: Bool
  let userId: String?

  init(
    isBiometricLocked: Bool = false,
    isImpersonating: Bool = false,
    userId: String? = "viewer-1"
  ) {
    self.isBiometricLocked = isBiometricLocked
    self.isImpersonating = isImpersonating
    self.userId = userId
  }

  func currentUserId() async -> String? {
    await Task.yield()
    userId
  }
}

@MainActor
private final class MockFriendsMessagesRepository: FriendsMessagesRepositoryProviding {
  var threads: [String: FriendThread] = [:]
  var messages: [String: FriendMessage] = [:]
  var savedThread: FriendThread?
  var savedMessages: [FriendMessage] = []

  func getThread(id: String, viewerUserId: String) -> FriendThread? {
    threads[id]
  }

  func getMessage(id: String, viewerUserId: String) -> FriendMessage? {
    messages[id]
  }

  func saveThreads(_ threads: [FriendThread], for viewerUserId: String) async {
    await Task.yield()
    for thread in threads {
      self.threads[thread.id] = thread
    }
  }

  func saveThread(_ thread: FriendThread, for viewerUserId: String) async {
    await Task.yield()
    savedThread = thread
    threads[thread.id] = thread
  }

  func saveMessages(_ messages: [FriendMessage], in threadId: String, for viewerUserId: String)
    async
  {
    await Task.yield()
    savedMessages = messages
    for message in messages {
      self.messages[message.id] = message
    }
  }

  func saveThreadState(_ state: FriendThreadState) async {
    await Task.yield()
  }

  func deleteMessage(id: String, viewerUserId: String) async {
    await Task.yield()
    messages[id] = nil
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

  func fetchThreadSummary(threadId: String) async throws -> FriendThread {
    await Task.yield()
    fetchThreadSummaryCallCount += 1
    return threadToReturn
  }

  func fetchMessagePayload(messageId: String) async throws -> FriendMessage {
    await Task.yield()
    fetchMessagePayloadCallCount += 1
    if let fetchMessageError {
      throw fetchMessageError
    }
    return messageToReturn
  }

  func getOrCreateDirectThread(otherUserId: String) async throws -> FriendThread {
    await Task.yield()
    XCTFail(
      "Unexpected call to getOrCreateDirectThread in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func listMyThreads(limit: Int, before cursor: FriendThreadCursor?) async throws -> [FriendThread]
  {
    await Task.yield()
    XCTFail("Unexpected call to listMyThreads in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func listThreadMessages(
    threadId: String,
    limit: Int,
    before cursor: FriendMessageCursor?
  ) async throws -> [FriendMessage] {
    await Task.yield()
    XCTFail("Unexpected call to listThreadMessages in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func sendMessage(
    threadId: String,
    clientId: String,
    body: String?,
    replyToMessageId: String?,
    attachments: [FriendOutgoingAttachment],
    metadataData: Data?
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
  func editMessage(messageId: String, body: String) async throws -> FriendMessage {
    await Task.yield()
    XCTFail("Unexpected call to editMessage in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func deleteMessage(messageId: String) async throws -> FriendThread {
    await Task.yield()
    XCTFail("Unexpected call to deleteMessage in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func markThreadRead(threadId: String, throughMessageId: String) async throws -> FriendThreadState
  {
    await Task.yield()
    XCTFail("Unexpected call to markThreadRead in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func setThreadMuted(threadId: String, muted: Bool) async throws -> FriendThreadState {
    await Task.yield()
    XCTFail("Unexpected call to setThreadMuted in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func fetchUnreadDirectMessageCount(userId: String) async throws -> Int {
    await Task.yield()
    XCTFail(
      "Unexpected call to fetchUnreadDirectMessageCount in FriendNotificationMessagePrefetcherTests"
    )
    throw TestError.failed
  }
  func fetchThreadState(threadId: String, userId: String) async throws -> FriendThreadState? {
    await Task.yield()
    XCTFail("Unexpected call to fetchThreadState in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func toggleMessageReaction(messageId: String, emoji: String) async throws -> FriendMessage {
    await Task.yield()
    XCTFail("Unexpected call to toggleMessageReaction in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func createAbuseReport(
    threadId: String,
    reportedUserId: String,
    messageId: String?,
    reason: FriendAbuseReportReason
  ) async throws {
    await Task.yield()
    XCTFail("Unexpected call to createAbuseReport in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func blockUserPair(otherUserId: String) async throws {
    await Task.yield()
    XCTFail("Unexpected call to blockUserPair in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func uploadImageAttachment(threadId: String, image: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  {
    await Task.yield()
    XCTFail("Unexpected call to uploadImageAttachment in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
  func downloadAttachmentData(path: String) async throws -> Data {
    await Task.yield()
    XCTFail("Unexpected call to downloadAttachmentData in FriendNotificationMessagePrefetcherTests")
    throw TestError.failed
  }
}

private enum TestError: Error {
  case failed
}
