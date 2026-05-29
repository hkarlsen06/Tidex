import CoreGraphics
import ExyteChat
import XCTest

@testable import Tidex

final class FriendsThreadExyteChatTests: XCTestCase {
  func testFriendsChatLinkifierDetectsTidexDeepLinks() {
    let links = FriendsChatMessageLinkifier.links(in: "Open tidex://settings/pay when ready")

    XCTAssertEqual(links.map(\.text), ["tidex://settings/pay"])
    XCTAssertEqual(links.map(\.url.absoluteString), ["tidex://settings/pay"])
  }

  func testFriendsChatLinkifierDetectsBareWebDomains() {
    let links = FriendsChatMessageLinkifier.links(in: "See www.tidex.no for details")

    XCTAssertEqual(links.map(\.text), ["www.tidex.no"])
    XCTAssertEqual(links.map(\.url.absoluteString), ["https://www.tidex.no"])
  }

  func testFriendsChatLinkifierTrimsTrailingSentencePunctuation() {
    let links = FriendsChatMessageLinkifier.links(in: "Pay setup: tidex://settings/pay.")

    XCTAssertEqual(links.map(\.text), ["tidex://settings/pay"])
    XCTAssertEqual(links.map(\.url.absoluteString), ["tidex://settings/pay"])
  }

  func testCurrentUserMenuItemsIncludeEditAndDeleteForTextMessage() {
    let message = Message(
      id: "message-1",
      user: User(id: "viewer", name: "Viewer", avatarURL: nil, isCurrentUser: true),
      createdAt: Date(),
      text: "Hello"
    )

    XCTAssertEqual(
      FriendsThreadMessageMenuAction.menuItems(for: message),
      [.reply, .copy, .edit, .delete]
    )
  }

  func testCounterpartMenuItemsPreferReportForMediaOnlyMessage() {
    let message = Message(
      id: "message-2",
      user: User(id: "other", name: "Other", avatarURL: nil, isCurrentUser: false),
      createdAt: Date(),
      text: ""
    )

    XCTAssertEqual(
      FriendsThreadMessageMenuAction.menuItems(for: message),
      [.reply, .report]
    )
  }

  func testCounterpartMenuItemsIncludeForwardForShiftSnapshotMessage() {
    let exyteMessage = FriendsThreadExyteMessageFactory.makeMessage(
      makeMessage(
        id: "message-shift",
        senderUserId: "other",
        createdAt: Date(),
        body: nil,
        metadataData: makeShiftSnapshotMetadataData()
      ),
      context: FriendsThreadExyteMessageFactory.Context(
        messagesById: [:],
        viewerUserId: "viewer",
        currentUserDisplayName: "Viewer Person",
        counterpartDisplayName: "Other Person",
        counterpartAvatarUrl: nil,
        latestOutgoingMessageId: nil,
        readReceiptMessageId: nil
      )
    )

    XCTAssertEqual(
      FriendsThreadMessageMenuAction.menuItems(for: exyteMessage),
      [.reply, .forward, .report]
    )
  }

  func testAttachmentTapGuardSuppressesTapImmediatelyAfterMenuRecognition() {
    let now = Date(timeIntervalSince1970: 1_775_433_600)
    let suppressedUntil = FriendsThreadAttachmentTapGuard.suppressedUntilAfterMenuRecognition(
      now: now
    )

    XCTAssertFalse(
      FriendsThreadAttachmentTapGuard.shouldHandleTap(
        suppressedUntil: suppressedUntil,
        now: now.addingTimeInterval(0.1)
      )
    )
  }

  func testAttachmentTapGuardAllowsTapAfterSuppressionWindowExpires() {
    let now = Date(timeIntervalSince1970: 1_775_433_600)
    let suppressedUntil = FriendsThreadAttachmentTapGuard.suppressedUntilAfterMenuRecognition(
      now: now
    )

    XCTAssertTrue(
      FriendsThreadAttachmentTapGuard.shouldHandleTap(
        suppressedUntil: suppressedUntil,
        now: suppressedUntil
      )
    )
  }

  func testSharingDeepLinkPreservesExistingPathWhenChatIsShowing() {
    XCTAssertTrue(
      SharingDeepLinkNavigationPathResolver.shouldPreserveExistingPath(
        navigationPathIsEmpty: false,
        selectedSharerId: nil,
        activeChatHighlightUserId: "friend-1"
      )
    )
  }

  func testSharingDeepLinkResetsPathWhenSharerDetailIsAlreadyShowing() {
    XCTAssertFalse(
      SharingDeepLinkNavigationPathResolver.shouldPreserveExistingPath(
        navigationPathIsEmpty: false,
        selectedSharerId: "friend-1",
        activeChatHighlightUserId: "friend-1"
      )
    )
  }

  func testShiftSnapshotNavigationRoutesOwnSnapshotToShiftsHighlight() {
    let deepLink = FriendsThreadShiftSnapshotNavigationResolver.deepLink(
      for: makeShiftSnapshot(ownerUserId: "viewer-1", shiftDate: "2026-04-04"),
      viewerUserId: "viewer-1",
      cachedFriends: .init(sharers: [], chatOnlyUserIds: [])
    )

    XCTAssertEqual(
      deepLink,
      .shifts(dates: ["2026-04-04"], shiftIds: nil, action: .highlight)
    )
  }

  func testShiftSnapshotNavigationRoutesVisibleSharerToSharingHighlight() {
    let deepLink = FriendsThreadShiftSnapshotNavigationResolver.deepLink(
      for: makeShiftSnapshot(ownerUserId: "owner-1", shiftDate: "2026-04-04"),
      viewerUserId: "viewer-1",
      cachedFriends: .init(
        sharers: [
          SharedUser(
            id: "owner-1",
            email: nil,
            phone: nil,
            firstName: "Owner",
            profilePictureUrl: nil,
            oauthAvatarUrl: nil,
            sharedAt: "2026-04-01T10:00:00Z",
            showEarnings: true,
            hidden: false
          )
        ],
        chatOnlyUserIds: []
      )
    )

    XCTAssertEqual(
      deepLink,
      .sharing(sharerId: "owner-1", highlightDates: ["2026-04-04"], changes: nil)
    )
  }

  func testShiftSnapshotNavigationDoesNotRouteChatOnlySharer() {
    let deepLink = FriendsThreadShiftSnapshotNavigationResolver.deepLink(
      for: makeShiftSnapshot(ownerUserId: "owner-1", shiftDate: "2026-04-04"),
      viewerUserId: "viewer-1",
      cachedFriends: .init(
        sharers: [
          SharedUser(
            id: "owner-1",
            email: nil,
            phone: nil,
            firstName: "Owner",
            profilePictureUrl: nil,
            oauthAvatarUrl: nil,
            sharedAt: "2026-04-01T10:00:00Z",
            showEarnings: false,
            hidden: false
          )
        ],
        chatOnlyUserIds: ["owner-1"]
      )
    )

    XCTAssertNil(deepLink)
  }

  func testShiftSnapshotNavigationRoutesHiddenSharerToSharingHighlight() {
    let deepLink = FriendsThreadShiftSnapshotNavigationResolver.deepLink(
      for: makeShiftSnapshot(ownerUserId: "owner-1", shiftDate: "2026-04-04"),
      viewerUserId: "viewer-1",
      cachedFriends: .init(
        sharers: [
          SharedUser(
            id: "owner-1",
            email: nil,
            phone: nil,
            firstName: "Owner",
            profilePictureUrl: nil,
            oauthAvatarUrl: nil,
            sharedAt: "2026-04-01T10:00:00Z",
            showEarnings: false,
            hidden: true
          )
        ],
        chatOnlyUserIds: []
      )
    )

    XCTAssertEqual(
      deepLink,
      .sharing(sharerId: "owner-1", highlightDates: ["2026-04-04"], changes: nil)
    )
  }

  func testReadReceiptTargetsLatestOutgoingMessageAtOrBeforeCounterpartReadMarker() {
    let baseDate = Date(timeIntervalSince1970: 1_731_000_000)
    let messages = [
      makeMessage(id: "out-1", senderUserId: "viewer", createdAt: baseDate),
      makeMessage(id: "in-1", senderUserId: "other", createdAt: baseDate.addingTimeInterval(30)),
      makeMessage(id: "out-2", senderUserId: "viewer", createdAt: baseDate.addingTimeInterval(60)),
    ]

    XCTAssertEqual(
      FriendsThreadMessageStatusResolver.readReceiptMessageId(
        messages: messages,
        viewerUserId: "viewer",
        counterpartLastReadMessageId: "in-1",
        counterpartLastReadAt: baseDate.addingTimeInterval(31)
      ),
      "out-1"
    )
  }

  func testReadReceiptFallsBackToBackendTupleOrderingWhenCounterpartReadMessageIsNotLoaded() {
    let readAt = Date(timeIntervalSince1970: 1_731_000_000)
    let messages = [
      makeMessage(id: "out-a", senderUserId: "viewer", createdAt: readAt.addingTimeInterval(-1)),
      makeMessage(id: "out-b", senderUserId: "viewer", createdAt: readAt),
      makeMessage(id: "out-z", senderUserId: "viewer", createdAt: readAt),
      makeMessage(id: "out-later", senderUserId: "viewer", createdAt: readAt.addingTimeInterval(1)),
    ]

    XCTAssertEqual(
      FriendsThreadMessageStatusResolver.readReceiptMessageId(
        messages: messages,
        viewerUserId: "viewer",
        counterpartLastReadMessageId: "out-b",
        counterpartLastReadAt: readAt
      ),
      "out-b"
    )
  }

  func testReadReceiptNormalizesViewerUserIdAndSkipsDeletedMessages() {
    let baseDate = Date(timeIntervalSince1970: 1_731_000_000)
    let messages = [
      makeMessage(
        id: "out-deleted",
        senderUserId: "viewer",
        createdAt: baseDate,
        deletedAt: baseDate.addingTimeInterval(5)
      ),
      makeMessage(
        id: "out-visible", senderUserId: "viewer", createdAt: baseDate.addingTimeInterval(10)),
    ]

    XCTAssertEqual(
      FriendsThreadMessageStatusResolver.readReceiptMessageId(
        messages: messages,
        viewerUserId: " viewer ",
        counterpartLastReadMessageId: "out-visible",
        counterpartLastReadAt: baseDate.addingTimeInterval(10)
      ),
      "out-visible"
    )
  }

  func testFactoryMapsViewerReactionForMenuSelectionState() {
    let message = makeMessage(
      id: "message-3",
      senderUserId: "other",
      createdAt: Date(),
      reactions: [
        FriendMessageReaction(emoji: "🔥", count: 3, viewerHasReacted: true),
        FriendMessageReaction(emoji: "😂", count: 2, viewerHasReacted: false),
      ]
    )

    let exyteMessage = FriendsThreadExyteMessageFactory.makeMessage(
      message,
      context: FriendsThreadExyteMessageFactory.Context(
        messagesById: [:],
        viewerUserId: "viewer",
        currentUserDisplayName: "Viewer Person",
        counterpartDisplayName: "Other Person",
        counterpartAvatarUrl: nil,
        latestOutgoingMessageId: nil,
        readReceiptMessageId: nil
      )
    )

    XCTAssertEqual(exyteMessage.reactions.count, 1)
    XCTAssertEqual(exyteMessage.reactions.first?.user.id, "viewer")
    XCTAssertTrue(exyteMessage.reactions.first?.user.isCurrentUser ?? false)
    if case .emoji(let emoji)? = exyteMessage.reactions.first?.type {
      XCTAssertEqual(emoji, "🔥")
    } else {
      XCTFail("Expected emoji reaction")
    }
  }

  func testPresentationIDStaysStableAcrossOptimisticAndConfirmedOutgoingMessage() {
    let optimisticMessage = makeMessage(
      id: "local-client-1",
      senderUserId: "viewer",
      createdAt: Date()
    )
    let confirmedMessage = FriendMessage(
      id: "message-1",
      threadId: optimisticMessage.threadId,
      senderUserId: optimisticMessage.senderUserId,
      messageType: optimisticMessage.messageType,
      body: optimisticMessage.body,
      clientId: optimisticMessage.clientId,
      replyToMessageId: optimisticMessage.replyToMessageId,
      createdAt: optimisticMessage.createdAt.addingTimeInterval(1),
      editedAt: nil,
      deletedAt: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    XCTAssertEqual(
      FriendsThreadMessagePresentationID.make(for: optimisticMessage, viewerUserId: "viewer"),
      FriendsThreadMessagePresentationID.make(for: confirmedMessage, viewerUserId: "viewer")
    )
  }

  func testLogicalRowIdentityNormalizesOutgoingClientID() {
    let message = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "viewer",
      messageType: .user,
      body: "Hello",
      clientId: " Client-1 ",
      replyToMessageId: nil,
      createdAt: Date(),
      editedAt: nil,
      deletedAt: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    XCTAssertEqual(message.logicalRowIdentity(viewerUserId: "viewer"), "client:client-1")
    XCTAssertEqual(message.logicalRowIdentity(viewerUserId: "other"), "message:message-1")
  }

  func testPresentationIDsDoNotRegisterConfirmedOutgoingMessageAsAppend() {
    let optimisticMessage = makeMessage(
      id: "local-client-1",
      senderUserId: "viewer",
      createdAt: Date()
    )
    let confirmedMessage = FriendMessage(
      id: "message-1",
      threadId: optimisticMessage.threadId,
      senderUserId: optimisticMessage.senderUserId,
      messageType: optimisticMessage.messageType,
      body: optimisticMessage.body,
      clientId: optimisticMessage.clientId,
      replyToMessageId: optimisticMessage.replyToMessageId,
      createdAt: optimisticMessage.createdAt.addingTimeInterval(1),
      editedAt: nil,
      deletedAt: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    let oldPresentationIDs = [
      FriendsThreadMessagePresentationID.make(for: optimisticMessage, viewerUserId: "viewer")
    ]
    let newPresentationIDs = [
      FriendsThreadMessagePresentationID.make(for: confirmedMessage, viewerUserId: "viewer")
    ]

    XCTAssertEqual(oldPresentationIDs, newPresentationIDs)
    XCTAssertFalse(
      FriendsThreadMessageListChangeResolver.isAppendedMessage(
        oldMessageIDs: oldPresentationIDs,
        newMessageIDs: newPresentationIDs
      )
    )
  }

  func testListChangeResolverIdentifiesAppendedOutgoingMessage() {
    XCTAssertTrue(
      FriendsThreadMessageListChangeResolver.isAppendedMessage(
        oldMessageIDs: ["message-1", "message-2"],
        newMessageIDs: ["message-1", "message-2", "message-3"]
      )
    )
    XCTAssertFalse(
      FriendsThreadMessageListChangeResolver.isPrependedMessage(
        oldMessageIDs: ["message-1", "message-2"],
        newMessageIDs: ["message-1", "message-2", "message-3"]
      )
    )
  }

  func testListChangeResolverIdentifiesPrependedOlderMessages() {
    XCTAssertTrue(
      FriendsThreadMessageListChangeResolver.isPrependedMessage(
        oldMessageIDs: ["message-2", "message-3"],
        newMessageIDs: ["message-1", "message-2", "message-3"]
      )
    )
    XCTAssertFalse(
      FriendsThreadMessageListChangeResolver.isAppendedMessage(
        oldMessageIDs: ["message-2", "message-3"],
        newMessageIDs: ["message-1", "message-2", "message-3"]
      )
    )
  }

  func testListChangeResolverClassifiesOutgoingAppendSeparately() {
    XCTAssertEqual(
      FriendsThreadMessageListChangeResolver.resolve(
        oldMessageIDs: ["message-1", "message-2"],
        newMessageIDs: ["message-1", "message-2", "message-3"],
        lastMessageSenderId: "viewer",
        viewerUserId: "viewer"
      ),
      .appendedOutgoing
    )
  }

  func testListChangeResolverClassifiesIncomingAppendSeparately() {
    XCTAssertEqual(
      FriendsThreadMessageListChangeResolver.resolve(
        oldMessageIDs: ["message-1", "message-2"],
        newMessageIDs: ["message-1", "message-2", "message-3"],
        lastMessageSenderId: "other",
        viewerUserId: "viewer"
      ),
      .appendedIncoming
    )
  }

  func testOutgoingAppendScrollResolverTargetsNewOutgoingMessageWhenPending() {
    XCTAssertEqual(
      FriendsThreadOutgoingAppendScrollResolver.scrollTarget(
        change: .appendedOutgoing,
        shouldScrollToNextOutgoingMessage: true,
        newMessageIDs: ["message-1", "message-2", "message-3"]
      ),
      "message-3"
    )
  }

  func testOutgoingAppendScrollResolverIgnoresNonPendingOrIncomingChanges() {
    XCTAssertNil(
      FriendsThreadOutgoingAppendScrollResolver.scrollTarget(
        change: .appendedOutgoing,
        shouldScrollToNextOutgoingMessage: false,
        newMessageIDs: ["message-1", "message-2", "message-3"]
      )
    )
    XCTAssertNil(
      FriendsThreadOutgoingAppendScrollResolver.scrollTarget(
        change: .appendedIncoming,
        shouldScrollToNextOutgoingMessage: true,
        newMessageIDs: ["message-1", "message-2", "message-3"]
      )
    )
  }

  func testIncomingAppendResolverShowsNewMessagesPillWhenUserIsScrolledUp() {
    XCTAssertEqual(
      FriendsThreadIncomingAppendResolver.resolve(
        previousMessageCount: 3,
        unreadIncomingCount: 0,
        isIncoming: true,
        isPinnedToBottom: false
      ),
      FriendsThreadIncomingAppendOutcome(
        unreadIncomingCount: 1,
        showsNewMessagesPill: true,
        shouldPlayFeedback: true
      )
    )
  }

  func testIncomingAppendResolverClearsPendingIndicatorWhenThreadIsPinnedToBottom() {
    XCTAssertEqual(
      FriendsThreadIncomingAppendResolver.resolve(
        previousMessageCount: 3,
        unreadIncomingCount: 2,
        isIncoming: true,
        isPinnedToBottom: true
      ),
      FriendsThreadIncomingAppendOutcome(
        unreadIncomingCount: 0,
        showsNewMessagesPill: false,
        shouldPlayFeedback: false
      )
    )
  }

  func testOutgoingGroupedMessageKeepsTimestampVisible() {
    XCTAssertTrue(
      FriendsThreadMessageStatusResolver.shouldShowTimestamp(
        for: makeMessage(id: "message-1", senderUserId: "viewer", createdAt: Date()),
        isCurrentUser: true,
        groupContext: FriendsChatMessageGroupContext(position: .leading, isCurrentUser: true),
        messageStatus: nil
      )
    )
  }

  func testIncomingGroupedMessageStillHidesTimestampUntilEndOfGroup() {
    XCTAssertFalse(
      FriendsThreadMessageStatusResolver.shouldShowTimestamp(
        for: makeMessage(id: "message-1", senderUserId: "other", createdAt: Date()),
        isCurrentUser: false,
        groupContext: FriendsChatMessageGroupContext(position: .leading, isCurrentUser: false),
        messageStatus: nil
      )
    )
  }

  func testReplySwipeResolverTriggersAtShiftCardThreshold() {
    XCTAssertEqual(
      FriendsChatReplySwipeResolver.outcome(
        offset: FriendsChatReplySwipeResolver.actionWidth
          * FriendsChatReplySwipeResolver.actionThreshold,
        velocity: 0,
        allowedDirection: .right
      ),
      .trigger
    )
  }

  func testReplySwipeResolverTriggersOnFastSwipeBeforeThreshold() {
    XCTAssertEqual(
      FriendsChatReplySwipeResolver.outcome(
        offset: 12,
        velocity: FriendsChatReplySwipeResolver.velocityThreshold + 1,
        allowedDirection: .right
      ),
      .trigger
    )
  }

  func testReplySwipeResolverIgnoresWrongDirectionAndVerticalDrag() {
    XCTAssertEqual(
      FriendsChatReplySwipeResolver.clampedOffset(
        horizontal: 28,
        vertical: 2,
        allowedDirection: .left
      ),
      0
    )

    XCTAssertNil(
      FriendsChatReplySwipeResolver.clampedOffset(
        horizontal: 28,
        vertical: 32,
        allowedDirection: .right
      )
    )
  }

  func testTimestampRevealResolverClampsLeftSwipeToColumnWidth() {
    XCTAssertEqual(
      FriendsChatTimestampRevealResolver.clampedRevealOffset(
        horizontal: -120,
        vertical: 4
      ),
      FriendsChatTimestampRevealResolver.revealWidth
    )
  }

  func testTimestampRevealResolverIgnoresRightSwipeAndVerticalDrag() {
    XCTAssertEqual(
      FriendsChatTimestampRevealResolver.clampedRevealOffset(
        horizontal: 28,
        vertical: 2
      ),
      0
    )

    XCTAssertNil(
      FriendsChatTimestampRevealResolver.clampedRevealOffset(
        horizontal: -28,
        vertical: 32
      )
    )
  }

  func testTimestampRevealResolverUsesOppositeBackgroundSpacerForSender() {
    XCTAssertEqual(
      FriendsChatTimestampRevealResolver.activeSurface(isCurrentUser: true),
      .leadingSpacer
    )

    XCTAssertEqual(
      FriendsChatTimestampRevealResolver.activeSurface(isCurrentUser: false),
      .trailingSpacer
    )
  }

  func testTimestampRevealResolverReservesRevealWidthForIncomingContent() {
    XCTAssertEqual(
      FriendsChatTimestampRevealResolver.contentMaxWidth(baseWidth: 360, isCurrentUser: true),
      360
    )

    XCTAssertEqual(
      FriendsChatTimestampRevealResolver.contentMaxWidth(baseWidth: 360, isCurrentUser: false),
      296
    )
  }

  func testPanGestureResolverUsesConfiguredMinimumDistance() {
    XCTAssertFalse(
      FriendsChatPanGestureResolver.hasPassedMinimumDistance(
        translation: CGSize(width: 8, height: 6),
        minimumDistance: FriendsChatReplySwipeResolver.minimumDistance
      )
    )

    XCTAssertTrue(
      FriendsChatPanGestureResolver.hasPassedMinimumDistance(
        translation: CGSize(width: 16, height: 12),
        minimumDistance: FriendsChatReplySwipeResolver.minimumDistance
      )
    )
  }

  func testPanGestureResolverBeginsOnlyForHorizontalIntent() {
    XCTAssertTrue(
      FriendsChatPanGestureResolver.hasHorizontalIntent(
        translation: CGSize(width: 24, height: 8)
      )
    )

    XCTAssertFalse(
      FriendsChatPanGestureResolver.hasHorizontalIntent(
        translation: CGSize(width: 8, height: 24)
      )
    )
  }

  func testPanGestureResolverRequiresDirectionalVelocityForReplyAndNavigation() {
    XCTAssertTrue(
      FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: 300, height: 80),
        direction: .right
      )
    )

    XCTAssertTrue(
      FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: -300, height: 80),
        direction: .left
      )
    )

    XCTAssertFalse(
      FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: 300, height: 80),
        direction: .left
      )
    )

    XCTAssertFalse(
      FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: 120, height: 100),
        direction: .right
      )
    )
  }

  func testPanGestureResolverTriggersNavigationBackForRightwardDistanceOrVelocity() {
    XCTAssertTrue(
      FriendsChatPanGestureResolver.shouldTriggerNavigationBack(
        translation: CGSize(
          width: FriendsChatPanGestureResolver.navigationBackDistanceThreshold, height: 4),
        velocity: .zero
      )
    )

    XCTAssertTrue(
      FriendsChatPanGestureResolver.shouldTriggerNavigationBack(
        translation: CGSize(width: 12, height: 2),
        velocity: CGSize(
          width: FriendsChatPanGestureResolver.navigationBackVelocityThreshold, height: 0)
      )
    )
  }

  func testPanGestureResolverDoesNotTriggerNavigationBackForVerticalOrLeftwardDrag() {
    XCTAssertFalse(
      FriendsChatPanGestureResolver.shouldTriggerNavigationBack(
        translation: CGSize(width: 120, height: 130),
        velocity: CGSize(width: 600, height: 0)
      )
    )

    XCTAssertFalse(
      FriendsChatPanGestureResolver.shouldTriggerNavigationBack(
        translation: CGSize(width: -120, height: 2),
        velocity: CGSize(width: -800, height: 0)
      )
    )
  }

  func testLiveEdgeResolverDoesNotTreatFocusedComposerAsPinnedToLatest() {
    XCTAssertFalse(
      FriendsThreadLiveEdgeResolver.shouldStickToLatest(
        isPinnedToBottom: false
      )
    )
  }

  func testLiveEdgeResolverUsesViewportPinState() {
    XCTAssertFalse(
      FriendsThreadLiveEdgeResolver.shouldStickToLatest(
        isPinnedToBottom: false
      )
    )
    XCTAssertTrue(
      FriendsThreadLiveEdgeResolver.shouldStickToLatest(
        isPinnedToBottom: true
      )
    )
  }

  func testCounterpartPreviewNavigationResolverBuildsSharingDeepLink() {
    let preview = SharerShiftPreview(
      sharerId: "friend-1",
      shift: SharedShiftData(
        id: "shift-1",
        user_id: "friend-1",
        job_id: "job-1",
        job_name: "ER",
        job_color: "#4A90E2",
        shift_date: "2026-03-13",
        start_time: "08:00",
        end_time: "16:00",
        computed: SharedShiftComputed(
          id: "shift-1",
          durationHours: 8,
          paidHours: 8,
          basePay: 1200,
          supplementPay: 0,
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
        tax_enabled: false,
        tax_percentage: 0,
        custom_pause_windows: nil,
        custom_supplements: nil,
        recurring_id: nil,
        recurring_anchor_weekday: nil
      ),
      status: .upcoming,
      showEarnings: true,
      currency: "NOK"
    )

    XCTAssertEqual(
      FriendsThreadCounterpartPreviewNavigationResolver.deepLink(for: preview),
      .sharing(
        sharerId: "friend-1",
        highlightDates: ["2026-03-13"],
        changes: [
          AppCoordinator.ShiftChange(
            shiftId: "shift-1",
            date: "2026-03-13",
            op: "updated"
          )
        ]
      )
    )
  }

  func testCounterpartPreviewNavigationResolverReturnsNilWithoutShift() {
    let preview = SharerShiftPreview(
      sharerId: "friend-1",
      shift: nil,
      status: nil,
      showEarnings: false,
      currency: nil
    )

    XCTAssertNil(FriendsThreadCounterpartPreviewNavigationResolver.deepLink(for: preview))
  }

  func testViewportResolverMapsReplyTargetAcrossDateSections() {
    let calendar = Calendar.current
    let firstDay = Date(timeIntervalSince1970: 1_731_000_000)
    let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay) ?? firstDay
    let messages = [
      Message(
        id: "day-1-message-1",
        user: User(id: "viewer", name: "Viewer", avatarURL: nil, isCurrentUser: true),
        createdAt: firstDay,
        text: "Day 1"
      ),
      Message(
        id: "day-2-message-1",
        user: User(id: "viewer", name: "Viewer", avatarURL: nil, isCurrentUser: true),
        createdAt: secondDay,
        text: "Day 2"
      ),
      Message(
        id: "day-2-message-2",
        user: User(id: "other", name: "Other", avatarURL: nil, isCurrentUser: false),
        createdAt: secondDay.addingTimeInterval(60),
        text: "Later"
      ),
    ]

    XCTAssertEqual(
      FriendsThreadChatViewportResolver.indexPath(
        for: "day-1-message-1",
        in: messages
      ),
      IndexPath(row: 0, section: 1)
    )
    XCTAssertEqual(
      FriendsThreadChatViewportResolver.indexPath(
        for: "day-2-message-2",
        in: messages
      ),
      IndexPath(row: 0, section: 0)
    )
    XCTAssertEqual(
      FriendsThreadChatViewportResolver.indexPath(
        for: "day-2-message-1",
        in: messages
      ),
      IndexPath(row: 1, section: 0)
    )
  }

  func testViewportResolverTreatsNearZeroOffsetAsPinnedToBottom() {
    XCTAssertTrue(FriendsThreadChatViewportResolver.isPinnedToBottom(contentOffsetY: 0))
    XCTAssertTrue(FriendsThreadChatViewportResolver.isPinnedToBottom(contentOffsetY: 0.5))
    XCTAssertFalse(FriendsThreadChatViewportResolver.isPinnedToBottom(contentOffsetY: 4))
  }

  func testViewportLayoutSnapshotPreservesPresentedMessageIndexPaths() {
    let calendar = Calendar(identifier: .gregorian)
    let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_731_000_000))
    let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay) ?? firstDay
    let messages = [
      Message(
        id: "day-1-message-1",
        user: User(id: "viewer", name: "Viewer", avatarURL: nil, isCurrentUser: true),
        createdAt: firstDay,
        text: "Day 1"
      ),
      Message(
        id: "day-2-message-1",
        user: User(id: "viewer", name: "Viewer", avatarURL: nil, isCurrentUser: true),
        createdAt: secondDay,
        text: "Day 2"
      ),
      Message(
        id: "day-2-message-2",
        user: User(id: "other", name: "Other", avatarURL: nil, isCurrentUser: false),
        createdAt: secondDay.addingTimeInterval(60),
        text: "Later"
      ),
    ]

    let snapshot = FriendsThreadChatViewportResolver.layoutSnapshot(messages: messages)

    XCTAssertEqual(
      FriendsThreadChatViewportResolver.indexPath(
        for: "day-1-message-1",
        in: snapshot
      ),
      IndexPath(row: 0, section: 1)
    )
    XCTAssertEqual(
      FriendsThreadChatViewportResolver.indexPath(
        for: "day-2-message-2",
        in: snapshot
      ),
      IndexPath(row: 0, section: 0)
    )
    XCTAssertEqual(
      FriendsThreadChatViewportResolver.indexPath(
        for: "day-2-message-1",
        in: snapshot
      ),
      IndexPath(row: 1, section: 0)
    )
  }

  func testViewportRequestResolverPrefersReplyTargetOverRestoreTarget() {
    let restoreTarget = makeMessage(
      id: "older-message",
      senderUserId: "other",
      createdAt: Date(timeIntervalSince1970: 1_731_000_000)
    )
    let replyTarget = FriendMessage(
      id: "reply-target",
      threadId: "thread-1",
      senderUserId: "viewer",
      messageType: .user,
      body: "Reply target",
      clientId: " Client-1 ",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_731_000_060),
      editedAt: nil,
      deletedAt: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    XCTAssertEqual(
      FriendsThreadChatViewportRequestResolver.request(
        replyTargetMessageId: replyTarget.id,
        restoreTargetMessageId: restoreTarget.id,
        liveEdgeTargetPresentedMessageID: nil,
        messages: [restoreTarget, replyTarget],
        viewerUserId: "viewer"
      ),
      FriendsThreadChatViewportScrollRequest(
        kind: .reply,
        messageID: replyTarget.id,
        presentedMessageID: "client:client-1"
      )
    )
  }

  func testViewportRequestResolverFallsBackToRestoreTargetWhenReplyTargetIsMissing() {
    let restoreTarget = makeMessage(
      id: "older-message",
      senderUserId: "other",
      createdAt: Date(timeIntervalSince1970: 1_731_000_000)
    )

    XCTAssertEqual(
      FriendsThreadChatViewportRequestResolver.request(
        replyTargetMessageId: "missing-message",
        restoreTargetMessageId: restoreTarget.id,
        liveEdgeTargetPresentedMessageID: nil,
        messages: [restoreTarget],
        viewerUserId: "viewer"
      ),
      FriendsThreadChatViewportScrollRequest(
        kind: .restore,
        messageID: restoreTarget.id,
        presentedMessageID: "message:\(restoreTarget.id)"
      )
    )
  }

  func testViewportRequestResolverFallsBackToLiveEdgeTargetWhenOtherTargetsAreMissing() {
    XCTAssertEqual(
      FriendsThreadChatViewportRequestResolver.request(
        replyTargetMessageId: nil,
        restoreTargetMessageId: nil,
        liveEdgeTargetPresentedMessageID: "client:client-1",
        messages: [],
        viewerUserId: "viewer"
      ),
      FriendsThreadChatViewportScrollRequest(
        kind: .liveEdge,
        messageID: "client:client-1",
        presentedMessageID: "client:client-1"
      )
    )
  }

  func testViewportRequestResolverResolvesPresentedMessageIDForHighlightedOutgoingMessage() {
    let highlightedMessage = FriendMessage(
      id: "reply-target",
      threadId: "thread-1",
      senderUserId: "viewer",
      messageType: .user,
      body: "Reply target",
      clientId: " Client-1 ",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_731_000_060),
      editedAt: nil,
      deletedAt: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    XCTAssertEqual(
      FriendsThreadChatViewportRequestResolver.presentedMessageID(
        for: highlightedMessage.id,
        messages: [highlightedMessage],
        viewerUserId: "viewer"
      ),
      "client:client-1"
    )
  }

  func testViewportScrollDeferralResolverDefersInitialReplyScroll() {
    XCTAssertTrue(
      FriendsThreadChatViewportScrollDeferralResolver.shouldDefer(
        kind: .reply,
        hasDeferredInitialReplyScroll: false,
        isUserInteracting: false
      )
    )

    XCTAssertFalse(
      FriendsThreadChatViewportScrollDeferralResolver.shouldDefer(
        kind: .reply,
        hasDeferredInitialReplyScroll: true,
        isUserInteracting: false
      )
    )
  }

  func testViewportScrollDeferralResolverDefersReplyWhileUserInteractionIsSettling() {
    XCTAssertTrue(
      FriendsThreadChatViewportScrollDeferralResolver.shouldDefer(
        kind: .reply,
        hasDeferredInitialReplyScroll: true,
        isUserInteracting: true
      )
    )
  }

  func testViewportScrollDeferralResolverKeepsExistingRestoreAndLiveEdgeBehavior() {
    XCTAssertTrue(
      FriendsThreadChatViewportScrollDeferralResolver.shouldDefer(
        kind: .restore,
        hasDeferredInitialReplyScroll: false,
        isUserInteracting: true
      )
    )

    XCTAssertFalse(
      FriendsThreadChatViewportScrollDeferralResolver.shouldDefer(
        kind: .restore,
        hasDeferredInitialReplyScroll: false,
        isUserInteracting: false
      )
    )

    XCTAssertFalse(
      FriendsThreadChatViewportScrollDeferralResolver.shouldDefer(
        kind: .liveEdge,
        hasDeferredInitialReplyScroll: false,
        isUserInteracting: true
      )
    )
  }

  func testVisibleMessageResolverIgnoresSyntheticTypingIndicatorRow() {
    XCTAssertNil(
      FriendsThreadVisibleMessageResolver.messageID(
        for: FriendsThreadExyteMessageFactory.typingIndicatorMessageID,
        messages: [
          makeMessage(
            id: "message-1",
            senderUserId: "other",
            createdAt: Date(timeIntervalSince1970: 1_731_000_000)
          )
        ],
        viewerUserId: "viewer"
      )
    )
  }

  func testVisibleMessageResolverMapsPresentedOutgoingMessageIDBackToMessageID() {
    let outgoingMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "viewer",
      messageType: .user,
      body: "Hello",
      clientId: " Client-1 ",
      replyToMessageId: nil,
      createdAt: Date(timeIntervalSince1970: 1_731_000_000),
      editedAt: nil,
      deletedAt: nil,
      attachments: [],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    XCTAssertEqual(
      FriendsThreadVisibleMessageResolver.messageID(
        for: "client:client-1",
        messages: [outgoingMessage],
        viewerUserId: "viewer"
      ),
      outgoingMessage.id
    )
  }

  func testHighlightRedrawResolverMarksOnlyTheHighlightedPresentedMessage() {
    let messages = [
      Message(
        id: "message-1",
        user: User(id: "viewer", name: "Viewer", avatarURL: nil, isCurrentUser: true),
        createdAt: Date(timeIntervalSince1970: 1_731_000_000),
        text: "One"
      ),
      Message(
        id: "message-2",
        user: User(id: "other", name: "Other", avatarURL: nil, isCurrentUser: false),
        createdAt: Date(timeIntervalSince1970: 1_731_000_060),
        text: "Two"
      ),
    ]

    let highlightedMessages = FriendsThreadExyteHighlightRedrawResolver.applyingHighlightMarker(
      to: messages,
      highlightedPresentedMessageID: "message-2"
    )

    XCTAssertEqual(highlightedMessages[0].text, "One")
    XCTAssertNotEqual(highlightedMessages[1].text, "Two")
    XCTAssertTrue(highlightedMessages[1].text.hasPrefix("Two"))
    XCTAssertFalse(FriendsThreadExyteHighlightRedrawResolver.isHighlighted(highlightedMessages[0]))
    XCTAssertTrue(FriendsThreadExyteHighlightRedrawResolver.isHighlighted(highlightedMessages[1]))
    XCTAssertEqual(
      FriendsThreadExyteHighlightRedrawResolver.visibleText(for: highlightedMessages[1]),
      "Two"
    )
  }

  func testMenuItemsIgnoreTransientHighlightMarkerForMediaOnlyMessage() {
    let highlightedMediaOnlyMessage =
      FriendsThreadExyteHighlightRedrawResolver
      .applyingHighlightMarker(
        to: [
          Message(
            id: "message-2",
            user: User(id: "other", name: "Other", avatarURL: nil, isCurrentUser: false),
            createdAt: Date(),
            text: ""
          )
        ],
        highlightedPresentedMessageID: "message-2"
      )[0]

    XCTAssertEqual(
      FriendsThreadMessageMenuAction.menuItems(for: highlightedMediaOnlyMessage),
      [.reply, .report]
    )
  }

  func testHighlightRefreshResolverIgnoresVisibilityOnlyScrollChurn() {
    XCTAssertFalse(
      FriendsThreadHighlightRefreshResolver.shouldRefreshRows(
        force: false,
        highlightedPresentedMessageID: "message-2",
        lastHighlightedPresentedMessageID: "message-2"
      )
    )
  }

  func testHighlightRefreshResolverRefreshesWhenHighlightedMessageChanges() {
    XCTAssertTrue(
      FriendsThreadHighlightRefreshResolver.shouldRefreshRows(
        force: false,
        highlightedPresentedMessageID: "message-2",
        lastHighlightedPresentedMessageID: "message-1"
      )
    )
  }

  func testHighlightRefreshResolverHonorsForcedRefreshes() {
    XCTAssertTrue(
      FriendsThreadHighlightRefreshResolver.shouldRefreshRows(
        force: true,
        highlightedPresentedMessageID: "message-2",
        lastHighlightedPresentedMessageID: "message-2"
      )
    )
  }

  func testImageGalleryResolverCollectsImageAttachmentsInChatOrder() {
    let baseDate = Date(timeIntervalSince1970: 1_731_000_000)
    let olderMessage = FriendMessage(
      id: "message-1",
      threadId: "thread-1",
      senderUserId: "viewer",
      messageType: .user,
      body: nil,
      clientId: "message-1",
      replyToMessageId: nil,
      createdAt: baseDate,
      editedAt: nil,
      deletedAt: nil,
      attachments: [
        makeImageAttachment(id: "image-2", attachmentIndex: 2),
        makeImageAttachment(id: "image-0", attachmentIndex: 0),
        makeImageAttachment(id: "image-1", attachmentIndex: 1),
      ],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )
    let newerMessage = FriendMessage(
      id: "message-2",
      threadId: "thread-1",
      senderUserId: "other",
      messageType: .user,
      body: nil,
      clientId: "message-2",
      replyToMessageId: nil,
      createdAt: baseDate.addingTimeInterval(60),
      editedAt: nil,
      deletedAt: nil,
      attachments: [
        makeImageAttachment(id: "image-3", attachmentIndex: 0)
      ],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    XCTAssertEqual(
      FriendsThreadImageGalleryResolver.imageAttachments(
        messages: [olderMessage, newerMessage]
      ).map(\.id),
      ["image-0", "image-1", "image-2", "image-3"]
    )
  }

  func testChatProjectionPrecomputesLookupsAndRowContext() {
    let baseDate = Date(timeIntervalSince1970: 1_731_000_000)
    let outgoing = makeMessage(
      id: "outgoing",
      senderUserId: "viewer",
      createdAt: baseDate
    )
    let incoming = FriendMessage(
      id: "incoming",
      threadId: "thread-1",
      senderUserId: "other",
      messageType: .user,
      body: "Photo",
      clientId: "incoming",
      replyToMessageId: nil,
      createdAt: baseDate.addingTimeInterval(60),
      editedAt: nil,
      deletedAt: nil,
      attachments: [
        makeImageAttachment(id: "image-0", attachmentIndex: 0)
      ],
      reactions: [],
      sendState: .sent,
      failureMessage: nil
    )

    let projection = FriendsThreadChatProjection.make(
      input: .init(
        messages: [outgoing, incoming],
        viewerUserId: "viewer",
        currentUserDisplayName: "Viewer Person",
        counterpartDisplayName: "Other Person",
        counterpartAvatarUrl: nil,
        quotedMessagesById: [:],
        counterpartLastReadMessageId: outgoing.id,
        counterpartLastReadAt: baseDate.addingTimeInterval(1),
        showsTypingIndicator: true,
        typingIndicatorCreatedAt: incoming.createdAt,
        reactionAttachmentTargets: [:]
      )
    )

    XCTAssertEqual(projection.presentedMessageIDs, ["client:outgoing", "message:incoming"])
    XCTAssertEqual(projection.presentedMessageLookup["message:incoming"]?.id, incoming.id)
    XCTAssertEqual(projection.presentedMessageIndexLookup["message:incoming"], 1)
    XCTAssertEqual(projection.imageAttachments.map(\.id), ["image-0"])
    XCTAssertEqual(
      projection.exyteMessages.map(\.id),
      ["client:outgoing", "message:incoming", "typing-indicator"])
    XCTAssertTrue(projection.typingIndicatorJoinsPrevious)
    XCTAssertTrue(
      projection.rowProjectionsByPresentedMessageID["message:incoming"]?
        .groupContext.joinsNext ?? false
    )
    XCTAssertEqual(
      projection.rowProjectionsByPresentedMessageID["client:outgoing"]?.messageStatus,
      .read
    )
  }

  func testImageGalleryResolverPreservesRequestedSelectionWhenPresent() {
    let attachments = [
      makeImageAttachment(id: "image-0", attachmentIndex: 0),
      makeImageAttachment(id: "image-1", attachmentIndex: 1),
    ]

    XCTAssertEqual(
      FriendsThreadImageGalleryResolver.initialSelectionID(
        requestedAttachmentID: "image-1",
        attachments: attachments
      ),
      "image-1"
    )
  }

  func testImageGalleryResolverFallsBackToFirstAttachmentWhenRequestedSelectionIsMissing() {
    let attachments = [
      makeImageAttachment(id: "image-0", attachmentIndex: 0),
      makeImageAttachment(id: "image-1", attachmentIndex: 1),
    ]

    XCTAssertEqual(
      FriendsThreadImageGalleryResolver.initialSelectionID(
        requestedAttachmentID: "missing",
        attachments: attachments
      ),
      "image-0"
    )
  }

  private func makeMessage(
    id: String,
    senderUserId: String,
    createdAt: Date,
    messageType: FriendMessageType = .user,
    body: String? = "Hello",
    deletedAt: Date? = nil,
    metadataData: Data? = nil,
    reactions: [FriendMessageReaction] = []
  ) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: "thread-1",
      senderUserId: senderUserId,
      messageType: messageType,
      body: body,
      clientId: id,
      replyToMessageId: nil,
      createdAt: createdAt,
      editedAt: nil,
      deletedAt: deletedAt,
      metadataData: metadataData,
      attachments: [],
      reactions: reactions,
      sendState: .sent,
      failureMessage: nil
    )
  }

  private func makeImageAttachment(id: String, attachmentIndex: Int) -> FriendMessageAttachment {
    FriendMessageAttachment(
      id: id,
      attachmentIndex: attachmentIndex,
      kind: .image,
      storageBucket: "message-attachments",
      storagePath: "thread-1/\(id).jpeg",
      mimeType: "image/jpeg",
      byteSize: 1_024,
      width: 1_200,
      height: 900,
      createdAt: Date(timeIntervalSince1970: 1_731_000_000)
    )
  }

  private func makeShiftSnapshot(ownerUserId: String, shiftDate: String) -> FriendShiftSnapshot {
    FriendShiftSnapshot(
      schemaVersion: 1,
      ownerUserId: ownerUserId,
      ownerDisplayName: "Owner",
      ownerAvatarUrl: nil,
      shiftId: "shift-1",
      jobName: "Cafe",
      jobColorHex: nil,
      shiftDate: shiftDate,
      startTime: "08:00",
      endTime: "16:00",
      paidHours: 8,
      currency: "NOK",
      includesEarnings: false,
      grossPay: nil,
      netPay: nil,
      taxEnabled: false,
      source: "tests"
    )
  }

  private func makeShiftSnapshotMetadataData() -> Data? {
    FriendsComposerAttachmentDraft
      .shiftSnapshot(
        ComposerShiftSnapshotDraft(
          snapshot: makeShiftSnapshot(ownerUserId: "owner-1", shiftDate: "2026-04-04")
        )
      )
      .metadataData
  }
}
