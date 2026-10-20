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

  func testCounterpartOnlyReactionChangeProducesUnequalExyteMessage() {
    let context = FriendsThreadExyteMessageFactory.Context(
      messagesById: [:],
      viewerUserId: "viewer",
      currentUserDisplayName: "Viewer Person",
      counterpartDisplayName: "Other Person",
      counterpartAvatarUrl: nil,
      latestOutgoingMessageId: nil,
      readReceiptMessageId: nil
    )
    let createdAt = Date(timeIntervalSince1970: 1_775_433_600)
    let plain = FriendsThreadExyteMessageFactory.makeMessage(
      makeMessage(id: "message-1", senderUserId: "viewer", createdAt: createdAt),
      context: context
    )
    let reacted = FriendsThreadExyteMessageFactory.makeMessage(
      makeMessage(
        id: "message-1",
        senderUserId: "viewer",
        createdAt: createdAt,
        reactions: [FriendMessageReaction(emoji: "🔥", count: 1, viewerHasReacted: false)]
      ),
      context: context
    )
    let unchanged = FriendsThreadExyteMessageFactory.makeMessage(
      makeMessage(id: "message-1", senderUserId: "viewer", createdAt: createdAt),
      context: context
    )

    XCTAssertNotEqual(plain, reacted)
    XCTAssertEqual(plain, unchanged)
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
    // The typing indicator only joins a recent message, so the fixture uses current times.
    let baseDate = Date().addingTimeInterval(-120)
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
}
