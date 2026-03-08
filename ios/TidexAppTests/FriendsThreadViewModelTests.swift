import SwiftData
import XCTest

@testable import Tidex

@MainActor
final class FriendsThreadViewModelTests: XCTestCase {
  func testSendDraftPersistsReturnedMessageOnSuccess() async throws {
    let repository = try makeRepository()
    let route = FriendChatRoute(
      thread: FriendThread(
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
      ),
      fallbackDisplayName: "Friend",
      fallbackAvatarUrl: nil
    )

    let mockService = MockFriendsMessagingService()
    mockService.sentMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    mockService.threadSummary = FriendThread(
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
      lastMessageAt: Date(timeIntervalSince1970: 1_700_000_001),
      lastMessageBody: "Hello",
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    mockService.threadMessages = [try XCTUnwrap(mockService.sentMessage)]

    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Hello"
    await viewModel.sendDraft()

    XCTAssertEqual(viewModel.draft, "")
    XCTAssertNil(viewModel.sendErrorMessage)
    XCTAssertEqual(repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1").count, 1)
    XCTAssertEqual(
      repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1").first?.body, "Hello")
  }

  func testSendDraftRestoresDraftAndShowsErrorOnFailure() async throws {
    let repository = try makeRepository()
    let route = FriendChatRoute(
      thread: FriendThread(
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
      ),
      fallbackDisplayName: "Friend",
      fallbackAvatarUrl: nil
    )

    let mockService = MockFriendsMessagingService()
    mockService.sendError = FriendsMessagingServiceError.networkError(underlying: TestError.failed)

    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Hello again"
    await viewModel.sendDraft()

    XCTAssertEqual(viewModel.draft, "Hello again")
    XCTAssertEqual(viewModel.sendErrorMessage, String(localized: .friendsChatSendFailed))
    XCTAssertTrue(repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1").isEmpty)
  }

  private func makeRepository() throws -> FriendsMessagesRepository {
    let schema = Schema([
      LocalThread.self,
      LocalThreadState.self,
      LocalMessage.self,
      LocalMessageAttachment.self,
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
}

private enum TestError: Error {
  case failed
}

@MainActor
private final class MockFriendsMessagingService: FriendsMessagingServiceProviding {
  var sentMessage: FriendMessage?
  var threadSummary: FriendThread?
  var threadMessages: [FriendMessage] = []
  var sendError: Error?

  func getOrCreateDirectThread(otherUserId _: String) async throws -> FriendThread {
    await Task.yield()
    throw TestError.failed
  }

  func listMyThreads(limit _: Int, before _: FriendThreadCursor?) async throws -> [FriendThread] {
    await Task.yield()
    []
  }

  func listThreadMessages(threadId _: String, limit _: Int, before _: FriendMessageCursor?)
    async throws -> [FriendMessage]
  {
    await Task.yield()
    threadMessages
  }

  func sendMessage(
    threadId _: String,
    clientId _: String,
    body _: String?,
    attachments _: [FriendOutgoingAttachment]
  ) async throws -> FriendMessage {
    await Task.yield()
    if let sendError {
      throw sendError
    }
    return try XCTUnwrap(sentMessage)
  }

  func markThreadRead(threadId _: String, throughMessageId _: String) async throws
    -> FriendThreadState
  {
    await Task.yield()
    FriendThreadState(
      threadId: "thread-1",
      userId: "viewer-1",
      lastReadMessageId: nil,
      lastReadAt: nil,
      muted: false,
      updatedAt: Date()
    )
  }

  func setThreadMuted(threadId _: String, muted _: Bool) async throws -> FriendThreadState {
    await Task.yield()
    FriendThreadState(
      threadId: "thread-1",
      userId: "viewer-1",
      lastReadMessageId: nil,
      lastReadAt: nil,
      muted: false,
      updatedAt: Date()
    )
  }

  func fetchThreadSummary(threadId _: String) async throws -> FriendThread {
    await Task.yield()
    try XCTUnwrap(threadSummary)
  }

  func fetchMessagePayload(messageId _: String) async throws -> FriendMessage {
    await Task.yield()
    try XCTUnwrap(sentMessage)
  }
}
