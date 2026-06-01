import ExyteChat
import Foundation
import SwiftUI
import UIKit

enum FriendsThreadMessageMenuAction: MessageMenuAction, Sendable {
  static let shiftSnapshotForwardMarker = "__tidex_shift_snapshot__"

  case reply
  case copy
  case edit
  case forward
  case delete
  case report

  func title() -> String {
    switch self {
    case .reply:
      return String(localized: .friendsChatActionReply)
    case .copy:
      return String(localized: .commonCopy)
    case .edit:
      return String(localized: .friendsChatActionEdit)
    case .forward:
      return String(localized: .friendsChatActionForward)
    case .delete:
      return String(localized: .friendsChatActionDelete)
    case .report:
      return String(localized: .friendsChatReportMessage)
    }
  }

  func icon() -> Image {
    switch self {
    case .reply:
      return Image(systemName: "arrowshape.turn.up.left")
    case .copy:
      return Image(systemName: "doc.on.doc")
    case .edit:
      return Image(systemName: "pencil")
    case .forward:
      return Image(systemName: "arrowshape.turn.up.right")
    case .delete:
      return Image(systemName: "trash")
    case .report:
      return Image(systemName: "flag")
    }
  }

  static func menuItems(for message: ExyteChat.Message) -> [Self] {
    let hasText = !FriendsThreadExyteHighlightRedrawResolver.visibleText(for: message)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty
    let canForwardShiftSnapshot = message.giphyMediaId == shiftSnapshotForwardMarker

    if message.user.isCurrentUser {
      var items: [Self] = [.reply]
      if hasText {
        items.append(.copy)
        items.append(.edit)
      }
      if canForwardShiftSnapshot {
        items.append(.forward)
      }
      items.append(.delete)
      return items
    }

    var items: [Self] = [.reply]
    if hasText {
      items.append(.copy)
    }
    if canForwardShiftSnapshot {
      items.append(.forward)
    }
    items.append(.report)
    return items
  }
}

enum FriendsThreadMessageStatusResolver {
  static func readReceiptMessageId(
    messages: [FriendMessage],
    viewerUserId: String,
    counterpartLastReadMessageId: String?,
    counterpartLastReadAt: Date?
  ) -> String? {
    guard let counterpartLastReadAt else { return nil }
    guard let normalizedViewerUserId = normalizedUserId(viewerUserId) else { return nil }

    return messages.last(where: {
      isReadReceiptCandidate($0, viewerUserId: normalizedViewerUserId)
        && isMessage(
          $0,
          readThroughAt: counterpartLastReadAt,
          readThroughMessageId: counterpartLastReadMessageId
        )
    })?.id
  }

  static func latestOutgoingMessageId(messages: [FriendMessage], viewerUserId: String) -> String? {
    guard let normalizedViewerUserId = normalizedUserId(viewerUserId) else { return nil }

    return messages.last(where: {
      isReadReceiptCandidate($0, viewerUserId: normalizedViewerUserId)
    })?.id
  }

  static func status(
    for message: FriendMessage,
    viewerUserId: String,
    latestOutgoingMessageId: String?,
    readReceiptMessageId: String?
  ) -> FriendsChatMessageStatus? {
    guard message.senderUserId == viewerUserId, message.messageType == .user else { return nil }

    switch message.sendState {
    case .sending:
      return .sending
    case .failed:
      return .failed
    case .sent:
      if readReceiptMessageId == message.id {
        return .read
      }
      if latestOutgoingMessageId == message.id {
        return .delivered
      }
      return nil
    }
  }

  static func shouldShowTimestamp(
    for message: FriendMessage,
    isCurrentUser: Bool,
    groupContext: FriendsChatMessageGroupContext,
    messageStatus: FriendsChatMessageStatus?
  ) -> Bool {
    guard isCurrentUser else { return !groupContext.joinsNext }

    switch messageStatus {
    case .sending, .failed:
      return false
    case .delivered, .read:
      return true
    case .none:
      return message.sendState == .sent
    }
  }

  private static func isReadReceiptCandidate(
    _ message: FriendMessage,
    viewerUserId: String
  ) -> Bool {
    normalizedUserId(message.senderUserId) == viewerUserId
      && message.messageType == .user
      && message.deletedAt == nil
  }

  private static func isMessage(
    _ message: FriendMessage,
    readThroughAt: Date,
    readThroughMessageId: String?
  ) -> Bool {
    guard let readThroughMessageId else {
      return message.createdAt <= readThroughAt
    }

    return (message.createdAt, message.id) <= (readThroughAt, readThroughMessageId)
  }

  private static func normalizedUserId(_ userId: String) -> String? {
    let normalized = userId.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}

enum FriendsChatReplySwipeDirection: Equatable {
  case left
  case right
}

enum FriendsChatReplySwipeOutcome: Equatable {
  case reset
  case trigger
}

enum FriendsChatPanGestureResolver {
  static let horizontalIntentRatio: CGFloat = 1.45
  static let navigationBackDistanceThreshold: CGFloat = 72
  static let navigationBackVelocityThreshold: CGFloat = 450

  static func hasPassedMinimumDistance(translation: CGSize, minimumDistance: CGFloat) -> Bool {
    hypot(translation.width, translation.height) >= minimumDistance
  }

  static func hasHorizontalIntent(translation: CGSize) -> Bool {
    abs(translation.width) > abs(translation.height)
  }

  static func hasHorizontalIntent(velocity: CGSize, ratio: CGFloat = horizontalIntentRatio) -> Bool
  {
    abs(velocity.width) > abs(velocity.height) * ratio
  }

  static func hasDirectionalHorizontalIntent(
    velocity: CGSize,
    direction: FriendsChatReplySwipeDirection,
    ratio: CGFloat = horizontalIntentRatio
  ) -> Bool {
    guard hasHorizontalIntent(velocity: velocity, ratio: ratio) else { return false }

    switch direction {
    case .left:
      return velocity.width < 0
    case .right:
      return velocity.width > 0
    }
  }

  static func shouldTriggerNavigationBack(translation: CGSize, velocity: CGSize) -> Bool {
    guard translation.width > 0 else { return false }
    guard abs(translation.width) > abs(translation.height) else { return false }
    return translation.width >= navigationBackDistanceThreshold
      || velocity.width >= navigationBackVelocityThreshold
  }
}

enum FriendsChatReplySwipeResolver {
  static let minimumDistance: CGFloat = 20
  static let actionThreshold: CGFloat = 0.4
  static let actionWidth: CGFloat = 80
  static let velocityThreshold: CGFloat = 300

  static func clampedOffset(
    horizontal: CGFloat,
    vertical: CGFloat,
    allowedDirection: FriendsChatReplySwipeDirection
  ) -> CGFloat? {
    guard abs(horizontal) > abs(vertical) else { return nil }

    switch allowedDirection {
    case .left:
      guard horizontal < 0 else { return 0 }
    case .right:
      guard horizontal > 0 else { return 0 }
    }

    if abs(horizontal) > actionWidth {
      let excess = abs(horizontal) - actionWidth
      let sign: CGFloat = horizontal > 0 ? 1 : -1
      return sign * (actionWidth + excess * 0.3)
    }

    return horizontal
  }

  static func crossedThreshold(offset: CGFloat) -> Bool {
    abs(offset) >= actionWidth * actionThreshold
  }

  static func outcome(
    offset: CGFloat,
    velocity: CGFloat,
    allowedDirection: FriendsChatReplySwipeDirection
  ) -> FriendsChatReplySwipeOutcome {
    switch allowedDirection {
    case .left:
      return offset < 0 && (crossedThreshold(offset: offset) || velocity < -velocityThreshold)
        ? .trigger
        : .reset
    case .right:
      return offset > 0 && (crossedThreshold(offset: offset) || velocity > velocityThreshold)
        ? .trigger
        : .reset
    }
  }
}

enum FriendsChatTimestampRevealResolver {
  enum Surface: Equatable {
    case leadingSpacer
    case trailingSpacer
  }

  static let revealWidth: CGFloat = 64
  static let minimumDistance: CGFloat = 16

  static func activeSurface(isCurrentUser: Bool) -> Surface {
    isCurrentUser ? .leadingSpacer : .trailingSpacer
  }

  static func contentMaxWidth(baseWidth: CGFloat, isCurrentUser: Bool) -> CGFloat {
    isCurrentUser ? baseWidth : max(0, baseWidth - revealWidth)
  }

  static func clampedRevealOffset(horizontal: CGFloat, vertical: CGFloat) -> CGFloat? {
    guard abs(horizontal) > abs(vertical) else { return nil }
    guard horizontal < 0 else { return 0 }
    return min(abs(horizontal), revealWidth)
  }
}

enum FriendsThreadMessageListChangeResolver {
  enum Change: Equatable {
    case none
    case prependedHistory
    case appendedIncoming
    case appendedOutgoing
  }

  static func resolve(
    oldMessageIDs: [String],
    newMessageIDs: [String],
    lastMessageSenderId: String?,
    viewerUserId: String
  ) -> Change {
    guard !newMessageIDs.isEmpty, newMessageIDs != oldMessageIDs else { return .none }

    let prependedMessage = isPrependedMessage(
      oldMessageIDs: oldMessageIDs, newMessageIDs: newMessageIDs)
    let appendedMessage = isAppendedMessage(
      oldMessageIDs: oldMessageIDs, newMessageIDs: newMessageIDs)

    guard appendedMessage, !prependedMessage else {
      return prependedMessage ? .prependedHistory : .none
    }

    return lastMessageSenderId == viewerUserId ? .appendedOutgoing : .appendedIncoming
  }

  static func isPrependedMessage(oldMessageIDs: [String], newMessageIDs: [String]) -> Bool {
    newMessageIDs.count > oldMessageIDs.count
      && newMessageIDs.first != oldMessageIDs.first
      && newMessageIDs.last == oldMessageIDs.last
  }

  static func isAppendedMessage(oldMessageIDs: [String], newMessageIDs: [String]) -> Bool {
    newMessageIDs.last != oldMessageIDs.last || oldMessageIDs.isEmpty
  }
}

struct FriendsThreadIncomingAppendOutcome: Equatable {
  let unreadIncomingCount: Int
  let showsNewMessagesPill: Bool
  let shouldPlayFeedback: Bool
}

enum FriendsThreadIncomingAppendResolver {
  static func resolve(
    previousMessageCount: Int,
    unreadIncomingCount: Int,
    isIncoming: Bool,
    isPinnedToBottom: Bool
  ) -> FriendsThreadIncomingAppendOutcome {
    guard previousMessageCount > 0 else {
      return FriendsThreadIncomingAppendOutcome(
        unreadIncomingCount: 0,
        showsNewMessagesPill: false,
        shouldPlayFeedback: false
      )
    }

    guard !isPinnedToBottom else {
      return FriendsThreadIncomingAppendOutcome(
        unreadIncomingCount: 0,
        showsNewMessagesPill: false,
        shouldPlayFeedback: false
      )
    }

    guard isIncoming else {
      return FriendsThreadIncomingAppendOutcome(
        unreadIncomingCount: unreadIncomingCount,
        showsNewMessagesPill: unreadIncomingCount > 0,
        shouldPlayFeedback: false
      )
    }

    return FriendsThreadIncomingAppendOutcome(
      unreadIncomingCount: unreadIncomingCount + 1,
      showsNewMessagesPill: true,
      shouldPlayFeedback: true
    )
  }
}

enum FriendsThreadOutgoingAppendScrollResolver {
  static func scrollTarget(
    change: FriendsThreadMessageListChangeResolver.Change,
    shouldScrollToNextOutgoingMessage: Bool,
    newMessageIDs: [String]
  ) -> String? {
    guard shouldScrollToNextOutgoingMessage, change == .appendedOutgoing else {
      return nil
    }

    return newMessageIDs.last
  }
}

enum FriendsThreadLiveEdgeResolver {
  static func shouldStickToLatest(
    isPinnedToBottom: Bool
  ) -> Bool {
    isPinnedToBottom
  }
}

enum FriendsThreadImageGalleryResolver {
  static func imageAttachments(messages: [FriendMessage]) -> [FriendMessageAttachment] {
    messages.flatMap { message in
      message.attachments
        .filter { $0.kind == .image }
        .sorted { lhs, rhs in
          lhs.attachmentIndex < rhs.attachmentIndex
        }
    }
  }

  static func initialSelectionID(
    requestedAttachmentID: String,
    attachments: [FriendMessageAttachment]
  ) -> String? {
    if attachments.contains(where: { $0.id == requestedAttachmentID }) {
      return requestedAttachmentID
    }

    return attachments.first?.id
  }
}

enum FriendsThreadCounterpartPreviewNavigationResolver {
  static func deepLink(for preview: SharerShiftPreview) -> AppCoordinator.DeepLink? {
    guard let shift = preview.shift else { return nil }

    return .sharing(
      sharerId: preview.sharerId,
      highlightDates: [shift.shift_date],
      changes: [
        AppCoordinator.ShiftChange(
          shiftId: shift.id,
          date: shift.shift_date,
          op: "updated"
        )
      ]
    )
  }
}

enum FriendsThreadAttachmentTapGuard {
  static let messageMenuRecognitionDuration: TimeInterval = 0.35
  private static let tapSuppressionDuration: TimeInterval = 0.75

  static func suppressedUntilAfterMenuRecognition(now: Date = .now) -> Date {
    now.addingTimeInterval(tapSuppressionDuration)
  }

  static func shouldHandleTap(suppressedUntil: Date?, now: Date = .now) -> Bool {
    guard let suppressedUntil else { return true }
    return now >= suppressedUntil
  }
}

enum FriendsThreadShiftSnapshotNavigationResolver {
  static func deepLink(
    for snapshot: FriendShiftSnapshot,
    viewerUserId: String,
    cachedFriends: SharedShiftsRepository.CachedFriendsSnapshot
  ) -> AppCoordinator.DeepLink? {
    let shiftDate = snapshot.shiftDate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !shiftDate.isEmpty else { return nil }

    if snapshot.ownerUserId == viewerUserId {
      return .shifts(dates: [shiftDate], shiftIds: nil, action: .highlight)
    }

    guard canViewSharedShifts(ownerUserId: snapshot.ownerUserId, cachedFriends: cachedFriends)
    else { return nil }

    return .sharing(
      sharerId: snapshot.ownerUserId,
      highlightDates: [shiftDate],
      changes: nil
    )
  }

  private static func canViewSharedShifts(
    ownerUserId: String,
    cachedFriends: SharedShiftsRepository.CachedFriendsSnapshot
  ) -> Bool {
    guard let sharer = cachedFriends.sharers.first(where: { $0.id == ownerUserId }) else {
      return false
    }

    let isVisible = !cachedFriends.chatOnlyUserIds.contains(ownerUserId)
    _ = sharer
    return isVisible
  }
}

struct FriendsThreadChatViewportScrollRequest: Equatable {
  enum Kind: Equatable {
    case reply
    case restore
    case liveEdge
  }

  let kind: Kind
  let messageID: String
  let presentedMessageID: String
}

enum FriendsThreadChatViewportScrollDeferralResolver {
  static func shouldDefer(
    kind: FriendsThreadChatViewportScrollRequest.Kind,
    hasDeferredInitialReplyScroll: Bool,
    isUserInteracting: Bool
  ) -> Bool {
    switch kind {
    case .reply:
      isUserInteracting || !hasDeferredInitialReplyScroll
    case .restore:
      isUserInteracting
    case .liveEdge:
      false
    }
  }
}

enum FriendsThreadChatViewportResolver {
  private static let pinnedToBottomThreshold: CGFloat = 1

  struct LayoutSnapshot {
    private let messageIDsSignature: [String]
    private let presentedMessageIDsByIndexPath: [IndexPath: String]
    private let indexPathsByPresentedMessageID: [String: IndexPath]
    private let orderByPresentedMessageID: [String: Int]

    init(messages: [ExyteChat.Message]) {
      messageIDsSignature = messages.map(\.id)

      let calendar = Calendar.current
      var messagesByDay: [Date: [ExyteChat.Message]] = [:]
      var orderByPresentedMessageID: [String: Int] = [:]

      for (order, message) in messages.enumerated() {
        let day = calendar.startOfDay(for: message.createdAt)
        messagesByDay[day, default: []].append(message)
        orderByPresentedMessageID[message.id] = order
      }

      var presentedMessageIDsByIndexPath: [IndexPath: String] = [:]
      var indexPathsByPresentedMessageID: [String: IndexPath] = [:]
      let sectionDates = messagesByDay.keys.sorted(by: >)

      for (sectionIndex, sectionDate) in sectionDates.enumerated() {
        let sectionMessages = Array(messagesByDay[sectionDate, default: []].reversed())
        for (rowIndex, message) in sectionMessages.enumerated() {
          let indexPath = IndexPath(row: rowIndex, section: sectionIndex)
          presentedMessageIDsByIndexPath[indexPath] = message.id
          indexPathsByPresentedMessageID[message.id] = indexPath
        }
      }

      self.presentedMessageIDsByIndexPath = presentedMessageIDsByIndexPath
      self.indexPathsByPresentedMessageID = indexPathsByPresentedMessageID
      self.orderByPresentedMessageID = orderByPresentedMessageID
    }

    func matches(messages: [ExyteChat.Message]) -> Bool {
      messageIDsSignature == messages.map(\.id)
    }

    func indexPath(for presentedMessageID: String) -> IndexPath? {
      indexPathsByPresentedMessageID[presentedMessageID]
    }

    func presentedMessageID(for indexPath: IndexPath) -> String? {
      presentedMessageIDsByIndexPath[indexPath]
    }

    func latestVisiblePresentedMessageID(in tableView: UITableView) -> String? {
      let visibleIndexPaths = (tableView.indexPathsForVisibleRows ?? []).filter { indexPath in
        tableView.numberOfSections > indexPath.section
          && tableView.numberOfRows(inSection: indexPath.section) > indexPath.row
      }

      var latestVisiblePresentedMessageID: String?
      var latestVisibleOrder = Int.min

      for indexPath in visibleIndexPaths {
        guard
          let presentedMessageID = presentedMessageID(for: indexPath),
          let order = orderByPresentedMessageID[presentedMessageID]
        else {
          continue
        }

        if order >= latestVisibleOrder {
          latestVisibleOrder = order
          latestVisiblePresentedMessageID = presentedMessageID
        }
      }

      return latestVisiblePresentedMessageID
    }
  }

  static func isPinnedToBottom(contentOffsetY: CGFloat) -> Bool {
    contentOffsetY <= pinnedToBottomThreshold
  }

  static func layoutSnapshot(messages: [ExyteChat.Message]) -> LayoutSnapshot {
    LayoutSnapshot(messages: messages)
  }

  static func indexPath(for presentedMessageID: String, in messages: [ExyteChat.Message])
    -> IndexPath?
  {
    layoutSnapshot(messages: messages).indexPath(for: presentedMessageID)
  }

  static func indexPath(for presentedMessageID: String, in layoutSnapshot: LayoutSnapshot)
    -> IndexPath?
  {
    layoutSnapshot.indexPath(for: presentedMessageID)
  }

  static func latestVisiblePresentedMessageID(
    in tableView: UITableView,
    messages: [ExyteChat.Message]
  ) -> String? {
    layoutSnapshot(messages: messages).latestVisiblePresentedMessageID(in: tableView)
  }

  static func latestVisiblePresentedMessageID(
    in tableView: UITableView,
    layoutSnapshot: LayoutSnapshot
  ) -> String? {
    layoutSnapshot.latestVisiblePresentedMessageID(in: tableView)
  }

  private static func presentedMessageID(for indexPath: IndexPath, in messages: [ExyteChat.Message])
    -> String?
  {
    layoutSnapshot(messages: messages).presentedMessageID(for: indexPath)
  }
}

enum FriendsThreadChatViewportRequestResolver {
  static func presentedMessageID(
    for messageId: String?,
    messages: [FriendMessage],
    viewerUserId: String
  ) -> String? {
    guard let messageId else { return nil }
    guard let message = messages.first(where: { $0.id == messageId }) else { return nil }
    return FriendsThreadMessagePresentationID.make(for: message, viewerUserId: viewerUserId)
  }

  static func request(
    replyTargetMessageId: String?,
    restoreTargetMessageId: String?,
    liveEdgeTargetPresentedMessageID: String?,
    messages: [FriendMessage],
    viewerUserId: String
  ) -> FriendsThreadChatViewportScrollRequest? {
    if let replyRequest = makeRequest(
      kind: .reply,
      messageId: replyTargetMessageId,
      messages: messages,
      viewerUserId: viewerUserId
    ) {
      return replyRequest
    }

    if let restoreRequest = makeRequest(
      kind: .restore,
      messageId: restoreTargetMessageId,
      messages: messages,
      viewerUserId: viewerUserId
    ) {
      return restoreRequest
    }

    return makePresentedMessageIDRequest(
      kind: .liveEdge,
      presentedMessageID: liveEdgeTargetPresentedMessageID
    )
  }

  private static func makeRequest(
    kind: FriendsThreadChatViewportScrollRequest.Kind,
    messageId: String?,
    messages: [FriendMessage],
    viewerUserId: String
  ) -> FriendsThreadChatViewportScrollRequest? {
    guard let messageId else { return nil }
    guard let message = messages.first(where: { $0.id == messageId }) else { return nil }

    return FriendsThreadChatViewportScrollRequest(
      kind: kind,
      messageID: messageId,
      presentedMessageID: FriendsThreadMessagePresentationID.make(
        for: message,
        viewerUserId: viewerUserId
      )
    )
  }

  private static func makePresentedMessageIDRequest(
    kind: FriendsThreadChatViewportScrollRequest.Kind,
    presentedMessageID: String?
  ) -> FriendsThreadChatViewportScrollRequest? {
    guard let presentedMessageID else { return nil }

    return FriendsThreadChatViewportScrollRequest(
      kind: kind,
      messageID: presentedMessageID,
      presentedMessageID: presentedMessageID
    )
  }
}

enum FriendsThreadVisibleMessageResolver {
  static func messageID(
    for presentedMessageID: String?,
    messages: [FriendMessage],
    viewerUserId: String
  ) -> String? {
    guard let presentedMessageID else { return nil }
    guard presentedMessageID != FriendsThreadExyteMessageFactory.typingIndicatorMessageID else {
      return nil
    }

    if let message = messages.first(where: {
      FriendsThreadMessagePresentationID.make(for: $0, viewerUserId: viewerUserId)
        == presentedMessageID
    }) {
      return message.id
    }

    return presentedMessageID.replacingOccurrences(of: "message:", with: "")
  }
}

struct FriendsThreadMessageRowProjection {
  let message: FriendMessage
  let index: Int
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let messageStatus: FriendsChatMessageStatus?
  let shouldShowTimestamp: Bool
}

struct FriendsThreadChatProjection {
  struct Input: Equatable {
    let messages: [FriendMessage]
    let viewerUserId: String
    let currentUserDisplayName: String
    let counterpartDisplayName: String
    let counterpartAvatarUrl: String?
    let quotedMessagesById: [String: FriendMessage]
    let counterpartLastReadMessageId: String?
    let counterpartLastReadAt: Date?
    let showsTypingIndicator: Bool
    let typingIndicatorCreatedAt: Date
    let reactionAttachmentTargets: [String: String]

    init(
      messages: [FriendMessage],
      viewerUserId: String,
      currentUserDisplayName: String,
      counterpartDisplayName: String,
      counterpartAvatarUrl: String?,
      quotedMessagesById: [String: FriendMessage],
      counterpartLastReadMessageId: String?,
      counterpartLastReadAt: Date?,
      showsTypingIndicator: Bool,
      typingIndicatorCreatedAt: Date,
      reactionAttachmentTargets: [String: String] = [:]
    ) {
      self.messages = messages
      self.viewerUserId = viewerUserId
      self.currentUserDisplayName = currentUserDisplayName
      self.counterpartDisplayName = counterpartDisplayName
      self.counterpartAvatarUrl = counterpartAvatarUrl
      self.quotedMessagesById = quotedMessagesById
      self.counterpartLastReadMessageId = counterpartLastReadMessageId
      self.counterpartLastReadAt = counterpartLastReadAt
      self.showsTypingIndicator = showsTypingIndicator
      self.typingIndicatorCreatedAt = typingIndicatorCreatedAt
      self.reactionAttachmentTargets = reactionAttachmentTargets
    }
  }

  static let empty = FriendsThreadChatProjection(
    messages: [],
    exyteMessages: [],
    presentedMessageLookup: [:],
    presentedMessageIDs: [],
    presentedMessageIndexLookup: [:],
    imageAttachments: [],
    rowProjectionsByPresentedMessageID: [:],
    typingIndicatorJoinsPrevious: false
  )

  let messages: [FriendMessage]
  let exyteMessages: [ExyteChat.Message]
  let presentedMessageLookup: [String: FriendMessage]
  let presentedMessageIDs: [String]
  let presentedMessageIndexLookup: [String: Int]
  let imageAttachments: [FriendMessageAttachment]
  let rowProjectionsByPresentedMessageID: [String: FriendsThreadMessageRowProjection]
  let typingIndicatorJoinsPrevious: Bool

  static func make(input: Input) -> FriendsThreadChatProjection {
    guard !input.messages.isEmpty || input.showsTypingIndicator else {
      return empty
    }

    let latestOutgoingMessageId = FriendsThreadMessageStatusResolver.latestOutgoingMessageId(
      messages: input.messages,
      viewerUserId: input.viewerUserId
    )
    let readReceiptMessageId = FriendsThreadMessageStatusResolver.readReceiptMessageId(
      messages: input.messages,
      viewerUserId: input.viewerUserId,
      counterpartLastReadMessageId: input.counterpartLastReadMessageId,
      counterpartLastReadAt: input.counterpartLastReadAt
    )
    let exyteMessages = FriendsThreadExyteMessageFactory.makeMessages(
      messages: input.messages,
      conversation: .init(
        viewerUserId: input.viewerUserId,
        currentUserDisplayName: input.currentUserDisplayName,
        counterpartDisplayName: input.counterpartDisplayName,
        counterpartAvatarUrl: input.counterpartAvatarUrl,
        quotedMessagesById: input.quotedMessagesById,
        counterpartLastReadMessageId: input.counterpartLastReadMessageId,
        counterpartLastReadAt: input.counterpartLastReadAt,
        showsTypingIndicator: input.showsTypingIndicator,
        typingIndicatorCreatedAt: input.typingIndicatorCreatedAt,
        reactionAttachmentTargets: input.reactionAttachmentTargets
      )
    )

    var presentedMessageLookup: [String: FriendMessage] = [:]
    var presentedMessageIDs: [String] = []
    var presentedMessageIndexLookup: [String: Int] = [:]
    var rowProjectionsByPresentedMessageID: [String: FriendsThreadMessageRowProjection] = [:]
    presentedMessageLookup.reserveCapacity(input.messages.count)
    presentedMessageIDs.reserveCapacity(input.messages.count)
    presentedMessageIndexLookup.reserveCapacity(input.messages.count)
    rowProjectionsByPresentedMessageID.reserveCapacity(input.messages.count)

    let lastMessageIndex = input.messages.indices.last
    for index in input.messages.indices {
      let message = input.messages[index]
      let presentedMessageID = FriendsThreadMessagePresentationID.make(
        for: message,
        viewerUserId: input.viewerUserId
      )
      let previousMessage = index > input.messages.startIndex ? input.messages[index - 1] : nil
      let nextMessage =
        index < input.messages.index(before: input.messages.endIndex)
        ? input.messages[index + 1]
        : nil
      let baseGroupContext = FriendsChatMessageGrouping.context(
        for: message,
        previous: previousMessage,
        next: nextMessage,
        viewerUserId: input.viewerUserId
      )
      let groupContext =
        shouldJoinTypingIndicator(
          message: message,
          index: index,
          lastMessageIndex: lastMessageIndex,
          viewerUserId: input.viewerUserId,
          showsTypingIndicator: input.showsTypingIndicator
        )
        ? baseGroupContext.joiningNext()
        : baseGroupContext
      let isCurrentUser = message.senderUserId == input.viewerUserId
      let messageStatus = FriendsThreadMessageStatusResolver.status(
        for: message,
        viewerUserId: input.viewerUserId,
        latestOutgoingMessageId: latestOutgoingMessageId,
        readReceiptMessageId: readReceiptMessageId
      )

      presentedMessageIDs.append(presentedMessageID)
      presentedMessageLookup[presentedMessageID] = message
      presentedMessageIndexLookup[presentedMessageID] = index
      rowProjectionsByPresentedMessageID[presentedMessageID] = FriendsThreadMessageRowProjection(
        message: message,
        index: index,
        isCurrentUser: isCurrentUser,
        groupContext: groupContext,
        messageStatus: messageStatus,
        shouldShowTimestamp: FriendsThreadMessageStatusResolver.shouldShowTimestamp(
          for: message,
          isCurrentUser: isCurrentUser,
          groupContext: groupContext,
          messageStatus: messageStatus
        )
      )
    }

    return FriendsThreadChatProjection(
      messages: input.messages,
      exyteMessages: exyteMessages,
      presentedMessageLookup: presentedMessageLookup,
      presentedMessageIDs: presentedMessageIDs,
      presentedMessageIndexLookup: presentedMessageIndexLookup,
      imageAttachments: FriendsThreadImageGalleryResolver.imageAttachments(
        messages: input.messages),
      rowProjectionsByPresentedMessageID: rowProjectionsByPresentedMessageID,
      typingIndicatorJoinsPrevious: input.messages.last.map {
        shouldJoinTypingIndicator(
          message: $0,
          index: lastMessageIndex,
          lastMessageIndex: lastMessageIndex,
          viewerUserId: input.viewerUserId,
          showsTypingIndicator: input.showsTypingIndicator
        )
      } ?? false
    )
  }

  private static func shouldJoinTypingIndicator(
    message: FriendMessage,
    index: Int?,
    lastMessageIndex: Int?,
    viewerUserId: String,
    showsTypingIndicator: Bool,
    now: Date = .now
  ) -> Bool {
    guard showsTypingIndicator else { return false }
    guard message.senderUserId != viewerUserId else { return false }
    guard message.messageType == .user, message.deletedAt == nil else { return false }
    guard index == lastMessageIndex else { return false }
    return now.timeIntervalSince(message.createdAt) <= FriendsChatMessageGrouping.maximumGap
  }
}

@MainActor
final class FriendsThreadChatProjectionStore: ObservableObject {
  private var cachedInput: FriendsThreadChatProjection.Input?
  private var cachedProjection: FriendsThreadChatProjection = .empty

  func projection(for input: FriendsThreadChatProjection.Input) -> FriendsThreadChatProjection {
    guard cachedInput != input else { return cachedProjection }
    cachedInput = input
    cachedProjection = FriendsThreadChatProjection.make(input: input)
    return cachedProjection
  }
}

enum FriendsThreadExyteHighlightRedrawResolver {
  private static let redrawMarker = "\u{2060}"

  static func applyingHighlightMarker(
    to messages: [ExyteChat.Message],
    highlightedPresentedMessageID: String?
  ) -> [ExyteChat.Message] {
    messages.map { message in
      guard message.id == highlightedPresentedMessageID else { return message }
      var highlightedMessage = message
      highlightedMessage.attributedText += AttributedString(redrawMarker)
      return highlightedMessage
    }
  }

  static func isHighlighted(_ message: ExyteChat.Message) -> Bool {
    String(message.attributedText.characters).hasSuffix(redrawMarker)
  }

  static func visibleText(for message: ExyteChat.Message) -> String {
    let text = String(message.attributedText.characters)
    guard isHighlighted(message) else { return text }
    return String(text.dropLast(redrawMarker.count))
  }
}

enum FriendsThreadHighlightRefreshResolver {
  static func shouldRefreshRows(
    force: Bool,
    highlightedPresentedMessageID: String?,
    lastHighlightedPresentedMessageID: String?
  ) -> Bool {
    force || highlightedPresentedMessageID != lastHighlightedPresentedMessageID
  }
}

struct FriendsThreadNavigationGestureBridge: UIViewRepresentable {
  let onNavigateBack: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onNavigateBack: onNavigateBack)
  }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.onNavigateBack = onNavigateBack
    DispatchQueue.main.async {
      context.coordinator.configure(from: uiView)
    }
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    coordinator.restore()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var onNavigateBack: () -> Void
    private weak var contentPopGestureRecognizer: UIGestureRecognizer?
    private weak var originalDelegate: UIGestureRecognizerDelegate?
    private weak var navigationView: UIView?
    private var backgroundBackPanGestureRecognizer: UIPanGestureRecognizer?

    init(onNavigateBack: @escaping () -> Void) {
      self.onNavigateBack = onNavigateBack
    }

    func configure(from view: UIView) {
      guard let navigationController = view.closestNavigationController() else { return }

      guard let recognizer = navigationController.interactiveContentPopGestureRecognizer else {
        installBackgroundBackRecognizerIfNeeded(on: navigationController.view)
        return
      }
      guard contentPopGestureRecognizer !== recognizer else { return }

      restore()
      originalDelegate = recognizer.delegate
      recognizer.delegate = self
      recognizer.isEnabled = true
      contentPopGestureRecognizer = recognizer
      installBackgroundBackRecognizerIfNeeded(on: navigationController.view)
    }

    func restore() {
      if let backgroundBackPanGestureRecognizer, let navigationView {
        navigationView.removeGestureRecognizer(backgroundBackPanGestureRecognizer)
      }
      backgroundBackPanGestureRecognizer = nil
      navigationView = nil

      guard let recognizer = contentPopGestureRecognizer else { return }
      if recognizer.delegate === self {
        recognizer.delegate = originalDelegate
      }
      contentPopGestureRecognizer = nil
      originalDelegate = nil
    }

    private func installBackgroundBackRecognizerIfNeeded(on view: UIView) {
      guard navigationView !== view else { return }

      if let backgroundBackPanGestureRecognizer, let navigationView {
        navigationView.removeGestureRecognizer(backgroundBackPanGestureRecognizer)
      }

      let recognizer =
        backgroundBackPanGestureRecognizer
        ?? UIPanGestureRecognizer(
          target: self,
          action: #selector(handleBackgroundBackPan(_:))
        )
      recognizer.cancelsTouchesInView = false
      recognizer.delaysTouchesBegan = false
      recognizer.delaysTouchesEnded = false
      recognizer.delegate = self
      view.addGestureRecognizer(recognizer)
      backgroundBackPanGestureRecognizer = recognizer
      navigationView = view
    }

    @objc private func handleBackgroundBackPan(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer.state == .ended else { return }

      let translation = recognizer.translation(in: recognizer.view)
      let velocity = recognizer.velocity(in: recognizer.view)
      guard
        FriendsChatPanGestureResolver.shouldTriggerNavigationBack(
          translation: CGSize(width: translation.x, height: translation.y),
          velocity: CGSize(width: velocity.x, height: velocity.y)
        )
      else {
        return
      }

      onNavigateBack()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer === backgroundBackPanGestureRecognizer {
        guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = recognizer.velocity(in: recognizer.view)
        guard
          FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
            velocity: CGSize(width: velocity.x, height: velocity.y),
            direction: .right
          )
        else {
          return false
        }

        return startsInChatTableBackground(gestureRecognizer)
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
      }

      if originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) == false {
        return false
      }

      if let recognizer = gestureRecognizer as? UIPanGestureRecognizer {
        let velocity = recognizer.velocity(in: recognizer.view)
        guard
          FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
            velocity: CGSize(width: velocity.x, height: velocity.y),
            direction: .right
          )
        else {
          return false
        }
      }

      return !startsInNavigationBackExcludedTarget(gestureRecognizer)
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if isBackNavigationRecognizer(gestureRecognizer, competingWith: otherGestureRecognizer) {
        return false
      }

      if gestureRecognizer === backgroundBackPanGestureRecognizer
        || otherGestureRecognizer === backgroundBackPanGestureRecognizer
      {
        return true
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizer?(
          gestureRecognizer,
          shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
        ) ?? true
      }

      return true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if isBackNavigationRecognizer(gestureRecognizer, competingWith: otherGestureRecognizer) {
        return true
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizer?(
          gestureRecognizer,
          shouldRequireFailureOf: otherGestureRecognizer
        ) ?? false
      }

      return false
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if isRightReplyGesture(gestureRecognizer),
        otherGestureRecognizer === contentPopGestureRecognizer
          || otherGestureRecognizer === backgroundBackPanGestureRecognizer
      {
        return false
      }

      guard gestureRecognizer === contentPopGestureRecognizer else {
        return originalDelegate?.gestureRecognizer?(
          gestureRecognizer,
          shouldBeRequiredToFailBy: otherGestureRecognizer
        ) ?? false
      }

      return false
    }

    private func isBackNavigationRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      competingWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      (gestureRecognizer === contentPopGestureRecognizer
        || gestureRecognizer === backgroundBackPanGestureRecognizer)
        && isRightReplyGesture(otherGestureRecognizer)
    }

    private func isRightReplyGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard
        let recognizer = gestureRecognizer as? FriendsChatDirectionalPanGestureRecognizer,
        case .replyPayload(direction: .right) = recognizer.targetKind
      else {
        return false
      }

      return recognizer.direction == .right
    }

    private func startsInChatTableBackground(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let rootView = gestureRecognizer.view else { return false }
      let location = gestureRecognizer.location(in: rootView)
      guard let tableView = rootView.containingTableView(at: location) else { return false }
      let tableLocation = gestureRecognizer.location(in: tableView)
      guard tableView.bounds.contains(tableLocation) else { return false }
      return !isNavigationBackExcludedTarget(rootView.chatGestureTargetKind(at: location))
    }

    private func startsInNavigationBackExcludedTarget(
      _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      guard let rootView = gestureRecognizer.view else { return false }
      let location = gestureRecognizer.location(in: rootView)
      return isNavigationBackExcludedTarget(rootView.chatGestureTargetKind(at: location))
    }

    private func isNavigationBackExcludedTarget(
      _ targetKind: FriendsChatGestureTargetKind?
    ) -> Bool {
      switch targetKind {
      case .replyPayload(direction: .right), .attachmentPhotoCarousel:
        return true
      case .replyPayload(direction: .left):
        return false
      case .timestampRevealGutter, .none:
        return false
      }
    }
  }
}

struct FriendsThreadTimestampRevealGestureBridge: UIViewRepresentable {
  let isEnabled: Bool
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onChanged: onChanged, onEnded: onEnded)
  }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.isEnabled = isEnabled
    context.coordinator.onChanged = onChanged
    context.coordinator.onEnded = onEnded

    DispatchQueue.main.async {
      context.coordinator.configure(from: uiView)
    }
  }

  static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
    coordinator.restore()
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var isEnabled = true
    var onChanged: (FriendsChatReplyDragValue) -> Void
    var onEnded: (FriendsChatReplyDragValue) -> Void
    private weak var tableView: UITableView?
    private var recognizer: UIPanGestureRecognizer?
    private var hasPassedMinimumDistance = false

    init(
      onChanged: @escaping (FriendsChatReplyDragValue) -> Void,
      onEnded: @escaping (FriendsChatReplyDragValue) -> Void
    ) {
      self.onChanged = onChanged
      self.onEnded = onEnded
    }

    func configure(from view: UIView) {
      guard isEnabled else {
        restore()
        return
      }
      guard let tableView = findChatTableView(from: view) else { return }
      guard tableView !== self.tableView else { return }

      restore()

      let recognizer = FriendsChatDirectionalPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
      )
      recognizer.targetKind = .timestampRevealGutter
      recognizer.direction = .left
      recognizer.cancelsTouchesInView = false
      recognizer.delaysTouchesBegan = false
      recognizer.delaysTouchesEnded = false
      recognizer.delegate = self
      tableView.addGestureRecognizer(recognizer)

      self.tableView = tableView
      self.recognizer = recognizer
    }

    func restore() {
      if let recognizer, let tableView {
        tableView.removeGestureRecognizer(recognizer)
      }
      recognizer = nil
      tableView = nil
      hasPassedMinimumDistance = false
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
      guard let tableView else { return }
      let value = dragValue(from: recognizer, in: tableView)

      switch recognizer.state {
      case .began:
        hasPassedMinimumDistance = false
        handleChangedIfReady(value)
      case .changed:
        handleChangedIfReady(value)
      case .ended:
        handleChangedIfReady(value)
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false
      case .cancelled, .failed:
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false
      case .possible:
        break
      @unknown default:
        if hasPassedMinimumDistance {
          onEnded(value)
        }
        hasPassedMinimumDistance = false
      }
    }

    private func handleChangedIfReady(_ value: FriendsChatReplyDragValue) {
      if !hasPassedMinimumDistance {
        guard
          FriendsChatPanGestureResolver.hasPassedMinimumDistance(
            translation: value.translation,
            minimumDistance: FriendsChatTimestampRevealResolver.minimumDistance
          )
        else {
          return
        }
        hasPassedMinimumDistance = true
      }

      onChanged(value)
    }

    private func dragValue(
      from recognizer: UIPanGestureRecognizer,
      in tableView: UITableView
    ) -> FriendsChatReplyDragValue {
      let coordinateView = tableView.window ?? tableView
      let translation = recognizer.translation(in: coordinateView)
      let velocity = recognizer.velocity(in: coordinateView)
      let location = recognizer.location(in: coordinateView)
      let startLocation = CGPoint(
        x: location.x - translation.x,
        y: location.y - translation.y
      )

      return FriendsChatReplyDragValue(
        location: location,
        startLocation: startLocation,
        translation: CGSize(width: translation.x, height: translation.y),
        velocity: CGSize(width: velocity.x, height: velocity.y)
      )
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard isEnabled else { return false }
      guard let recognizer = gestureRecognizer as? UIPanGestureRecognizer, let tableView else {
        return false
      }

      let location = recognizer.location(in: tableView)
      guard tableView.bounds.contains(location) else { return false }
      guard tableView.indexPathForRow(at: location) == nil else { return false }

      let velocity = recognizer.velocity(in: tableView.window ?? tableView)
      return FriendsChatPanGestureResolver.hasDirectionalHorizontalIntent(
        velocity: CGSize(width: velocity.x, height: velocity.y),
        direction: .left
      )
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    private func findChatTableView(from view: UIView) -> UITableView? {
      let searchRoot = view.window ?? view.nearestRootView()
      let tableViews = searchRoot.descendantViews(ofType: UITableView.self)

      return tableViews.first(where: { candidate in
        guard let delegate = candidate.delegate else { return false }
        return String(reflecting: type(of: delegate)).contains("UIList")
      }) ?? tableViews.first
    }
  }
}

extension UIView {
  fileprivate func closestNavigationController() -> UINavigationController? {
    sequence(first: self as UIResponder?, next: { $0?.next })
      .first { $0 is UINavigationController } as? UINavigationController
  }

  fileprivate func containsChatGestureTarget(at point: CGPoint) -> Bool {
    chatGestureTargetKind(at: point) != nil
  }

  fileprivate func chatGestureTargetKind(at point: CGPoint) -> FriendsChatGestureTargetKind? {
    for subview in subviews.reversed() {
      guard !subview.isHidden, subview.alpha > 0.01 else { continue }

      let convertedPoint = subview.convert(point, from: self)
      if let targetView = subview as? FriendsChatGestureTargetView,
        targetView.bounds.contains(convertedPoint)
      {
        return targetView.kind
      }

      if subview.bounds.contains(convertedPoint) || !subview.clipsToBounds {
        if let kind = subview.chatGestureTargetKind(at: convertedPoint) {
          return kind
        }
      }
    }

    return nil
  }

  fileprivate func containingTableView(at point: CGPoint) -> UITableView? {
    for subview in subviews.reversed() {
      guard !subview.isHidden, subview.alpha > 0.01 else { continue }

      let convertedPoint = subview.convert(point, from: self)
      if let tableView = subview as? UITableView, tableView.bounds.contains(convertedPoint) {
        return tableView
      }

      if subview.bounds.contains(convertedPoint) || !subview.clipsToBounds {
        if let tableView = subview.containingTableView(at: convertedPoint) {
          return tableView
        }
      }
    }

    return nil
  }
}

struct FriendsThreadChatViewportBridge: UIViewRepresentable {
  let messages: [ExyteChat.Message]
  let scrollRequest: FriendsThreadChatViewportScrollRequest?
  let observedPresentedMessageID: String?
  let highlightedPresentedMessageID: String?
  let onPinnedToBottomChanged: (Bool) -> Void
  let onLatestVisiblePresentedMessageIDChanged: (String?) -> Void
  let onObservedPresentedMessageVisible: (String) -> Void
  let onDidHandleScrollRequest: (FriendsThreadChatViewportScrollRequest) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeUIView(context: Context) -> UIView {
    let view = UIView(frame: .zero)
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.update(
      from: uiView,
      input: .init(
        messages: messages,
        scrollRequest: scrollRequest,
        observedPresentedMessageID: observedPresentedMessageID,
        highlightedPresentedMessageID: highlightedPresentedMessageID,
        onPinnedToBottomChanged: onPinnedToBottomChanged,
        onLatestVisiblePresentedMessageIDChanged: onLatestVisiblePresentedMessageIDChanged,
        onObservedPresentedMessageVisible: onObservedPresentedMessageVisible,
        onDidHandleScrollRequest: onDidHandleScrollRequest
      )
    )
  }

  @MainActor
  final class Coordinator {
    struct UpdateInput {
      let messages: [ExyteChat.Message]
      let scrollRequest: FriendsThreadChatViewportScrollRequest?
      let observedPresentedMessageID: String?
      let highlightedPresentedMessageID: String?
      let onPinnedToBottomChanged: (Bool) -> Void
      let onLatestVisiblePresentedMessageIDChanged: (String?) -> Void
      let onObservedPresentedMessageVisible: (String) -> Void
      let onDidHandleScrollRequest: (FriendsThreadChatViewportScrollRequest) -> Void
    }

    private weak var tableView: UITableView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var messages: [ExyteChat.Message] = []
    private var layoutSnapshot: FriendsThreadChatViewportResolver.LayoutSnapshot?
    private var scrollRequest: FriendsThreadChatViewportScrollRequest?
    private var observedPresentedMessageID: String?
    private var highlightedPresentedMessageID: String?
    private var lastHighlightedPresentedMessageID: String?
    private var handledScrollRequest: FriendsThreadChatViewportScrollRequest?
    private var lastPinnedToBottomState: Bool?
    private var lastVisiblePresentedMessageID: String?
    private var lastReportedObservedPresentedMessageID: String?
    private var deferredScrollRequest: FriendsThreadChatViewportScrollRequest?
    private var initiallyDeferredReplyScrollRequest: FriendsThreadChatViewportScrollRequest?
    private var onPinnedToBottomChanged: ((Bool) -> Void)?
    private var onLatestVisiblePresentedMessageIDChanged: ((String?) -> Void)?
    private var onObservedPresentedMessageVisible: ((String) -> Void)?
    private var onDidHandleScrollRequest: ((FriendsThreadChatViewportScrollRequest) -> Void)?

    func update(
      from view: UIView,
      input: UpdateInput
    ) {
      if layoutSnapshot?.matches(messages: input.messages) != true {
        layoutSnapshot = FriendsThreadChatViewportResolver.layoutSnapshot(messages: input.messages)
      }
      messages = input.messages
      scrollRequest = input.scrollRequest
      if observedPresentedMessageID != input.observedPresentedMessageID {
        lastReportedObservedPresentedMessageID = nil
      }
      observedPresentedMessageID = input.observedPresentedMessageID
      highlightedPresentedMessageID = input.highlightedPresentedMessageID
      onPinnedToBottomChanged = input.onPinnedToBottomChanged
      onLatestVisiblePresentedMessageIDChanged = input.onLatestVisiblePresentedMessageIDChanged
      onObservedPresentedMessageVisible = input.onObservedPresentedMessageVisible
      onDidHandleScrollRequest = input.onDidHandleScrollRequest

      if input.scrollRequest == nil {
        handledScrollRequest = nil
        initiallyDeferredReplyScrollRequest = nil
      }

      attachIfNeeded(from: view)
      reportPinnedToBottomIfNeeded()
      reportLatestVisiblePresentedMessageIDIfNeeded()
      attemptPendingScroll()
      reportObservedPresentedMessageVisibleIfNeeded()
      refreshHighlightedRowsIfNeeded(
        force: input.highlightedPresentedMessageID != lastHighlightedPresentedMessageID)
    }

    private func attachIfNeeded(from view: UIView) {
      guard view.window != nil else { return }

      if let tableView, tableView.window != nil {
        return
      }

      guard let tableView = findChatTableView(from: view) else {
        DispatchQueue.main.async { [weak self, weak view] in
          guard let self, let view, view.window != nil else { return }
          self.attachIfNeeded(from: view)
          self.reportPinnedToBottomIfNeeded()
          self.attemptPendingScroll()
          self.reportObservedPresentedMessageVisibleIfNeeded()
        }
        return
      }

      guard tableView !== self.tableView else { return }

      self.tableView = tableView
      contentOffsetObservation = tableView.observe(\.contentOffset, options: [.initial, .new]) {
        [weak self] tableView, _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.handleContentOffsetChange(for: tableView)
        }
      }
      contentSizeObservation = tableView.observe(\.contentSize, options: [.new]) {
        [weak self] _, _ in
        Task { @MainActor [weak self] in
          self?.reportLatestVisiblePresentedMessageIDIfNeeded()
          self?.attemptPendingScroll()
          self?.reportObservedPresentedMessageVisibleIfNeeded()
        }
      }
    }

    private func handleContentOffsetChange(for tableView: UITableView) {
      guard tableView === self.tableView else { return }
      reportPinnedToBottomIfNeeded()
      reportLatestVisiblePresentedMessageIDIfNeeded()
      reportObservedPresentedMessageVisibleIfNeeded()
    }

    private func reportPinnedToBottomIfNeeded() {
      guard let tableView else { return }
      let isPinnedToBottom = FriendsThreadChatViewportResolver.isPinnedToBottom(
        contentOffsetY: tableView.contentOffset.y
      )
      guard lastPinnedToBottomState != isPinnedToBottom else { return }
      lastPinnedToBottomState = isPinnedToBottom
      DispatchQueue.main.async { [weak self] in
        self?.onPinnedToBottomChanged?(isPinnedToBottom)
      }
    }

    private func reportLatestVisiblePresentedMessageIDIfNeeded() {
      guard let tableView else { return }
      guard let layoutSnapshot = resolvedLayoutSnapshot() else { return }

      let visiblePresentedMessageID =
        FriendsThreadChatViewportResolver.latestVisiblePresentedMessageID(
          in: tableView,
          layoutSnapshot: layoutSnapshot
        )

      guard lastVisiblePresentedMessageID != visiblePresentedMessageID else { return }
      lastVisiblePresentedMessageID = visiblePresentedMessageID
      DispatchQueue.main.async { [weak self] in
        self?.onLatestVisiblePresentedMessageIDChanged?(visiblePresentedMessageID)
      }
    }

    private func reportObservedPresentedMessageVisibleIfNeeded() {
      guard let tableView, let observedPresentedMessageID else { return }
      guard lastReportedObservedPresentedMessageID != observedPresentedMessageID else { return }
      guard let layoutSnapshot = resolvedLayoutSnapshot() else { return }
      guard
        let indexPath = FriendsThreadChatViewportResolver.indexPath(
          for: observedPresentedMessageID,
          in: layoutSnapshot
        )
      else {
        return
      }
      guard tableView.numberOfSections > indexPath.section else { return }
      guard tableView.numberOfRows(inSection: indexPath.section) > indexPath.row else { return }
      guard tableView.cellForRow(at: indexPath) != nil else { return }

      lastReportedObservedPresentedMessageID = observedPresentedMessageID
      DispatchQueue.main.async { [weak self] in
        self?.onObservedPresentedMessageVisible?(observedPresentedMessageID)
      }
    }

    private func attemptPendingScroll() {
      guard let tableView, let scrollRequest else { return }
      guard handledScrollRequest != scrollRequest else { return }

      let hasDeferredInitialReplyScroll = initiallyDeferredReplyScrollRequest == scrollRequest
      if FriendsThreadChatViewportScrollDeferralResolver.shouldDefer(
        kind: scrollRequest.kind,
        hasDeferredInitialReplyScroll: hasDeferredInitialReplyScroll,
        isUserInteracting: isUserInteracting(with: tableView)
      ) {
        if scrollRequest.kind == .reply {
          initiallyDeferredReplyScrollRequest = scrollRequest
        }
        scheduleDeferredScroll(scrollRequest)
        return
      }

      guard let layoutSnapshot = resolvedLayoutSnapshot() else { return }
      guard
        let indexPath = FriendsThreadChatViewportResolver.indexPath(
          for: scrollRequest.presentedMessageID,
          in: layoutSnapshot
        )
      else {
        return
      }
      guard tableView.numberOfSections > indexPath.section else { return }
      guard tableView.numberOfRows(inSection: indexPath.section) > indexPath.row else { return }

      let scrollPosition: UITableView.ScrollPosition =
        switch scrollRequest.kind {
        case .reply:
          .middle
        case .restore:
          .top
        case .liveEdge:
          .top
        }
      let animated = scrollRequest.kind == .reply

      tableView.layoutIfNeeded()

      if animated {
        tableView.scrollToRow(at: indexPath, at: scrollPosition, animated: true)
      } else {
        UIView.performWithoutAnimation {
          tableView.scrollToRow(at: indexPath, at: scrollPosition, animated: false)
          tableView.layoutIfNeeded()
        }
      }

      handledScrollRequest = scrollRequest
      DispatchQueue.main.async { [weak self] in
        self?.onDidHandleScrollRequest?(scrollRequest)
      }
      reportLatestVisiblePresentedMessageIDIfNeeded()
    }

    private func isUserInteracting(with tableView: UITableView) -> Bool {
      tableView.isTracking || tableView.isDragging || tableView.isDecelerating
    }

    private func scheduleDeferredScroll(_ scrollRequest: FriendsThreadChatViewportScrollRequest) {
      guard deferredScrollRequest != scrollRequest else { return }
      deferredScrollRequest = scrollRequest

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self else { return }
        guard self.deferredScrollRequest == scrollRequest else { return }
        self.deferredScrollRequest = nil
        self.attemptPendingScroll()
      }
    }

    private func refreshHighlightedRowsIfNeeded(force: Bool) {
      guard let tableView else { return }
      guard let layoutSnapshot = resolvedLayoutSnapshot() else { return }
      let currentIndexPath =
        highlightedPresentedMessageID.flatMap {
          FriendsThreadChatViewportResolver.indexPath(for: $0, in: layoutSnapshot)
        }
      let previousIndexPath =
        lastHighlightedPresentedMessageID.flatMap {
          FriendsThreadChatViewportResolver.indexPath(for: $0, in: layoutSnapshot)
        }

      guard
        FriendsThreadHighlightRefreshResolver.shouldRefreshRows(
          force: force,
          highlightedPresentedMessageID: highlightedPresentedMessageID,
          lastHighlightedPresentedMessageID: lastHighlightedPresentedMessageID
        )
      else { return }

      let candidateIndexPaths = Set([previousIndexPath, currentIndexPath].compactMap { $0 })
      let validIndexPaths = candidateIndexPaths.filter { indexPath in
        tableView.numberOfSections > indexPath.section
          && tableView.numberOfRows(inSection: indexPath.section) > indexPath.row
      }

      if !validIndexPaths.isEmpty {
        UIView.performWithoutAnimation {
          tableView.reconfigureRows(at: Array(validIndexPaths))
          tableView.layoutIfNeeded()
        }
      }

      lastHighlightedPresentedMessageID = highlightedPresentedMessageID
    }

    private func resolvedLayoutSnapshot() -> FriendsThreadChatViewportResolver.LayoutSnapshot? {
      if let layoutSnapshot, layoutSnapshot.matches(messages: messages) {
        return layoutSnapshot
      }
      guard !messages.isEmpty else { return nil }

      let rebuiltLayoutSnapshot = FriendsThreadChatViewportResolver.layoutSnapshot(
        messages: messages)
      layoutSnapshot = rebuiltLayoutSnapshot
      return rebuiltLayoutSnapshot
    }

    private func findChatTableView(from view: UIView) -> UITableView? {
      let searchRoot = view.window ?? view.nearestRootView()
      let tableViews = searchRoot.descendantViews(ofType: UITableView.self)

      return tableViews.first(where: { candidate in
        guard let delegate = candidate.delegate else { return false }
        return String(reflecting: type(of: delegate)).contains("UIList")
      }) ?? tableViews.first
    }
  }
}

extension UIView {
  fileprivate func nearestRootView() -> UIView {
    var currentView = self

    while let superview = currentView.superview {
      currentView = superview
    }

    return currentView
  }

  fileprivate func descendantViews<T: UIView>(ofType type: T.Type) -> [T] {
    var matches: [T] = []

    if let matchingView = self as? T {
      matches.append(matchingView)
    }

    for subview in subviews {
      matches.append(contentsOf: subview.descendantViews(ofType: type))
    }

    return matches
  }
}

enum FriendsThreadMessagePresentationID {
  static func make(for message: FriendMessage, viewerUserId: String) -> String {
    message.logicalRowIdentity(viewerUserId: viewerUserId)
  }
}

enum FriendsThreadExyteMessageFactory {
  static let typingIndicatorMessageID = "typing-indicator"

  struct ConversationContext {
    let viewerUserId: String
    let currentUserDisplayName: String
    let counterpartDisplayName: String
    let counterpartAvatarUrl: String?
    let quotedMessagesById: [String: FriendMessage]
    let counterpartLastReadMessageId: String?
    let counterpartLastReadAt: Date?
    let showsTypingIndicator: Bool
    let typingIndicatorCreatedAt: Date
    let reactionAttachmentTargets: [String: String]

    init(
      viewerUserId: String,
      currentUserDisplayName: String,
      counterpartDisplayName: String,
      counterpartAvatarUrl: String?,
      quotedMessagesById: [String: FriendMessage],
      counterpartLastReadMessageId: String?,
      counterpartLastReadAt: Date?,
      showsTypingIndicator: Bool,
      typingIndicatorCreatedAt: Date,
      reactionAttachmentTargets: [String: String] = [:]
    ) {
      self.viewerUserId = viewerUserId
      self.currentUserDisplayName = currentUserDisplayName
      self.counterpartDisplayName = counterpartDisplayName
      self.counterpartAvatarUrl = counterpartAvatarUrl
      self.quotedMessagesById = quotedMessagesById
      self.counterpartLastReadMessageId = counterpartLastReadMessageId
      self.counterpartLastReadAt = counterpartLastReadAt
      self.showsTypingIndicator = showsTypingIndicator
      self.typingIndicatorCreatedAt = typingIndicatorCreatedAt
      self.reactionAttachmentTargets = reactionAttachmentTargets
    }
  }

  struct Context {
    let messagesById: [String: FriendMessage]
    let viewerUserId: String
    let currentUserDisplayName: String
    let counterpartDisplayName: String
    let counterpartAvatarUrl: String?
    let latestOutgoingMessageId: String?
    let readReceiptMessageId: String?
    let reactionAttachmentTargets: [String: String]

    init(
      messagesById: [String: FriendMessage],
      viewerUserId: String,
      currentUserDisplayName: String,
      counterpartDisplayName: String,
      counterpartAvatarUrl: String?,
      latestOutgoingMessageId: String?,
      readReceiptMessageId: String?,
      reactionAttachmentTargets: [String: String] = [:]
    ) {
      self.messagesById = messagesById
      self.viewerUserId = viewerUserId
      self.currentUserDisplayName = currentUserDisplayName
      self.counterpartDisplayName = counterpartDisplayName
      self.counterpartAvatarUrl = counterpartAvatarUrl
      self.latestOutgoingMessageId = latestOutgoingMessageId
      self.readReceiptMessageId = readReceiptMessageId
      self.reactionAttachmentTargets = reactionAttachmentTargets
    }
  }

  static func makeMessages(messages: [FriendMessage], conversation: ConversationContext)
    -> [ExyteChat.Message]
  {
    let latestOutgoingMessageId = FriendsThreadMessageStatusResolver.latestOutgoingMessageId(
      messages: messages,
      viewerUserId: conversation.viewerUserId
    )
    let readReceiptMessageId = FriendsThreadMessageStatusResolver.readReceiptMessageId(
      messages: messages,
      viewerUserId: conversation.viewerUserId,
      counterpartLastReadMessageId: conversation.counterpartLastReadMessageId,
      counterpartLastReadAt: conversation.counterpartLastReadAt
    )
    let context = Context(
      messagesById: Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        .merging(conversation.quotedMessagesById) { current, _ in current },
      viewerUserId: conversation.viewerUserId,
      currentUserDisplayName: conversation.currentUserDisplayName,
      counterpartDisplayName: conversation.counterpartDisplayName,
      counterpartAvatarUrl: conversation.counterpartAvatarUrl,
      latestOutgoingMessageId: latestOutgoingMessageId,
      readReceiptMessageId: readReceiptMessageId,
      reactionAttachmentTargets: conversation.reactionAttachmentTargets
    )

    var exyteMessages = messages.map { message in
      makeMessage(message, context: context)
    }

    if conversation.showsTypingIndicator {
      exyteMessages.append(
        makeTypingIndicatorMessage(
          context: context, createdAt: conversation.typingIndicatorCreatedAt))
    }

    return exyteMessages
  }

  static func makeMessage(_ message: FriendMessage, context: Context) -> ExyteChat.Message {
    let isCurrentUser = message.senderUserId == context.viewerUserId
    let user = ExyteChat.User(
      id: message.senderUserId,
      name: isCurrentUser ? context.currentUserDisplayName : context.counterpartDisplayName,
      avatarURL: isCurrentUser ? nil : URL(string: context.counterpartAvatarUrl ?? ""),
      isCurrentUser: isCurrentUser
    )

    let replyMessage = message.replyToMessageId
      .flatMap { context.messagesById[$0] }
      .map {
        makeReplyMessage(
          for: $0,
          viewerUserId: context.viewerUserId,
          currentUserDisplayName: context.currentUserDisplayName,
          counterpartDisplayName: context.counterpartDisplayName,
          counterpartAvatarUrl: context.counterpartAvatarUrl
        )
      }

    return ExyteChat.Message(
      id: FriendsThreadMessagePresentationID.make(for: message, viewerUserId: context.viewerUserId),
      user: user,
      status: exyteStatus(
        for: message,
        viewerUserId: context.viewerUserId,
        latestOutgoingMessageId: context.latestOutgoingMessageId,
        readReceiptMessageId: context.readReceiptMessageId
      ),
      createdAt: message.createdAt,
      text: message.normalizedBody ?? "",
      attachments: [],
      giphyMediaId: exyteMenuMarker(for: message),
      reactions: exyteReactions(
        for: message,
        viewerUserId: context.viewerUserId,
        attachmentId: context.reactionAttachmentTargets[message.id]
      ),
      replyMessage: replyMessage
    )
  }

  static func makeTypingIndicatorMessage(context: Context, createdAt: Date) -> ExyteChat.Message {
    ExyteChat.Message(
      id: typingIndicatorMessageID,
      user: ExyteChat.User(
        id: "typing-indicator-user",
        name: context.counterpartDisplayName,
        avatarURL: URL(string: context.counterpartAvatarUrl ?? ""),
        isCurrentUser: false
      ),
      status: nil,
      createdAt: createdAt,
      text: "",
      attachments: [],
      giphyMediaId: nil,
      reactions: [],
      replyMessage: nil
    )
  }

  private static func exyteMenuMarker(for message: FriendMessage) -> String? {
    guard message.shiftSnapshot != nil else { return nil }
    return FriendsThreadMessageMenuAction.shiftSnapshotForwardMarker
  }

  static func exyteReactions(
    for message: FriendMessage,
    viewerUserId: String,
    attachmentId: String? = nil
  ) -> [ExyteChat.Reaction] {
    let reactions =
      attachmentId
      .flatMap { attachmentId in
        message.attachments.first { $0.id == attachmentId }?.reactions
      } ?? message.reactions

    return reactions.compactMap { reaction in
      guard reaction.viewerHasReacted else { return nil }
      return ExyteChat.Reaction(
        user: ExyteChat.User(
          id: viewerUserId,
          name: "You",
          avatarURL: nil,
          isCurrentUser: true
        ),
        type: .emoji(reaction.emoji),
        status: .sent
      )
    }
  }

  private static func makeReplyMessage(
    for message: FriendMessage,
    viewerUserId: String,
    currentUserDisplayName: String,
    counterpartDisplayName: String,
    counterpartAvatarUrl: String?
  ) -> ExyteChat.ReplyMessage {
    let isCurrentUser = message.senderUserId == viewerUserId
    let user = ExyteChat.User(
      id: message.senderUserId,
      name: isCurrentUser ? currentUserDisplayName : counterpartDisplayName,
      avatarURL: isCurrentUser ? nil : URL(string: counterpartAvatarUrl ?? ""),
      isCurrentUser: isCurrentUser
    )

    return ExyteChat.ReplyMessage(
      id: FriendsThreadMessagePresentationID.make(for: message, viewerUserId: viewerUserId),
      user: user,
      createdAt: message.createdAt,
      text: message.normalizedBody ?? "",
      attachments: [],
      recording: nil
    )
  }

  private static func exyteStatus(
    for message: FriendMessage,
    viewerUserId: String,
    latestOutgoingMessageId: String?,
    readReceiptMessageId: String?
  ) -> ExyteChat.Message.Status? {
    switch FriendsThreadMessageStatusResolver.status(
      for: message,
      viewerUserId: viewerUserId,
      latestOutgoingMessageId: latestOutgoingMessageId,
      readReceiptMessageId: readReceiptMessageId
    ) {
    case .sending:
      return .sending
    case .delivered:
      return .delivered
    case .read:
      return .read
    case .failed:
      return .error(
        DraftMessage(
          id: FriendsThreadMessagePresentationID.make(for: message, viewerUserId: viewerUserId),
          text: message.normalizedBody ?? "",
          medias: [],
          giphyMedia: nil,
          recording: nil,
          replyMessage: nil,
          createdAt: message.createdAt
        )
      )
    case .none:
      return nil
    }
  }
}
