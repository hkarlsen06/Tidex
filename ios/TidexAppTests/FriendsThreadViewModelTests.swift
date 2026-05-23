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
    let didSend = await viewModel.sendDraft()

    XCTAssertTrue(didSend)
    XCTAssertEqual(viewModel.draft, "")
    XCTAssertNil(viewModel.sendErrorMessage)
    XCTAssertEqual(repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1").count, 1)
    XCTAssertEqual(
      repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1").first?.body, "Hello")
  }

  func testSendDraftShowsOptimisticMessageAfterSettleWindowForSlowSend() async throws {
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
    mockService.sendDelay = .milliseconds(250)
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
    let sendTask = Task {
      await viewModel.sendDraft()
    }

    try? await Task.sleep(for: .milliseconds(180))

    let optimisticMessages = repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1")
    XCTAssertEqual(optimisticMessages.count, 1)
    XCTAssertEqual(optimisticMessages.first?.sendState, .sending)
    XCTAssertTrue(optimisticMessages.first?.id.hasPrefix("local-") ?? false)
    XCTAssertEqual(viewModel.draft, "")

    let didSend = await sendTask.value
    XCTAssertTrue(didSend)

    try? await Task.sleep(for: .milliseconds(150))
    let confirmedMessages = repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1")
    XCTAssertEqual(confirmedMessages.count, 1)
    XCTAssertEqual(confirmedMessages.first?.id, "message-1")
    XCTAssertEqual(confirmedMessages.first?.sendState, .sent)
  }

  func testSendDraftBlocksTooLongMessagesBeforeRPC() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = makeThread()
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

    viewModel.draft = String(repeating: "a", count: 2001)

    XCTAssertEqual(viewModel.draftCharacterCount, 2001)
    XCTAssertEqual(
      viewModel.composerValidationMessage,
      String(localized: "friends.chat.composer.message_too_long", table: "Localizable")
        .replacingOccurrences(of: "{limit}", with: "2000")
    )

    let didSend = await viewModel.sendDraft()

    XCTAssertFalse(didSend)
    XCTAssertEqual(mockService.sendMessageCallCount, 0)
    XCTAssertEqual(viewModel.draft, String(repeating: "a", count: 2001))
    XCTAssertTrue(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").isEmpty)
  }

  func testSendDraftRecoversMissingViewerUserIdBeforeSavingOutgoingMessage() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.sentMessage = FriendMessage(
      id: "message-1",
      threadId: route.threadId,
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
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator,
      viewerUserIdResolver: { "viewer-1" }
    )

    viewModel.draft = "Hello"
    let didSend = await viewModel.sendDraft()

    XCTAssertTrue(didSend)
    XCTAssertEqual(viewModel.viewerUserId, "viewer-1")
    XCTAssertEqual(repository.getMessages(threadId: route.threadId, viewerUserId: "").count, 0)
    XCTAssertEqual(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").count, 1)
    XCTAssertEqual(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").first?
        .senderUserId,
      "viewer-1"
    )
  }

  func testLoadIfNeededDoesNotDuplicateWorkWhileViewerIdResolutionIsInFlight() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let message = FriendMessage(
      id: "message-1",
      threadId: route.threadId,
      senderUserId: route.counterpartUserId,
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
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: message.id,
      lastMessageSenderId: message.senderUserId,
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageHasImage: false,
      unreadCount: 1,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    mockService.threadMessages = [message]
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()
    var viewerUserIdResolverCallCount = 0

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator,
      viewerUserIdResolver: {
        viewerUserIdResolverCallCount += 1
        try? await Task.sleep(for: .milliseconds(100))
        return "viewer-1"
      }
    )

    let firstLoadTask = Task { await viewModel.loadIfNeeded() }
    let secondLoadTask = Task { await viewModel.loadIfNeeded() }
    _ = await (firstLoadTask.value, secondLoadTask.value)

    XCTAssertEqual(viewerUserIdResolverCallCount, 1)
    XCTAssertEqual(realtimeCoordinator.startThreadSubscriptionCallCount, 1)
    XCTAssertEqual(viewModel.viewerUserId, "viewer-1")
    XCTAssertEqual(viewModel.messages.map(\.id), [message.id])
  }

  func testLoadIfNeededRestartsRealtimeAfterInitialLoad() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let message = FriendMessage(
      id: "message-restart-1",
      threadId: route.threadId,
      senderUserId: route.counterpartUserId,
      messageType: .user,
      body: "Welcome back",
      clientId: "client-restart-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: message.id,
      lastMessageSenderId: message.senderUserId,
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageHasImage: false,
      unreadCount: 1,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    mockService.threadMessages = [message]
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()
    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.loadIfNeeded()
    SensitiveContentPresentationState.shared.setVisibleContext(nil)
    await viewModel.stopRealtime()
    await viewModel.loadIfNeeded()

    XCTAssertEqual(realtimeCoordinator.startThreadSubscriptionCallCount, 2)
    XCTAssertEqual(realtimeCoordinator.stopThreadSubscriptionCallCount, 1)
  }

  func testSendDraftBlocksMessagesThatExceedBackendCodePointLimit() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = makeThread()
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

    let draft = String(repeating: "👨‍👩‍👧‍👦", count: 300)
    let expectedBackendCount =
      draft
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .unicodeScalars.count

    XCTAssertTrue(expectedBackendCount > 2000)

    viewModel.draft = draft

    XCTAssertEqual(viewModel.draftCharacterCount, expectedBackendCount)
    XCTAssertEqual(
      viewModel.composerValidationMessage,
      String(localized: "friends.chat.composer.message_too_long", table: "Localizable")
        .replacingOccurrences(of: "{limit}", with: "2000")
    )

    let didSend = await viewModel.sendDraft()

    XCTAssertFalse(didSend)
    XCTAssertEqual(mockService.sendMessageCallCount, 0)
    XCTAssertEqual(viewModel.draft, draft)
    XCTAssertTrue(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").isEmpty)
  }

  func testSendDraftWithReplyTargetPersistsReturnedReplyReference() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let repliedToMessage = FriendMessage(
      id: "message-0",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: "Original",
      clientId: "client-0",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )

    let mockService = MockFriendsMessagingService()
    mockService.sentMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Reply",
      clientId: "client-1",
      replyToMessageId: repliedToMessage.id,
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
      lastMessageBody: "Reply",
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    mockService.threadMessages = [repliedToMessage, try XCTUnwrap(mockService.sentMessage)]

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

    viewModel.setReplyTarget(repliedToMessage)
    viewModel.draft = "Reply"
    let didSend = await viewModel.sendDraft()

    XCTAssertTrue(didSend)
    XCTAssertEqual(mockService.lastSentReplyToMessageId, repliedToMessage.id)
    XCTAssertNil(viewModel.draftReplyTarget)
    XCTAssertEqual(
      repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1").last?.replyToMessageId,
      repliedToMessage.id
    )
  }

  func testStartEditingSeedsComposerStateAndClearsReplyAndAttachment() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-edit",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Original message",
      clientId: "client-edit",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_040),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let replyTarget = FriendMessage(
      id: "message-reply",
      threadId: route.threadId,
      senderUserId: "friend-1",
      messageType: .user,
      body: "Reply target",
      clientId: "client-reply",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_030),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )

    await repository.saveThread(makeThread(), for: "viewer-1")
    await repository.saveMessages(
      [replyTarget, originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = makeThread()
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

    viewModel.setReplyTarget(replyTarget)
    await viewModel.setComposerAttachment(
      .image(ImageAttachment(id: "image-1", data: Data([0x00]), mediaType: "image/jpeg"))
    )
    await viewModel.startEditing(originalMessage)

    XCTAssertEqual(viewModel.composerMode, .edit)
    XCTAssertEqual(viewModel.draftEditTarget?.id, originalMessage.id)
    XCTAssertNil(viewModel.draftReplyTarget)
    XCTAssertNil(viewModel.stagedComposerAttachment)
    XCTAssertEqual(viewModel.draft, "Original message")
    XCTAssertEqual(viewModel.composerFocusRequestToken, 1)
  }

  func testCancelComposerModeAfterEditingRestoresSuspendedComposerState() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-edit",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Original message",
      clientId: "client-edit",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_041),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let replyTarget = FriendMessage(
      id: "message-reply",
      threadId: route.threadId,
      senderUserId: "friend-1",
      messageType: .user,
      body: "Reply target",
      clientId: "client-reply",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_031),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let attachment = FriendsComposerAttachmentDraft.image(
      ImageAttachment(id: "image-restore", data: Data([0x00]), mediaType: "image/jpeg")
    )

    await repository.saveThread(makeThread(), for: "viewer-1")
    await repository.saveMessages(
      [replyTarget, originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = makeThread()
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

    viewModel.setReplyTarget(replyTarget)
    viewModel.draft = "Pending follow up"
    await viewModel.setComposerAttachment(attachment)
    await viewModel.startEditing(originalMessage)
    await viewModel.cancelComposerMode()

    XCTAssertEqual(viewModel.composerMode, .reply)
    XCTAssertEqual(viewModel.draftReplyTarget?.id, replyTarget.id)
    XCTAssertEqual(viewModel.draft, "Pending follow up")
    XCTAssertEqual(viewModel.stagedComposerAttachment, attachment)
  }

  func testSendDraftInEditModeCallsEditMessageAndUpdatesStoredMessage() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-edit",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Original message",
      clientId: "client-edit",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_050),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let editedMessage = originalMessage.withEditedBody(
      "Updated message",
      editedAt: Date(timeIntervalSince1970: 1_700_000_060)
    )

    await repository.saveThread(makeThread(), for: "viewer-1")
    await repository.saveMessages([originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.editedMessage = editedMessage
    mockService.threadSummary = makeThread()
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

    await viewModel.startEditing(originalMessage)
    let didSend = await viewModel.sendMessage(content: "Updated message")

    XCTAssertTrue(didSend)
    XCTAssertEqual(mockService.lastEditedMessageId, originalMessage.id)
    XCTAssertEqual(mockService.lastEditedBody, "Updated message")
    XCTAssertEqual(
      repository.getMessage(id: originalMessage.id, viewerUserId: "viewer-1")?.body,
      "Updated message"
    )
    XCTAssertEqual(viewModel.composerMode, .normal)
    XCTAssertEqual(viewModel.draft, "")
  }

  func testSendDraftInEditModeRestoresSuspendedComposerStateOnSuccess() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-edit",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Original message",
      clientId: "client-edit",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_051),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let replyTarget = FriendMessage(
      id: "message-reply",
      threadId: route.threadId,
      senderUserId: "friend-1",
      messageType: .user,
      body: "Reply target",
      clientId: "client-reply",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_032),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let editedMessage = originalMessage.withEditedBody(
      "Updated message",
      editedAt: Date(timeIntervalSince1970: 1_700_000_061)
    )
    let attachment = FriendsComposerAttachmentDraft.image(
      ImageAttachment(id: "image-success", data: Data([0x01]), mediaType: "image/jpeg")
    )

    await repository.saveThread(makeThread(), for: "viewer-1")
    await repository.saveMessages(
      [replyTarget, originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.editedMessage = editedMessage
    mockService.threadSummary = makeThread()
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

    viewModel.setReplyTarget(replyTarget)
    viewModel.draft = "Pending follow up"
    await viewModel.setComposerAttachment(attachment)
    await viewModel.startEditing(originalMessage)
    let didSend = await viewModel.sendMessage(content: "Updated message")

    XCTAssertTrue(didSend)
    XCTAssertEqual(viewModel.composerMode, .reply)
    XCTAssertEqual(viewModel.draftReplyTarget?.id, replyTarget.id)
    XCTAssertEqual(viewModel.draft, "Pending follow up")
    XCTAssertEqual(viewModel.stagedComposerAttachment, attachment)
    XCTAssertEqual(
      repository.getMessage(id: originalMessage.id, viewerUserId: "viewer-1")?.body,
      "Updated message"
    )
  }

  func testSendDraftInEditModeRollsBackOnFailureAndShowsError() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-edit",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Original message",
      clientId: "client-edit",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_070),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )

    await repository.saveThread(makeThread(), for: "viewer-1")
    await repository.saveMessages([originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.editError = FriendsMessagingServiceError.networkError(underlying: TestError.failed)
    mockService.threadSummary = makeThread()
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

    await viewModel.startEditing(originalMessage)
    let didSend = await viewModel.sendMessage(content: "Updated message")

    XCTAssertFalse(didSend)
    XCTAssertEqual(
      repository.getMessage(id: originalMessage.id, viewerUserId: "viewer-1")?.body,
      "Original message"
    )
    XCTAssertEqual(
      viewModel.sendErrorMessage,
      String(localized: "friends.chat.edit_failed", table: "Localizable")
    )
    XCTAssertEqual(viewModel.composerMode, .edit)
    XCTAssertEqual(viewModel.draft, "Updated message")
  }

  func testDeleteMessageRemovesStoredMessageAndUpdatesThreadSummary() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-delete",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Delete me",
      clientId: "client-delete",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_080),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: originalMessage.id,
      lastMessageSenderId: "viewer-1",
      lastMessageAt: originalMessage.createdAt,
      lastMessageBody: originalMessage.body,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let emptiedThread = FriendThread(
      id: route.threadId,
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
      lastMessageAt: thread.createdAt,
      lastMessageBody: nil,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: thread.createdAt
    )

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages([originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.deletedThread = emptiedThread
    mockService.threadSummary = thread
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

    await viewModel.deleteMessage(messageId: originalMessage.id)

    XCTAssertEqual(mockService.lastDeletedMessageId, originalMessage.id)
    XCTAssertTrue(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").isEmpty)
    XCTAssertNil(repository.getThread(id: route.threadId, viewerUserId: "viewer-1")?.lastMessageId)
  }

  func testDeleteMessageRestoresStoredMessageWhenDeleteFails() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-delete",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Delete me",
      clientId: "client-delete",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_090),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: originalMessage.id,
      lastMessageSenderId: "viewer-1",
      lastMessageAt: originalMessage.createdAt,
      lastMessageBody: originalMessage.body,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages([originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.deleteError = FriendsMessagingServiceError.networkError(
      underlying: TestError.failed)
    mockService.threadSummary = thread
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

    await viewModel.deleteMessage(messageId: originalMessage.id)

    XCTAssertEqual(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").map(\.id),
      [originalMessage.id]
    )
    XCTAssertEqual(
      repository.getThread(id: route.threadId, viewerUserId: "viewer-1")?.lastMessageId,
      originalMessage.id
    )
    XCTAssertEqual(
      viewModel.sendErrorMessage,
      String(localized: "friends.chat.delete_failed", table: "Localizable")
    )
  }

  func testDeleteMessageRestoresComposerStateWhenDeleteFailsInEditMode() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let originalMessage = FriendMessage(
      id: "message-delete",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Delete me",
      clientId: "client-delete",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_091),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: originalMessage.id,
      lastMessageSenderId: "viewer-1",
      lastMessageAt: originalMessage.createdAt,
      lastMessageBody: originalMessage.body,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages([originalMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.deleteError = FriendsMessagingServiceError.networkError(
      underlying: TestError.failed)
    mockService.threadSummary = thread
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

    await viewModel.startEditing(originalMessage)
    viewModel.draft = "Edited draft"
    await viewModel.deleteMessage(messageId: originalMessage.id)

    XCTAssertEqual(viewModel.composerMode, .edit)
    XCTAssertEqual(viewModel.draftEditTarget?.id, originalMessage.id)
    XCTAssertEqual(viewModel.draft, "Edited draft")
    XCTAssertEqual(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").map(\.id),
      [originalMessage.id]
    )
  }

  func testDeleteFailedMessageRemovesItLocallyWithoutCallingServer() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let previousMessage = FriendMessage(
      id: "message-sent",
      threadId: route.threadId,
      senderUserId: "friend-1",
      messageType: .user,
      body: "Previous",
      clientId: "client-sent",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_100),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let failedMessage = FriendMessage(
      id: "local-failed",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Will not send",
      clientId: "client-failed",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_110),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [],
      reactions: [],
      sendState: .failed,
      failureMessage: "Failed"
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: "friend-1",
      counterpartDisplayName: "Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: failedMessage.id,
      lastMessageSenderId: failedMessage.senderUserId,
      lastMessageAt: failedMessage.createdAt,
      lastMessageBody: failedMessage.body,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages(
      [previousMessage, failedMessage], in: route.threadId, for: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
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

    await viewModel.deleteMessage(messageId: failedMessage.id)

    XCTAssertNil(mockService.lastDeletedMessageId)
    XCTAssertEqual(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").map(\.id),
      [previousMessage.id]
    )
    XCTAssertEqual(
      repository.getThread(id: route.threadId, viewerUserId: "viewer-1")?.lastMessageId,
      previousMessage.id
    )
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
    let didSend = await viewModel.sendDraft()

    XCTAssertFalse(didSend)
    XCTAssertEqual(viewModel.draft, "Hello again")
    XCTAssertEqual(viewModel.sendErrorMessage, String(localized: .friendsChatSendFailed))
    XCTAssertTrue(repository.getMessages(threadId: "thread-1", viewerUserId: "viewer-1").isEmpty)
  }

  func testSubmitReportUsesCounterpartAndMessageId() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
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

    try await viewModel.submitReport(messageId: "message-9", reason: .spam)

    XCTAssertEqual(mockService.createdReport?.threadId, "thread-1")
    XCTAssertEqual(mockService.createdReport?.reportedUserId, "friend-1")
    XCTAssertEqual(mockService.createdReport?.messageId, "message-9")
    XCTAssertEqual(mockService.createdReport?.reason, .spam)
  }

  func testBlockCounterpartMarksThreadReadOnly() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
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
    try await viewModel.blockCounterpart()

    XCTAssertEqual(mockService.blockedUserId, "friend-1")
    XCTAssertTrue(viewModel.isThreadReadOnly)
    XCTAssertEqual(viewModel.draft, "")
    XCTAssertEqual(viewModel.sendErrorMessage, String(localized: .friendsChatBlockedReadOnly))
  }

  func testLoadOlderMessagesAppendsOlderPageAndSetsRestoreTarget() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()

    let olderMessage = FriendMessage(
      id: "message-0",
      threadId: "thread-1",
      senderUserId: "friend-1",
      messageType: .user,
      body: "Older",
      clientId: "client-0",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let newestMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Newest",
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
      lastMessageAt: newestMessage.createdAt,
      lastMessageBody: newestMessage.body,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    mockService.listThreadMessagesHandler = { _, limit, cursor in
      XCTAssertEqual(limit, 50)
      if cursor == nil {
        return [newestMessage]
      }

      XCTAssertEqual(cursor?.messageId, newestMessage.id)
      return [olderMessage]
    }

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

    await viewModel.load()
    await viewModel.loadOlderMessagesIfNeeded(currentFirstMessageId: newestMessage.id)

    XCTAssertEqual(viewModel.messages.map(\.id), [olderMessage.id, newestMessage.id])
    XCTAssertEqual(viewModel.restoreScrollTargetMessageId, newestMessage.id)
    XCTAssertFalse(viewModel.hasMoreHistoricalMessages)
  }

  func testRefreshShowsMessagesBeforeSlowCounterpartStateReturns() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    let previewService = MockSharingPreviewService(previews: [])
    let message = FriendMessage(
      id: "message-1",
      threadId: route.threadId,
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
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: message.id,
      lastMessageSenderId: message.senderUserId,
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    mockService.threadMessages = [message]
    mockService.fetchThreadStateDelay = .milliseconds(700)

    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      sharingPreviewService: previewService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    let refreshTask = Task {
      await viewModel.refresh()
    }

    try? await Task.sleep(for: .milliseconds(150))

    XCTAssertEqual(viewModel.messages.map(\.id), [message.id])
    XCTAssertEqual(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").map(\.id),
      [message.id]
    )

    await refreshTask.value
  }

  func testLoadHydratesPendingComposerAttachmentDraft() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let thread = makeThread()
    let route = makeRoute()
    let snapshotDraft = FriendsComposerAttachmentDraft.shiftSnapshot(
      ComposerShiftSnapshotDraft(snapshot: makeShiftSnapshot())
    )

    await draftStore.saveAttachmentDraft(
      snapshotDraft, threadId: route.threadId, viewerUserId: "viewer-1")

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.load()

    XCTAssertEqual(viewModel.stagedComposerAttachment, snapshotDraft)
  }

  func testLoadHydratesPendingComposerImageAttachmentDrafts() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let thread = makeThread()
    let route = makeRoute()
    let imageDrafts: [FriendsComposerAttachmentDraft] = [
      .image(ImageAttachment(id: "image-1", data: Data([0x00]), mediaType: "image/jpeg")),
      .image(ImageAttachment(id: "image-2", data: Data([0x01]), mediaType: "image/jpeg")),
    ]

    await draftStore.saveAttachmentDrafts(
      imageDrafts,
      threadId: route.threadId,
      viewerUserId: "viewer-1"
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.load()

    XCTAssertEqual(viewModel.stagedComposerAttachments, imageDrafts)
  }

  func testLoadDeduplicatesPendingComposerImageAttachmentDraftsByPayload() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let thread = makeThread()
    let route = makeRoute()
    let duplicatePayload = Data([0x00, 0x01, 0x02])
    let imageDrafts: [FriendsComposerAttachmentDraft] = [
      .image(ImageAttachment(id: "image-1", data: duplicatePayload, mediaType: "image/jpeg")),
      .image(ImageAttachment(id: "image-2", data: duplicatePayload, mediaType: "image/jpeg")),
      .image(ImageAttachment(id: "image-3", data: Data([0x03]), mediaType: "image/jpeg")),
    ]

    await draftStore.saveAttachmentDrafts(
      imageDrafts,
      threadId: route.threadId,
      viewerUserId: "viewer-1"
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.load()

    XCTAssertEqual(
      viewModel.stagedComposerAttachments,
      [
        .image(ImageAttachment(id: "image-1", data: duplicatePayload, mediaType: "image/jpeg")),
        .image(ImageAttachment(id: "image-3", data: Data([0x03]), mediaType: "image/jpeg")),
      ]
    )
  }

  func testLoadHydratesPendingComposerTextDraft() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let thread = makeThread()
    let route = makeRoute()

    await draftStore.saveDraftText(
      "Unsent message",
      threadId: route.threadId,
      viewerUserId: "viewer-1"
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.load()

    XCTAssertEqual(viewModel.draft, "Unsent message")
  }

  func testHandleDraftChangedPersistsComposerTextDraft() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Persistent text"
    await viewModel.handleDraftChanged(to: "Persistent text")

    let storedText = await draftStore.loadDraftText(
      threadId: route.threadId,
      viewerUserId: "viewer-1"
    )
    XCTAssertEqual(storedText, "Persistent text")
  }

  func testHandleDraftChangedRetriesTypingStartAfterInitialBroadcastFailure() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()
    realtimeCoordinator.canBroadcastTyping = false

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Persistent text"
    await viewModel.handleDraftChanged(to: "Persistent text")

    XCTAssertEqual(realtimeCoordinator.typingStartCallCount, 1)

    realtimeCoordinator.canBroadcastTyping = true
    await viewModel.handleDraftChanged(to: "Persistent text")

    XCTAssertEqual(realtimeCoordinator.typingStartCallCount, 2)

    viewModel.draft = ""
    await viewModel.handleDraftChanged(to: "")

    XCTAssertEqual(realtimeCoordinator.typingStopCallCount, 1)
  }

  func testHandleDraftChangedQueuesVisibleTypingNotificationAfterSustainedTyping() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.queueThreadTypingNotificationResult = true
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Persistent text"
    await viewModel.handleDraftChanged(to: "Persistent text")

    XCTAssertEqual(mockService.queueThreadTypingNotificationCallCount, 0)

    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    XCTAssertEqual(mockService.queueThreadTypingNotificationCallCount, 1)
    XCTAssertEqual(mockService.lastQueuedTypingNotificationThreadId, route.threadId)
  }

  func testHandleDraftChangedDoesNotQueueVisibleTypingNotificationForShortDrafts() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.queueThreadTypingNotificationResult = true
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Short"
    await viewModel.handleDraftChanged(to: "Short")

    try? await Task.sleep(for: .milliseconds(300))
    viewModel.draft = ""
    await viewModel.handleDraftChanged(to: "")
    try? await Task.sleep(for: .milliseconds(600))
    await Task.yield()

    XCTAssertEqual(mockService.queueThreadTypingNotificationCallCount, 0)
  }

  func testHandleDraftChangedRespectsVisibleTypingNotificationCooldown() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.queueThreadTypingNotificationResult = true
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Persistent text"
    await viewModel.handleDraftChanged(to: "Persistent text")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    viewModel.draft = ""
    await viewModel.handleDraftChanged(to: "")
    viewModel.draft = "Back again"
    await viewModel.handleDraftChanged(to: "Back again")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    XCTAssertEqual(mockService.queueThreadTypingNotificationCallCount, 1)
  }

  func testHandleDraftChangedDoesNotStartCooldownWhenVisibleTypingNotificationIsSuppressed()
    async throws
  {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.queueThreadTypingNotificationResult = false
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Persistent text"
    await viewModel.handleDraftChanged(to: "Persistent text")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    viewModel.draft = ""
    await viewModel.handleDraftChanged(to: "")
    viewModel.draft = "Back again"
    await viewModel.handleDraftChanged(to: "Back again")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    XCTAssertEqual(mockService.queueThreadTypingNotificationCallCount, 2)
  }

  func testHandleDraftChangedDoesNotStartCooldownWhenVisibleTypingNotificationQueueFails()
    async throws
  {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.queueThreadTypingNotificationError = TestError.failed
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Persistent text"
    await viewModel.handleDraftChanged(to: "Persistent text")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    viewModel.draft = ""
    await viewModel.handleDraftChanged(to: "")
    viewModel.draft = "Back again"
    await viewModel.handleDraftChanged(to: "Back again")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    XCTAssertEqual(mockService.queueThreadTypingNotificationCallCount, 2)
  }

  func testSuccessfulSendResetsVisibleTypingNotificationCooldown() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    mockService.queueThreadTypingNotificationResult = true
    mockService.sentMessage = FriendMessage(
      id: "message-1",
      threadId: route.threadId,
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
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.draft = "Persistent text"
    await viewModel.handleDraftChanged(to: "Persistent text")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    viewModel.draft = "Hello"
    let didSend = await viewModel.sendDraft()
    XCTAssertTrue(didSend)

    viewModel.draft = "Fresh draft"
    await viewModel.handleDraftChanged(to: "Fresh draft")
    try? await Task.sleep(for: .milliseconds(900))
    await Task.yield()

    XCTAssertEqual(mockService.queueThreadTypingNotificationCallCount, 2)
  }

  func testReplyTargetSurvivesOutgoingMessageConfirmationByLogicalRowIdentity() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let optimisticMessage = FriendMessage(
      id: "local-client-1",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
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
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Hello",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: optimisticMessage.createdAt.addingTimeInterval(2),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )
    let realtimeCoordinator = MockFriendsRealtimeCoordinator()

    await repository.saveThread(makeThread(), for: "viewer-1")
    await repository.saveOptimisticMessage(
      optimisticMessage,
      in: route.threadId,
      for: "viewer-1"
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: MockFriendsMessagingService(),
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.reloadFromCache()
    viewModel.setReplyTarget(optimisticMessage)

    await repository.saveConfirmedMessage(
      confirmedMessage,
      replacingLocalMessageId: optimisticMessage.id,
      in: route.threadId,
      for: "viewer-1"
    )

    viewModel.reloadFromCache()

    XCTAssertEqual(viewModel.draftReplyTarget?.id, confirmedMessage.id)
    XCTAssertEqual(viewModel.draftReplyTarget?.clientId, confirmedMessage.clientId)
  }

  func testHandleAppDidBecomeActiveResubscribesRealtimeAndRefreshesThreadData() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let message = FriendMessage(
      id: "message-1",
      threadId: route.threadId,
      senderUserId: route.counterpartUserId,
      messageType: .user,
      body: "Welcome back",
      clientId: "client-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: message.id,
      lastMessageSenderId: message.senderUserId,
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageHasImage: false,
      unreadCount: 1,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    mockService.threadMessages = [message]

    let realtimeCoordinator = MockFriendsRealtimeCoordinator()
    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    viewModel.handleCounterpartTypingChange(userId: route.counterpartUserId, isTyping: true)
    XCTAssertTrue(viewModel.counterpartIsTyping)

    await viewModel.handleAppDidBecomeActive()

    XCTAssertEqual(realtimeCoordinator.startThreadSubscriptionCallCount, 1)
    XCTAssertFalse(viewModel.counterpartIsTyping)
    XCTAssertEqual(viewModel.messages.map(\.id), [message.id])
    XCTAssertEqual(
      repository.getThread(id: route.threadId, viewerUserId: "viewer-1")?.lastMessageId,
      message.id
    )
  }

  func testHandleNotificationOpenPrimesCounterpartTypingFromTypingNotification() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: MockFriendsMessagingService(),
      repository: repository,
      realtimeCoordinator: MockFriendsRealtimeCoordinator()
    )

    await viewModel.handleNotificationOpen(
      targetMessageId: nil,
      notificationTypingUserId: route.counterpartUserId,
      forceRefresh: false
    )

    XCTAssertTrue(viewModel.counterpartIsTyping)
  }

  func testReloadFromCachePreservesPrimedTypingIndicatorDuringNotificationHandoff() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let message = FriendMessage(
      id: "message-handoff-1",
      threadId: route.threadId,
      senderUserId: route.counterpartUserId,
      messageType: .user,
      body: "Still typing",
      clientId: "client-handoff-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_100),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: message.id,
      lastMessageSenderId: message.senderUserId,
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageHasImage: false,
      unreadCount: 1,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: MockFriendsMessagingService(),
      repository: repository,
      realtimeCoordinator: MockFriendsRealtimeCoordinator()
    )

    await viewModel.handleNotificationOpen(
      targetMessageId: nil,
      notificationTypingUserId: route.counterpartUserId,
      forceRefresh: false
    )
    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages([message], in: route.threadId, for: "viewer-1")

    viewModel.reloadFromCache()

    XCTAssertTrue(viewModel.counterpartIsTyping)
  }

  func testHandleAppDidBecomeActiveReappliesPrimedNotificationTypingIndicator() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let message = FriendMessage(
      id: "message-active-1",
      threadId: route.threadId,
      senderUserId: route.counterpartUserId,
      messageType: .user,
      body: "Latest",
      clientId: "client-active-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_100),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: message.id,
      lastMessageSenderId: message.senderUserId,
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageHasImage: false,
      unreadCount: 1,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    mockService.threadMessages = [message]

    let realtimeCoordinator = MockFriendsRealtimeCoordinator()
    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.handleNotificationOpen(
      targetMessageId: nil,
      notificationTypingUserId: route.counterpartUserId,
      forceRefresh: false
    )
    await viewModel.handleAppDidBecomeActive()

    XCTAssertEqual(realtimeCoordinator.startThreadSubscriptionCallCount, 1)
    XCTAssertTrue(viewModel.counterpartIsTyping)
  }

  func testHandleAppDidBecomeActiveRefreshesCounterpartReadState() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let message = FriendMessage(
      id: "message-read-1",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Seen already",
      clientId: "client-read-1",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_100),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: []
    )
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: message.id,
      lastMessageSenderId: message.senderUserId,
      lastMessageAt: message.createdAt,
      lastMessageBody: message.body,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    mockService.threadMessages = [message]
    mockService.threadStates = [
      FriendThreadState(
        threadId: route.threadId,
        userId: "viewer-1",
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_101)
      ),
      FriendThreadState(
        threadId: route.threadId,
        userId: route.counterpartUserId,
        lastReadMessageId: message.id,
        lastReadAt: message.createdAt,
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_102)
      ),
    ]

    let realtimeCoordinator = MockFriendsRealtimeCoordinator()
    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.handleAppDidBecomeActive()

    XCTAssertEqual(realtimeCoordinator.startThreadSubscriptionCallCount, 1)
    XCTAssertEqual(viewModel.counterpartReadState?.lastReadMessageId, message.id)
    XCTAssertEqual(
      repository.getThreadState(threadId: route.threadId, viewerUserId: route.counterpartUserId)?
        .lastReadMessageId,
      message.id
    )
  }

  func testVisibleReadMarkerAdvancesOnlyToLatestVisibleMessage() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: "message-3",
      lastMessageSenderId: "friend-1",
      lastMessageAt: Date(timeIntervalSince1970: 1_700_000_030),
      lastMessageBody: "Newest",
      lastMessageHasImage: false,
      unreadCount: 2,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let messages = [
      FriendMessage(
        id: "message-1",
        threadId: route.threadId,
        senderUserId: "friend-1",
        messageType: .user,
        body: "First",
        clientId: "",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_010),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
      FriendMessage(
        id: "message-2",
        threadId: route.threadId,
        senderUserId: "viewer-1",
        messageType: .user,
        body: "Reply",
        clientId: "client-2",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_020),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
      FriendMessage(
        id: "message-3",
        threadId: route.threadId,
        senderUserId: "friend-1",
        messageType: .user,
        body: "Newest",
        clientId: "",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_030),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
    ]

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages(messages, in: route.threadId, for: "viewer-1")
    await repository.saveThreadState(
      FriendThreadState(
        threadId: route.threadId,
        userId: "viewer-1",
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_005)
      ))

    let mockService = MockFriendsMessagingService()
    mockService.markThreadReadResult = FriendThreadState(
      threadId: route.threadId,
      userId: "viewer-1",
      lastReadMessageId: "message-2",
      lastReadAt: Date(timeIntervalSince1970: 1_700_000_020),
      muted: false,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_040)
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: MockFriendsRealtimeCoordinator()
    )

    viewModel.reloadFromCache()
    await viewModel.updateLatestVisibleMessage(messageId: "message-2")
    try? await Task.sleep(for: .milliseconds(250))

    XCTAssertEqual(mockService.markThreadReadCallCount, 1)
    XCTAssertEqual(mockService.lastMarkedReadThreadId, route.threadId)
    XCTAssertEqual(mockService.lastMarkedReadMessageId, "message-2")
    XCTAssertEqual(
      repository.getThreadState(threadId: route.threadId, viewerUserId: "viewer-1")?
        .lastReadMessageId,
      "message-2"
    )
  }

  func testVisibleReadMarkerDoesNotAdvanceToHiddenLatestMessage() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: "message-3",
      lastMessageSenderId: "friend-1",
      lastMessageAt: Date(timeIntervalSince1970: 1_700_000_030),
      lastMessageBody: "Newest",
      lastMessageHasImage: false,
      unreadCount: 2,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let messages = [
      FriendMessage(
        id: "message-1",
        threadId: route.threadId,
        senderUserId: "friend-1",
        messageType: .user,
        body: "First",
        clientId: "",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_010),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
      FriendMessage(
        id: "message-2",
        threadId: route.threadId,
        senderUserId: "viewer-1",
        messageType: .user,
        body: "Reply",
        clientId: "client-2",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_020),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
      FriendMessage(
        id: "message-3",
        threadId: route.threadId,
        senderUserId: "friend-1",
        messageType: .user,
        body: "Newest",
        clientId: "",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_030),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
    ]

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages(messages, in: route.threadId, for: "viewer-1")
    await repository.saveThreadState(
      FriendThreadState(
        threadId: route.threadId,
        userId: "viewer-1",
        lastReadMessageId: "message-2",
        lastReadAt: Date(timeIntervalSince1970: 1_700_000_020),
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_021)
      ))

    let mockService = MockFriendsMessagingService()
    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: MockFriendsRealtimeCoordinator()
    )

    viewModel.reloadFromCache()
    await viewModel.updateLatestVisibleMessage(messageId: "message-2")
    try? await Task.sleep(for: .milliseconds(250))

    XCTAssertEqual(mockService.markThreadReadCallCount, 0)
    XCTAssertNil(mockService.lastMarkedReadMessageId)
  }

  func testVisibleReadMarkerCoalescesRapidViewportUpdates() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let thread = FriendThread(
      id: route.threadId,
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: route.counterpartUserId,
      counterpartDisplayName: route.displayName,
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: "message-3",
      lastMessageSenderId: "friend-1",
      lastMessageAt: Date(timeIntervalSince1970: 1_700_000_030),
      lastMessageBody: "Newest",
      lastMessageHasImage: false,
      unreadCount: 2,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let messages = [
      FriendMessage(
        id: "message-1",
        threadId: route.threadId,
        senderUserId: "friend-1",
        messageType: .user,
        body: "First",
        clientId: "",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_010),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
      FriendMessage(
        id: "message-2",
        threadId: route.threadId,
        senderUserId: "viewer-1",
        messageType: .user,
        body: "Reply",
        clientId: "client-2",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_020),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
      FriendMessage(
        id: "message-3",
        threadId: route.threadId,
        senderUserId: "friend-1",
        messageType: .user,
        body: "Newest",
        clientId: "",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_700_000_030),
        editedAt: nil,
        deletedAt: nil,
        attachments: []
      ),
    ]

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages(messages, in: route.threadId, for: "viewer-1")
    await repository.saveThreadState(
      FriendThreadState(
        threadId: route.threadId,
        userId: "viewer-1",
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: false,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_005)
      ))

    let mockService = MockFriendsMessagingService()
    mockService.markThreadReadResult = FriendThreadState(
      threadId: route.threadId,
      userId: "viewer-1",
      lastReadMessageId: "message-3",
      lastReadAt: Date(timeIntervalSince1970: 1_700_000_030),
      muted: false,
      updatedAt: Date(timeIntervalSince1970: 1_700_000_040)
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      realtimeCoordinator: MockFriendsRealtimeCoordinator()
    )

    viewModel.reloadFromCache()
    await viewModel.updateLatestVisibleMessage(messageId: "message-1")
    await viewModel.updateLatestVisibleMessage(messageId: "message-2")
    await viewModel.updateLatestVisibleMessage(messageId: "message-3")
    try? await Task.sleep(for: .milliseconds(250))

    XCTAssertEqual(mockService.markThreadReadCallCount, 1)
    XCTAssertEqual(mockService.lastMarkedReadMessageId, "message-3")
  }

  func testSendDraftWithShiftSnapshotUsesStoredMetadata() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let thread = makeThread()
    let route = makeRoute()
    let snapshotDraft = FriendsComposerAttachmentDraft.shiftSnapshot(
      ComposerShiftSnapshotDraft(snapshot: makeShiftSnapshot())
    )

    let mockService = MockFriendsMessagingService()
    mockService.sentMessage = FriendMessage(
      id: "message-shift",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: nil,
      clientId: "client-shift",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_010),
      editedAt: nil,
      deletedAt: nil,
      metadataData: snapshotDraft.metadataData,
      attachments: []
    )
    mockService.threadSummary = thread
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.setComposerAttachment(snapshotDraft)
    let didSend = await viewModel.sendDraft()
    await Task.yield()

    XCTAssertTrue(didSend)
    XCTAssertNil(viewModel.stagedComposerAttachment)
    XCTAssertEqual(mockService.lastSentMetadataData, snapshotDraft.metadataData)
    XCTAssertNotNil(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").last?.metadataData
    )
    let storedDraft = await draftStore.loadAttachmentDraft(
      threadId: route.threadId, viewerUserId: "viewer-1")
    XCTAssertNil(storedDraft)
  }

  func testSendDraftWithMultipleImagesSendsSingleMessageWithAllAttachments() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let thread = makeThread()
    let route = makeRoute()
    let imageDrafts: [FriendsComposerAttachmentDraft] = [
      .image(ImageAttachment(id: "image-1", data: Data([0x00]), mediaType: "image/jpeg")),
      .image(ImageAttachment(id: "image-2", data: Data([0x01]), mediaType: "image/jpeg")),
    ]

    let mockService = MockFriendsMessagingService()
    mockService.sentMessage = FriendMessage(
      id: "message-multi-image",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: "Two images",
      clientId: "client-multi-image",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_011),
      editedAt: nil,
      deletedAt: nil,
      metadataData: nil,
      attachments: [
        FriendMessageAttachment(
          id: "uploaded-1",
          attachmentIndex: 0,
          kind: .image,
          storageBucket: "message-attachments",
          storagePath: "thread-1/viewer-1/uploaded-1.jpg",
          mimeType: "image/jpeg",
          byteSize: 1024,
          width: 320,
          height: 240,
          createdAt: Date(timeIntervalSince1970: 1_700_000_011)
        ),
        FriendMessageAttachment(
          id: "uploaded-2",
          attachmentIndex: 1,
          kind: .image,
          storageBucket: "message-attachments",
          storagePath: "thread-1/viewer-1/uploaded-2.jpg",
          mimeType: "image/jpeg",
          byteSize: 2048,
          width: 640,
          height: 480,
          createdAt: Date(timeIntervalSince1970: 1_700_000_011)
        ),
      ]
    )
    mockService.uploadedAttachmentsQueue = [
      FriendOutgoingAttachment(
        attachmentId: "uploaded-1",
        storagePath: "thread-1/viewer-1/uploaded-1.jpg",
        mimeType: "image/jpeg",
        byteSize: 1024,
        width: 320,
        height: 240
      ),
      FriendOutgoingAttachment(
        attachmentId: "uploaded-2",
        storagePath: "thread-1/viewer-1/uploaded-2.jpg",
        mimeType: "image/jpeg",
        byteSize: 2048,
        width: 640,
        height: 480
      ),
    ]
    mockService.threadSummary = thread
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.setComposerAttachments(imageDrafts)
    viewModel.draft = "Two images"
    let didSend = await viewModel.sendDraft()
    await Task.yield()

    XCTAssertTrue(didSend)
    XCTAssertTrue(viewModel.stagedComposerAttachments.isEmpty)
    XCTAssertEqual(
      mockService.lastSentAttachments.map(\.attachmentId), ["uploaded-1", "uploaded-2"])
    XCTAssertNil(mockService.lastSentMetadataData)
    XCTAssertEqual(
      repository.getMessages(threadId: route.threadId, viewerUserId: "viewer-1").last?.attachments
        .map(\.id),
      ["uploaded-1", "uploaded-2"]
    )
    let storedDrafts = await draftStore.loadAttachmentDrafts(
      threadId: route.threadId,
      viewerUserId: "viewer-1"
    )
    XCTAssertTrue(storedDrafts.isEmpty)
  }

  func testRetryMessagePreservesShiftSnapshotMetadata() async throws {
    let repository = try makeRepository()
    let draftStore = try makeDraftStore()
    let thread = makeThread()
    let route = makeRoute()
    let metadataData = FriendsComposerAttachmentDraft.shiftSnapshot(
      ComposerShiftSnapshotDraft(snapshot: makeShiftSnapshot())
    ).metadataData

    await repository.saveThread(thread, for: "viewer-1")
    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-failed",
          threadId: route.threadId,
          senderUserId: "viewer-1",
          messageType: .user,
          body: nil,
          clientId: "client-failed",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_020),
          editedAt: nil,
          deletedAt: nil,
          metadataData: metadataData,
          attachments: [],
          reactions: [],
          sendState: .failed,
          failureMessage: "Failed"
        )
      ],
      in: route.threadId,
      for: "viewer-1"
    )

    let mockService = MockFriendsMessagingService()
    mockService.sentMessage = FriendMessage(
      id: "message-confirmed",
      threadId: route.threadId,
      senderUserId: "viewer-1",
      messageType: .user,
      body: nil,
      clientId: "client-failed",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_700_000_021),
      editedAt: nil,
      deletedAt: nil,
      metadataData: metadataData,
      attachments: []
    )
    mockService.threadSummary = thread
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      repository: repository,
      composerDraftStore: draftStore,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.retryMessage(messageId: "message-failed")
    await Task.yield()

    XCTAssertEqual(mockService.lastSentMetadataData, metadataData)
  }

  func testSendDraftWithDisabledShiftSnapshotGateKeepsDraftAndShowsError() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let snapshotDraft = FriendsComposerAttachmentDraft.shiftSnapshot(
      ComposerShiftSnapshotDraft(snapshot: makeShiftSnapshot())
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = makeThread()
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      capabilities: MockFriendsMessagingCapabilities(canSendShiftSnapshots: false),
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.setComposerAttachment(snapshotDraft)
    let didSend = await viewModel.sendDraft()

    XCTAssertFalse(didSend)
    XCTAssertEqual(viewModel.stagedComposerAttachment, snapshotDraft)
    XCTAssertEqual(
      viewModel.sendErrorMessage,
      String(localized: "friends.chat.shift_snapshot_send_unavailable", table: "Localizable")
    )
    XCTAssertNil(mockService.lastSentMetadataData)
  }

  func testRetryMessageWithDisabledShiftSnapshotGateDoesNotRetry() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let metadataData = FriendsComposerAttachmentDraft.shiftSnapshot(
      ComposerShiftSnapshotDraft(snapshot: makeShiftSnapshot())
    ).metadataData

    await repository.saveThread(makeThread(), for: "viewer-1")
    await repository.saveMessages(
      [
        FriendMessage(
          id: "message-failed",
          threadId: route.threadId,
          senderUserId: "viewer-1",
          messageType: .user,
          body: nil,
          clientId: "client-failed",
          replyToMessageId: nil,
          createdAt: Date(timeIntervalSince1970: 1_700_000_030),
          editedAt: nil,
          deletedAt: nil,
          metadataData: metadataData,
          attachments: [],
          reactions: [],
          sendState: .failed,
          failureMessage: "Failed"
        )
      ],
      in: route.threadId,
      for: "viewer-1"
    )

    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = makeThread()
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      capabilities: MockFriendsMessagingCapabilities(canSendShiftSnapshots: false),
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.retryMessage(messageId: "message-failed")

    XCTAssertEqual(
      viewModel.sendErrorMessage,
      String(localized: "friends.chat.shift_snapshot_send_unavailable", table: "Localizable")
    )
    XCTAssertNil(mockService.lastSentMetadataData)
    XCTAssertEqual(
      repository.getMessage(id: "message-failed", viewerUserId: "viewer-1")?.sendState,
      .failed
    )
  }

  func testLoadFetchesCounterpartShiftPreviewWhenCounterpartIsVisibleSharer() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let thread = makeThread()
    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread

    let preview = SharerShiftPreview(
      sharerId: route.counterpartUserId,
      shift: SharedShiftData(
        id: "shared-shift-1",
        user_id: route.counterpartUserId,
        job_id: "job-1",
        job_name: "Cafe",
        job_color: "#FFAA00",
        shift_date: "2026-03-12",
        start_time: "10:00",
        end_time: "18:00",
        computed: SharedShiftComputed(
          id: "shared-shift-1",
          durationHours: 8,
          paidHours: 7.5,
          basePay: 1000,
          supplementPay: 200,
          gross: 1200,
          breakAudit: SharedBreakAudit(
            method: .none,
            thresholdHours: 0,
            deductedHours: 0,
            source: .none,
            appliedPauseWindows: nil,
            notes: []
          )
        ),
        tax_enabled: true,
        tax_percentage: 12.5,
        custom_pause_windows: nil,
        custom_supplements: nil,
        recurring_id: nil,
        recurring_anchor_weekday: nil
      ),
      status: .upcoming,
      showEarnings: true
    )

    let previewService = MockSharingPreviewService(previews: [preview])
    let sharedShiftsCache = MockSharedShiftsCache(
      cachedFriends: .init(
        sharers: [
          SharedUser(
            id: route.counterpartUserId,
            email: "friend@example.com",
            phone: nil,
            firstName: "Friend",
            profilePictureUrl: nil,
            oauthAvatarUrl: nil,
            sharedAt: "2026-03-11T10:00:00Z",
            showEarnings: true,
            hidden: false
          )
        ],
        chatOnlyUserIds: []
      )
    )
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      sharingPreviewService: previewService,
      sharedShiftsCache: sharedShiftsCache,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.load()

    XCTAssertEqual(viewModel.counterpartShiftPreview, preview)
    XCTAssertEqual(previewService.requestedSharerIds, [[route.counterpartUserId]])
    XCTAssertEqual(sharedShiftsCache.savedPreviewBatches.count, 1)
  }

  func testLoadHidesCounterpartShiftPreviewForChatOnlyCounterpart() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let thread = makeThread()
    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread
    let previewService = MockSharingPreviewService(previews: [])
    let sharedShiftsCache = MockSharedShiftsCache(
      cachedFriends: .init(
        sharers: [
          SharedUser(
            id: route.counterpartUserId,
            email: "friend@example.com",
            phone: nil,
            firstName: "Friend",
            profilePictureUrl: nil,
            oauthAvatarUrl: nil,
            sharedAt: "2026-03-11T10:00:00Z",
            showEarnings: false,
            hidden: false
          )
        ],
        chatOnlyUserIds: [route.counterpartUserId]
      )
    )
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      sharingPreviewService: previewService,
      sharedShiftsCache: sharedShiftsCache,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.load()

    XCTAssertNil(viewModel.counterpartShiftPreview)
    XCTAssertTrue(previewService.requestedSharerIds.isEmpty)
  }

  func testLoadFetchesCounterpartShiftPreviewWhenSharerCacheIsCold() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let thread = makeThread()
    let mockService = MockFriendsMessagingService()
    mockService.threadSummary = thread

    let preview = SharerShiftPreview(
      sharerId: route.counterpartUserId,
      shift: SharedShiftData(
        id: "shared-shift-cold",
        user_id: route.counterpartUserId,
        job_id: "job-1",
        job_name: "Cafe",
        job_color: "#FFAA00",
        shift_date: "2026-03-12",
        start_time: "10:00",
        end_time: "18:00",
        computed: SharedShiftComputed(
          id: "shared-shift-cold",
          durationHours: 8,
          paidHours: 7.5,
          basePay: 1000,
          supplementPay: 200,
          gross: 1200,
          breakAudit: SharedBreakAudit(
            method: .none,
            thresholdHours: 0,
            deductedHours: 0,
            source: .none,
            appliedPauseWindows: nil,
            notes: []
          )
        ),
        tax_enabled: true,
        tax_percentage: 12.5,
        custom_pause_windows: nil,
        custom_supplements: nil,
        recurring_id: nil,
        recurring_anchor_weekday: nil
      ),
      status: .upcoming,
      showEarnings: true
    )

    let previewService = MockSharingPreviewService(previews: [preview])
    let sharedShiftsCache = MockSharedShiftsCache(
      cachedFriends: .init(
        sharers: [],
        chatOnlyUserIds: []
      )
    )
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      sharingPreviewService: previewService,
      sharedShiftsCache: sharedShiftsCache,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    await viewModel.load()

    XCTAssertEqual(viewModel.counterpartShiftPreview, preview)
    XCTAssertEqual(previewService.requestedSharerIds, [[route.counterpartUserId]])
  }

  func testRefreshCounterpartShiftPreviewBypassesStaleHiddenCache() async throws {
    let repository = try makeRepository()
    let route = makeRoute()
    let mockService = MockFriendsMessagingService()
    let preview = SharerShiftPreview(
      sharerId: route.counterpartUserId,
      shift: SharedShiftData(
        id: "shared-shift-refresh",
        user_id: route.counterpartUserId,
        job_id: "job-1",
        job_name: "Cafe",
        job_color: "#FFAA00",
        shift_date: "2026-03-12",
        start_time: "10:00",
        end_time: "18:00",
        computed: SharedShiftComputed(
          id: "shared-shift-refresh",
          durationHours: 8,
          paidHours: 7.5,
          basePay: 1000,
          supplementPay: 200,
          gross: 1200,
          breakAudit: SharedBreakAudit(
            method: .none,
            thresholdHours: 0,
            deductedHours: 0,
            source: .none,
            appliedPauseWindows: nil,
            notes: []
          )
        ),
        tax_enabled: true,
        tax_percentage: 12.5,
        custom_pause_windows: nil,
        custom_supplements: nil,
        recurring_id: nil,
        recurring_anchor_weekday: nil
      ),
      status: .upcoming,
      showEarnings: true
    )
    let previewService = MockSharingPreviewService(previews: [preview])
    let sharedShiftsCache = MockSharedShiftsCache(
      cachedFriends: .init(
        sharers: [
          SharedUser(
            id: route.counterpartUserId,
            email: "friend@example.com",
            phone: nil,
            firstName: "Friend",
            profilePictureUrl: nil,
            oauthAvatarUrl: nil,
            sharedAt: "2026-03-11T10:00:00Z",
            showEarnings: true,
            hidden: true
          )
        ],
        chatOnlyUserIds: []
      )
    )
    let realtimeCoordinator = FriendsMessagingRealtimeCoordinator(
      service: mockService,
      repository: repository
    )

    let viewModel = FriendsThreadViewModel(
      route: route,
      viewerUserId: "viewer-1",
      service: mockService,
      sharingPreviewService: previewService,
      sharedShiftsCache: sharedShiftsCache,
      repository: repository,
      realtimeCoordinator: realtimeCoordinator
    )

    XCTAssertNil(viewModel.counterpartShiftPreview)

    await viewModel.refreshCounterpartShiftPreview()

    XCTAssertEqual(viewModel.counterpartShiftPreview, preview)
    XCTAssertEqual(previewService.requestedSharerIds, [[route.counterpartUserId]])
    XCTAssertEqual(previewService.requestedForceRefreshValues, [true])
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

  private func makeDraftStore() throws -> FriendsComposerDraftStore {
    let schema = Schema([
      LocalPendingFriendComposerDraft.self
    ])

    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      allowsSave: true
    )

    let container = try ModelContainer(for: schema, configurations: [configuration])
    let storeActor = LocalStoreActor(modelContainer: container)
    let attachmentsDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(
      at: attachmentsDirectory, withIntermediateDirectories: true)
    return FriendsComposerDraftStore(
      container: container,
      storeActor: storeActor,
      attachmentsDirectory: attachmentsDirectory
    )
  }

  private func makeRoute() -> FriendChatRoute {
    FriendChatRoute(
      thread: makeThread(),
      fallbackDisplayName: "Friend",
      fallbackAvatarUrl: nil
    )
  }

  private func makeThread() -> FriendThread {
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
      lastMessageId: nil,
      lastMessageSenderId: nil,
      lastMessageAt: nil,
      lastMessageBody: nil,
      lastMessageHasImage: false,
      unreadCount: 0,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }
}

private func makeShiftSnapshot() -> FriendShiftSnapshot {
  FriendShiftSnapshot(
    schemaVersion: 1,
    ownerUserId: "viewer-1",
    ownerDisplayName: "Viewer",
    ownerAvatarUrl: nil,
    shiftId: "shift-1",
    jobName: "Cafe",
    jobColorHex: "#FFAA00",
    shiftDate: "2026-03-11",
    startTime: "09:00",
    endTime: "17:00",
    paidHours: 7.5,
    currency: "kr",
    includesEarnings: true,
    grossPay: 1200,
    netPay: 1050,
    taxEnabled: true,
    source: "tests"
  )
}

private enum TestError: Error {
  case failed
}

private struct MockFriendsMessagingCapabilities: FriendsMessagingCapabilityProviding {
  let canSendShiftSnapshots: Bool
}

@MainActor
private final class MockSharingPreviewService: SharingPreviewProviding {
  let previews: [SharerShiftPreview]
  var requestedSharerIds: [[String]] = []
  var requestedForceRefreshValues: [Bool] = []

  init(previews: [SharerShiftPreview]) {
    self.previews = previews
  }

  func fetchShiftPreviews(sharerIds: [String], forceRefresh: Bool) async throws
    -> [SharerShiftPreview]
  {
    await Task.yield()
    requestedSharerIds.append(sharerIds)
    requestedForceRefreshValues.append(forceRefresh)
    return previews
  }
}

@MainActor
private final class MockSharedShiftsCache: SharedShiftsCaching {
  let cachedFriends: SharedShiftsRepository.CachedFriendsSnapshot
  var cachedPreviewsByViewerId: [String: [String: SharerShiftPreview]]
  var savedPreviewBatches: [[SharerShiftPreview]] = []

  init(
    cachedFriends: SharedShiftsRepository.CachedFriendsSnapshot,
    cachedPreviewsByViewerId: [String: [String: SharerShiftPreview]] = [:]
  ) {
    self.cachedFriends = cachedFriends
    self.cachedPreviewsByViewerId = cachedPreviewsByViewerId
  }

  func getCachedFriends(
    for _: String,
    includeHidden _: Bool
  ) -> SharedShiftsRepository.CachedFriendsSnapshot {
    cachedFriends
  }

  func getShiftPreviews(for viewerId: String) -> [String: SharerShiftPreview] {
    cachedPreviewsByViewerId[viewerId] ?? [:]
  }

  func saveShiftPreviews(_ previews: [SharerShiftPreview], for viewerId: String) async {
    await Task.yield()
    savedPreviewBatches.append(previews)
    cachedPreviewsByViewerId[viewerId] =
      Dictionary(uniqueKeysWithValues: previews.map { ($0.sharerId, $0) })
  }
}

@MainActor
private final class MockFriendsMessagingService: FriendsMessagingServiceProviding {
  var sentMessage: FriendMessage?
  var editedMessage: FriendMessage?
  var threadSummary: FriendThread?
  var deletedThread: FriendThread?
  var threadMessages: [FriendMessage] = []
  var sendDelay: Duration?
  var fetchThreadStateDelay: Duration?
  var threadStates: [FriendThreadState] = []
  var listThreadMessagesHandler:
    ((String, Int, FriendMessageCursor?) async throws -> [FriendMessage])?
  var sendError: Error?
  var editError: Error?
  var deleteError: Error?
  var markThreadReadError: Error?
  var queueThreadTypingNotificationError: Error?
  var sendMessageCallCount = 0
  var markThreadReadCallCount = 0
  var queueThreadTypingNotificationResult = false
  var queueThreadTypingNotificationCallCount = 0
  var markThreadReadResult = FriendThreadState(
    threadId: "thread-1",
    userId: "viewer-1",
    lastReadMessageId: nil,
    lastReadAt: nil,
    muted: false,
    updatedAt: Date()
  )
  var lastSentReplyToMessageId: String?
  var lastSentAttachments: [FriendOutgoingAttachment] = []
  var lastSentMetadataData: Data?
  var lastEditedMessageId: String?
  var lastEditedBody: String?
  var lastDeletedMessageId: String?
  var lastMarkedReadThreadId: String?
  var lastMarkedReadMessageId: String?
  var lastQueuedTypingNotificationThreadId: String?
  var createdReport:
    (threadId: String, reportedUserId: String, messageId: String?, reason: FriendAbuseReportReason)?
  var blockedUserId: String?
  var uploadedAttachment: FriendOutgoingAttachment?
  var uploadedAttachmentsQueue: [FriendOutgoingAttachment] = []

  func getOrCreateDirectThread(otherUserId _: String) async throws -> FriendThread {
    await Task.yield()
    throw TestError.failed
  }

  func listMyThreads(limit _: Int, before _: FriendThreadCursor?) async throws -> [FriendThread] {
    await Task.yield()
    []
  }

  func listThreadMessages(
    threadId: String,
    limit: Int,
    before cursor: FriendMessageCursor?
  )
    async throws -> [FriendMessage]
  {
    await Task.yield()
    if let listThreadMessagesHandler {
      return try await listThreadMessagesHandler(threadId, limit, cursor)
    }
    threadMessages
  }

  func sendMessage(
    threadId _: String,
    clientId _: String,
    body _: String?,
    replyToMessageId: String?,
    attachments: [FriendOutgoingAttachment],
    metadataData: Data?
  ) async throws -> FriendMessage {
    await Task.yield()
    sendMessageCallCount += 1
    if let sendDelay {
      try? await Task.sleep(for: sendDelay)
    }
    lastSentReplyToMessageId = replyToMessageId
    lastSentAttachments = attachments
    lastSentMetadataData = metadataData
    if let sendError {
      throw sendError
    }
    return try XCTUnwrap(sentMessage)
  }

  func editMessage(messageId: String, body: String) async throws -> FriendMessage {
    await Task.yield()
    lastEditedMessageId = messageId
    lastEditedBody = body
    if let editError {
      throw editError
    }
    return try XCTUnwrap(editedMessage)
  }

  func deleteMessage(messageId: String) async throws -> FriendThread {
    await Task.yield()
    lastDeletedMessageId = messageId
    if let deleteError {
      throw deleteError
    }
    return try XCTUnwrap(deletedThread)
  }

  func markThreadRead(threadId: String, throughMessageId: String) async throws
    -> FriendThreadState
  {
    await Task.yield()
    markThreadReadCallCount += 1
    lastMarkedReadThreadId = threadId
    lastMarkedReadMessageId = throughMessageId
    if let markThreadReadError {
      throw markThreadReadError
    }
    return markThreadReadResult
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

  func queueThreadTypingNotification(threadId: String) async throws -> Bool {
    await Task.yield()
    queueThreadTypingNotificationCallCount += 1
    lastQueuedTypingNotificationThreadId = threadId
    if let queueThreadTypingNotificationError {
      throw queueThreadTypingNotificationError
    }
    return queueThreadTypingNotificationResult
  }

  func fetchThreadSummary(threadId _: String) async throws -> FriendThread {
    await Task.yield()
    try XCTUnwrap(threadSummary)
  }

  func fetchThreadState(threadId _: String, userId _: String) async throws -> FriendThreadState? {
    await Task.yield()
    if let fetchThreadStateDelay {
      try? await Task.sleep(for: fetchThreadStateDelay)
    }
    return nil
  }

  func listThreadStates(threadId _: String) async throws -> [FriendThreadState] {
    await Task.yield()
    if let fetchThreadStateDelay {
      try? await Task.sleep(for: fetchThreadStateDelay)
    }
    return threadStates
  }

  func fetchMessagePayload(messageId _: String) async throws -> FriendMessage {
    await Task.yield()
    try XCTUnwrap(sentMessage)
  }

  func fetchMessageSyncPayloadV2(messageId _: String) async throws -> FriendMessage {
    await Task.yield()
    try XCTUnwrap(sentMessage)
  }

  func toggleMessageReaction(
    messageId: String,
    emoji: String,
    attachmentId: String?
  ) async throws -> FriendMessage {
    await Task.yield()
    let message = try XCTUnwrap(threadMessages.first { $0.id == messageId })
    return message.toggledReaction(emoji: emoji, attachmentId: attachmentId)
  }

  func createAbuseReport(
    threadId: String,
    reportedUserId: String,
    messageId: String?,
    reason: FriendAbuseReportReason
  ) async throws {
    await Task.yield()
    createdReport = (threadId, reportedUserId, messageId, reason)
  }

  func blockUserPair(otherUserId: String) async throws {
    await Task.yield()
    blockedUserId = otherUserId
  }

  func uploadImageAttachment(threadId _: String, image _: ImageAttachment) async throws
    -> FriendOutgoingAttachment
  {
    await Task.yield()
    if !uploadedAttachmentsQueue.isEmpty {
      return uploadedAttachmentsQueue.removeFirst()
    }
    return uploadedAttachment
      ?? FriendOutgoingAttachment(
        attachmentId: UUID().uuidString,
        storagePath: "thread-1/viewer-1/test.jpg",
        mimeType: "image/jpeg",
        byteSize: 1024,
        width: 200,
        height: 200
      )
  }

  func downloadAttachmentData(path _: String) async throws -> Data {
    await Task.yield()
    return Data()
  }
}

@MainActor
private final class MockFriendsRealtimeCoordinator: FriendsMessagingRealtimeCoordinating {
  var canBroadcastTyping = true
  private(set) var startThreadSubscriptionCallCount = 0
  private(set) var stopThreadSubscriptionCallCount = 0
  private(set) var typingStartCallCount = 0
  private(set) var typingStopCallCount = 0

  func startForAuthenticatedUser(viewerUserId _: String) async {
    await Task.yield()
  }

  func stopForAuthenticatedUser() async {
    await Task.yield()
  }

  func handleAppDidBecomeActive() async {
    await Task.yield()
  }

  func setFriendsFeedVisible(_: Bool) {}

  func setVisibleThreadIds(_: [String]) {}

  func setActiveThread(threadId _: String, viewerUserId _: String) async {
    startThreadSubscriptionCallCount += 1
    await Task.yield()
  }

  func clearActiveThread(threadId _: String) async {
    stopThreadSubscriptionCallCount += 1
    await Task.yield()
  }

  func startThreadListSubscription(viewerUserId _: String) async {
    await Task.yield()
  }

  func stopThreadListSubscription() async {
    await Task.yield()
  }

  func startThreadSubscription(threadId _: String, viewerUserId _: String) async {
    startThreadSubscriptionCallCount += 1
    await Task.yield()
  }

  func stopThreadSubscription(threadId _: String) async {
    stopThreadSubscriptionCallCount += 1
    await Task.yield()
  }

  func sendTypingStart(threadId _: String, userId _: String) async -> Bool {
    typingStartCallCount += 1
    await Task.yield()
    return canBroadcastTyping
  }

  func sendTypingStop(threadId _: String, userId _: String) async -> Bool {
    typingStopCallCount += 1
    await Task.yield()
    return canBroadcastTyping
  }
}
