import ExyteChat
import XCTest

@testable import Tidex

final class FriendsThreadExyteChatTests: XCTestCase {
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

  func testLiveEdgeResolverTreatsFocusedComposerAsPinnedToLatest() {
    XCTAssertTrue(
      FriendsThreadLiveEdgeResolver.shouldStickToLatest(
        isPinnedToBottom: false,
        isComposerFocused: true
      )
    )
  }

  func testLiveEdgeResolverFallsBackToViewportPinWhenComposerIsNotFocused() {
    XCTAssertFalse(
      FriendsThreadLiveEdgeResolver.shouldStickToLatest(
        isPinnedToBottom: false,
        isComposerFocused: false
      )
    )
    XCTAssertTrue(
      FriendsThreadLiveEdgeResolver.shouldStickToLatest(
        isPinnedToBottom: true,
        isComposerFocused: false
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
          gross: 1200
        ),
        tax_enabled: false,
        tax_percentage: 0,
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

  private func makeMessage(
    id: String,
    senderUserId: String,
    createdAt: Date,
    reactions: [FriendMessageReaction] = []
  ) -> FriendMessage {
    FriendMessage(
      id: id,
      threadId: "thread-1",
      senderUserId: senderUserId,
      messageType: .user,
      body: "Hello",
      clientId: id,
      replyToMessageId: nil,
      createdAt: createdAt,
      editedAt: nil,
      deletedAt: nil,
      attachments: [],
      reactions: reactions,
      sendState: .sent,
      failureMessage: nil
    )
  }
}
