import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class FriendsMessageOutboxTests: XCTestCase {
  private let viewerId = "viewer-1"

  func testDrainSendsQueuedMessagesFromThreadsThatAreNotOpen() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    let outbox = makeOutbox(service: service, repository: repository)

    await queue(makeMessage(id: "local-a1", threadId: "thread-a", second: 1), in: repository)
    await queue(makeMessage(id: "local-b1", threadId: "thread-b", second: 2), in: repository)
    await queue(makeMessage(id: "local-a2", threadId: "thread-a", second: 3), in: repository)

    await outbox.drain(userId: viewerId)

    XCTAssertEqual(service.sentClientIds, ["client-local-a1", "client-local-b1", "client-local-a2"])
    XCTAssertEqual(
      repository.getMessages(threadId: "thread-a", viewerUserId: viewerId).map(\.sendState),
      [.sent, .sent]
    )
    XCTAssertEqual(
      repository.getMessages(threadId: "thread-b", viewerUserId: viewerId).map(\.sendState),
      [.sent]
    )
    XCTAssertTrue(repository.getQueuedMessages(viewerUserId: viewerId).isEmpty)
  }

  func testDrainSkipsMessageAnotherSenderOwnsAndKeepsThreadOrder() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    let outbox = makeOutbox(service: service, repository: repository)

    await queue(makeMessage(id: "local-a1", threadId: "thread-a", second: 1), in: repository)
    await queue(makeMessage(id: "local-a2", threadId: "thread-a", second: 2), in: repository)
    await queue(makeMessage(id: "local-b1", threadId: "thread-b", second: 3), in: repository)

    // The open thread is sending local-a1, so the drain must not send it or the message after it.
    XCTAssertTrue(outbox.claim("local-a1"))
    await outbox.drain(userId: viewerId)
    XCTAssertEqual(service.sentClientIds, ["client-local-b1"])

    outbox.release("local-a1")
    await outbox.drain(userId: viewerId)
    XCTAssertEqual(service.sentClientIds, ["client-local-b1", "client-local-a1", "client-local-a2"])
  }

  func testOverlappingDrainsDoNotSendTheSameMessageTwice() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    service.sendDelay = .milliseconds(100)
    let outbox = makeOutbox(service: service, repository: repository)

    await queue(makeMessage(id: "local-a1", threadId: "thread-a", second: 1), in: repository)

    async let first: Void = outbox.drain(userId: viewerId)
    async let second: Void = outbox.drain(userId: viewerId)
    _ = await (first, second)

    XCTAssertEqual(service.sentClientIds, ["client-local-a1"])
  }

  func testUnclassifiedFailureFailsAfterThreeAttempts() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    service.sendError = FriendsMessagingServiceError.networkError(
      underlying: URLError(.badServerResponse))
    let outbox = makeOutbox(service: service, repository: repository)
    await queue(makeMessage(id: "local-a1", threadId: "thread-a", second: 1), in: repository)

    await outbox.drain(userId: viewerId)
    await outbox.drain(userId: viewerId)
    XCTAssertEqual(repository.getMessage(id: "local-a1", viewerUserId: viewerId)?.sendState, .sending)

    await outbox.drain(userId: viewerId)
    let message = try XCTUnwrap(repository.getMessage(id: "local-a1", viewerUserId: viewerId))
    XCTAssertEqual(message.sendState, .failed)
    XCTAssertEqual(message.failureMessage, String(localized: .friendsChatSendFailed))

    await outbox.drain(userId: viewerId)
    XCTAssertEqual(service.sentClientIds.count, 3)
  }

  func testOfflineFailureStaysQueuedWithoutCountingAttempts() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    service.sendError = FriendsMessagingServiceError.networkError(
      underlying: URLError(.notConnectedToInternet))
    let outbox = makeOutbox(service: service, repository: repository)
    await queue(makeMessage(id: "local-a1", threadId: "thread-a", second: 1), in: repository)
    await queue(makeMessage(id: "local-b1", threadId: "thread-b", second: 2), in: repository)

    for _ in 0..<5 {
      await outbox.drain(userId: viewerId)
    }

    let message = try XCTUnwrap(repository.getMessage(id: "local-a1", viewerUserId: viewerId))
    XCTAssertEqual(message.sendState, .sending)
    XCTAssertEqual(message.failureMessage, String(localized: .friendsChatWaitingForNetwork))
    // Each drain stops at the first offline error instead of trying every message.
    XCTAssertEqual(service.sentClientIds.count, 5)
  }

  func testServerRejectionFailsImmediately() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    service.sendError = FriendsMessagingServiceError.httpError(statusCode: 400, message: "No")
    let outbox = makeOutbox(service: service, repository: repository)
    await queue(makeMessage(id: "local-a1", threadId: "thread-a", second: 1), in: repository)

    await outbox.drain(userId: viewerId)

    XCTAssertEqual(repository.getMessage(id: "local-a1", viewerUserId: viewerId)?.sendState, .failed)
  }

  func testDeletingQueuedMessageRemovesItAndItsPendingBytes() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    let store = makePendingStore()
    let outbox = makeOutbox(service: service, repository: repository, store: store)
    let attachment = makePendingAttachment(id: "image-1")
    let message = makeMessage(
      id: "local-a1", threadId: "thread-a", second: 1, attachments: [attachment])
    store.save(ImageAttachment(id: "image-1", data: Data([1, 2, 3])))
    await queue(message, in: repository)

    let viewModel = FriendsThreadViewModel(
      route: makeRoute(threadId: "thread-a"),
      viewerUserId: viewerId,
      service: service,
      repository: repository,
      realtimeCoordinator: FriendsMessagingRealtimeCoordinator(
        service: service, repository: repository),
      outbox: outbox
    )

    await viewModel.deleteMessage(messageId: "local-a1")

    XCTAssertNil(repository.getMessage(id: "local-a1", viewerUserId: viewerId))
    XCTAssertNil(store.load(id: "image-1", mediaType: "image/jpeg"))
    XCTAssertTrue(service.sentClientIds.isEmpty)
    XCTAssertNil(service.deletedMessageId)
  }

  func testPendingBytesSurviveCacheEvictionAndAreDeletedAfterSend() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    let store = makePendingStore()
    let outbox = makeOutbox(service: service, repository: repository, store: store)
    let attachment = makePendingAttachment(id: "image-2")
    // The bytes are only in the durable store, as if ImageCache had dropped its copy.
    store.save(ImageAttachment(id: "image-2", data: Data([9, 8, 7])))
    await queue(
      makeMessage(id: "local-a1", threadId: "thread-a", second: 1, attachments: [attachment]),
      in: repository
    )

    await outbox.drain(userId: viewerId)

    XCTAssertEqual(service.uploadedImages.map(\.data), [Data([9, 8, 7])])
    XCTAssertEqual(repository.getMessage(id: "local-a1", viewerUserId: viewerId)?.sendState, .sent)
    XCTAssertNil(store.load(id: "image-2", mediaType: "image/jpeg"))
  }

  func testMissingPendingBytesFailTheMessage() async throws {
    let repository = try makeRepository()
    let service = OutboxStubService()
    let outbox = makeOutbox(service: service, repository: repository)
    await queue(
      makeMessage(
        id: "local-a1", threadId: "thread-a", second: 1,
        attachments: [makePendingAttachment(id: "image-gone")]),
      in: repository
    )

    await outbox.drain(userId: viewerId)

    XCTAssertEqual(repository.getMessage(id: "local-a1", viewerUserId: viewerId)?.sendState, .failed)
    XCTAssertTrue(service.sentClientIds.isEmpty)
  }

  func testCanDeleteAllowsQueuedMessages() {
    let queued = makeMessage(id: "local-a1", threadId: "thread-a", second: 1)
    XCTAssertTrue(queued.canDelete(viewerUserId: viewerId))
  }

  func testConnectivityClassificationOnlyTreatsOfflineErrorsAsOffline() {
    XCTAssertTrue(FriendsMessageOutbox.isConnectivityError(URLError(.notConnectedToInternet)))
    XCTAssertTrue(
      FriendsMessageOutbox.isConnectivityError(
        FriendsMessagingServiceError.networkError(underlying: URLError(.timedOut))))
    XCTAssertFalse(FriendsMessageOutbox.isConnectivityError(URLError(.badServerResponse)))
    XCTAssertFalse(
      FriendsMessageOutbox.isConnectivityError(
        FriendsMessagingServiceError.networkError(underlying: URLError(.cannotParseResponse))))
    XCTAssertFalse(
      FriendsMessageOutbox.isConnectivityError(
        FriendsMessagingServiceError.httpError(statusCode: 500, message: nil)))
  }

  func testNetworkErrorDescriptionDoesNotEmbedSystemText() {
    let error = FriendsMessagingServiceError.networkError(underlying: URLError(.timedOut))
    XCTAssertEqual(error.errorDescription, String(localized: .commonErrorGeneric))
  }

  // MARK: - Helpers

  private func makeOutbox(
    service: OutboxStubService,
    repository: FriendsMessagesRepository,
    store: FriendsPendingAttachmentStore? = nil
  ) -> FriendsMessageOutbox {
    FriendsMessageOutbox(
      service: service,
      repository: repository,
      pendingStore: store ?? makePendingStore()
    )
  }

  private func makePendingStore() -> FriendsPendingAttachmentStore {
    FriendsPendingAttachmentStore(
      directory: FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true))
  }

  private func makeRepository() throws -> FriendsMessagesRepository {
    let schema = Schema([
      LocalPendingFriendComposerDraft.self,
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

  private func queue(_ message: FriendMessage, in repository: FriendsMessagesRepository) async {
    await repository.saveOptimisticMessage(message, in: message.threadId, for: viewerId)
  }

  private func makeMessage(
    id: String,
    threadId: String,
    second: TimeInterval,
    attachments: [FriendMessageAttachment] = []
  ) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: threadId,
      senderUserId: viewerId,
      messageType: .user,
      body: "Body \(id)",
      clientId: "client-\(id)",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000 + second),
      editedAt: nil,
      deletedAt: nil,
      attachments: attachments,
      sendState: .sending,
      failureMessage: nil
    )
  }

  private func makePendingAttachment(id: String) -> FriendMessageAttachment {
    FriendMessageAttachment(
      id: id,
      attachmentIndex: 0,
      kind: .image,
      storageBucket: "message-attachments",
      storagePath: FriendsMessageOutbox.pendingAttachmentStoragePath(for: id),
      mimeType: "image/jpeg",
      byteSize: 3,
      width: nil,
      height: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  private func makeRoute(threadId: String) -> FriendChatRoute {
    FriendChatRoute(
      thread: FriendThread(
        id: threadId,
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
      ),
      fallbackDisplayName: "Friend",
      fallbackAvatarUrl: nil
    )
  }
}

private enum OutboxStubError: Error {
  case unsupported
}

// The protocol requires async, and most stub methods have nothing to await.
// swiftlint:disable async_without_await
@MainActor
private final class OutboxStubService: FriendsMessagingServiceProviding {
  var sendError: Error?
  var sendDelay: Duration?
  private(set) var sentClientIds: [String] = []
  private(set) var uploadedImages: [ImageAttachment] = []
  private(set) var deletedMessageId: String?

  func sendMessage(
    threadId: String,
    clientId: String,
    body: String?,
    replyToMessageId _: String?,
    attachments _: [FriendOutgoingAttachment],
    metadataData _: Data?
  ) async throws -> FriendMessage {
    sentClientIds.append(clientId)
    if let sendDelay {
      try? await Task.sleep(for: sendDelay)
    }
    if let sendError {
      throw sendError
    }
    return FriendMessage(
      id: "server-\(clientId)",
      threadId: threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: body,
      clientId: clientId,
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_500),
      editedAt: nil,
      deletedAt: nil
    )
  }

  func uploadImageAttachment(threadId _: String, image: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  {
    uploadedImages.append(image)
    return FriendOutgoingAttachment(
      attachmentId: image.id,
      storagePath: "thread/viewer-1/\(image.id).jpg",
      mimeType: image.mediaType,
      byteSize: Int64(image.data.count),
      width: nil,
      height: nil
    )
  }

  func deleteMessage(messageId: String) async throws -> FriendThread {
    deletedMessageId = messageId
    throw OutboxStubError.unsupported
  }

  func getOrCreateDirectThread(otherUserId _: String) async throws -> FriendThread {
    throw OutboxStubError.unsupported
  }

  func listMyThreads(limit _: Int, before _: FriendThreadCursor?) async throws -> [FriendThread] {
    []
  }

  func fetchInboxSyncSnapshotV2(limit _: Int, before _: FriendThreadCursor?) async throws
    -> FriendInboxSyncSnapshot
  {
    throw OutboxStubError.unsupported
  }

  func listInboxEventsV2(afterVersion _: Int64, limit _: Int) async throws
    -> FriendInboxSyncEventsPage
  {
    throw OutboxStubError.unsupported
  }

  func listThreadMessages(threadId _: String, limit _: Int, before _: FriendMessageCursor?)
    async throws -> [FriendMessage]
  {
    []
  }

  func listThreadMessagesV2(threadId _: String, limit _: Int, before _: FriendMessageCursor?)
    async throws -> FriendThreadMessagesPage
  {
    throw OutboxStubError.unsupported
  }

  func fetchThreadSyncSnapshotV2(threadId _: String, messageLimit _: Int) async throws
    -> FriendThreadSyncSnapshot
  {
    throw OutboxStubError.unsupported
  }

  func listThreadEventsV2(threadId _: String, afterVersion _: Int64, limit _: Int) async throws
    -> FriendThreadSyncEventsPage
  {
    throw OutboxStubError.unsupported
  }

  func listThreadStates(threadId _: String) async throws -> [FriendThreadState] {
    []
  }

  func editMessage(messageId _: String, body _: String) async throws -> FriendMessage {
    throw OutboxStubError.unsupported
  }

  func markThreadRead(threadId _: String, throughMessageId _: String) async throws
    -> FriendThreadState
  {
    throw OutboxStubError.unsupported
  }

  func setThreadMuted(threadId _: String, muted _: Bool) async throws -> FriendThreadState {
    throw OutboxStubError.unsupported
  }

  func queueThreadTypingNotification(threadId _: String) async throws -> Bool {
    false
  }

  func fetchUnreadDirectMessageCount(userId _: String) async throws -> Int {
    0
  }

  func fetchThreadSummary(threadId _: String) async throws -> FriendThread {
    throw OutboxStubError.unsupported
  }

  func fetchThreadState(threadId _: String, userId _: String) async throws -> FriendThreadState? {
    nil
  }

  func fetchMessagePayload(messageId _: String) async throws -> FriendMessage {
    throw OutboxStubError.unsupported
  }

  func fetchMessageSyncPayloadV2(messageId _: String) async throws -> FriendMessage {
    throw OutboxStubError.unsupported
  }

  func toggleMessageReaction(messageId _: String, emoji _: String, attachmentId _: String?)
    async throws -> FriendMessage
  {
    throw OutboxStubError.unsupported
  }

  func createAbuseReport(
    threadId _: String,
    reportedUserId _: String,
    messageId _: String?,
    reason _: FriendAbuseReportReason
  ) async throws {
    throw OutboxStubError.unsupported
  }

  func blockUserPair(otherUserId _: String) async throws {
    throw OutboxStubError.unsupported
  }

  func downloadAttachmentData(path _: String) async throws -> Data {
    Data()
  }
}
// swiftlint:enable async_without_await
