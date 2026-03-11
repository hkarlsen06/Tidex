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
          gross: 1200
        ),
        tax_enabled: true,
        tax_percentage: 12.5,
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
    return FriendsComposerDraftStore(container: container, storeActor: storeActor)
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

  init(previews: [SharerShiftPreview]) {
    self.previews = previews
  }

  func fetchShiftPreviews(sharerIds: [String], forceRefresh _: Bool) async throws
    -> [SharerShiftPreview]
  {
    await Task.yield()
    requestedSharerIds.append(sharerIds)
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
  var threadSummary: FriendThread?
  var threadMessages: [FriendMessage] = []
  var listThreadMessagesHandler:
    ((String, Int, FriendMessageCursor?) async throws -> [FriendMessage])?
  var sendError: Error?
  var lastSentReplyToMessageId: String?
  var lastSentMetadataData: Data?
  var createdReport:
    (threadId: String, reportedUserId: String, messageId: String?, reason: FriendAbuseReportReason)?
  var blockedUserId: String?
  var uploadedAttachment: FriendOutgoingAttachment?

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
    attachments _: [FriendOutgoingAttachment],
    metadataData: Data?
  ) async throws -> FriendMessage {
    await Task.yield()
    lastSentReplyToMessageId = replyToMessageId
    lastSentMetadataData = metadataData
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

  func fetchThreadState(threadId _: String, userId _: String) async throws -> FriendThreadState? {
    await Task.yield()
    return nil
  }

  func fetchMessagePayload(messageId _: String) async throws -> FriendMessage {
    await Task.yield()
    try XCTUnwrap(sentMessage)
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
