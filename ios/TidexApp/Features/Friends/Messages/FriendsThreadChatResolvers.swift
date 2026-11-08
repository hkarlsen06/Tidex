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
    guard let counterpartLastReadAt else {
      return nil
    }
    guard let normalizedViewerUserId = normalizedUserId(viewerUserId) else {
      return nil
    }

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
    guard let normalizedViewerUserId = normalizedUserId(viewerUserId) else {
      return nil
    }

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
    guard message.senderUserId == viewerUserId, message.messageType == .user else {
      return nil
    }

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
    guard isCurrentUser else {
      return !groupContext.joinsNext
    }

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
    guard hasHorizontalIntent(velocity: velocity, ratio: ratio) else {
      return false
    }

    switch direction {
    case .left:
      return velocity.width < 0

    case .right:
      return velocity.width > 0
    }
  }

  static func shouldTriggerNavigationBack(translation: CGSize, velocity: CGSize) -> Bool {
    guard translation.width > 0 else {
      return false
    }
    guard abs(translation.width) > abs(translation.height) else {
      return false
    }
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
    guard abs(horizontal) > abs(vertical) else {
      return nil
    }

    switch allowedDirection {
    case .left:
      guard horizontal < 0 else {
        return 0
      }

    case .right:
      guard horizontal > 0 else {
        return 0
      }
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
    guard abs(horizontal) > abs(vertical) else {
      return nil
    }
    guard horizontal < 0 else {
      return 0
    }
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
    guard !newMessageIDs.isEmpty, newMessageIDs != oldMessageIDs else {
      return .none
    }

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
    guard let shift = preview.shift else {
      return nil
    }

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
    guard let suppressedUntil else {
      return true
    }
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
    guard !shiftDate.isEmpty else {
      return nil
    }

    if snapshot.ownerUserId == viewerUserId {
      return .shifts(dates: [shiftDate], shiftIds: nil, action: .highlight)
    }

    guard canViewSharedShifts(ownerUserId: snapshot.ownerUserId, cachedFriends: cachedFriends)
    else {
      return nil
    }

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
  static let pullUpToFocusThreshold: CGFloat = 24
  private static let bottomEdgeTolerance: CGFloat = 8

  struct LayoutSnapshot {
    private let messageIDsSignature: [String]
    private let presentedMessageIDsByIndexPath: [IndexPath: String]
    private let indexPathsByPresentedMessageID: [String: IndexPath]
    private let orderByPresentedMessageID: [String: Int]

    init(messages: [ExyteChat.Message]) {
      messageIDsSignature = messages.map(\.id)

      let calendar = Calendar.gregorianCurrent
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

    @MainActor
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

  static func isAtBottomEdge(contentOffsetY: CGFloat, topInset: CGFloat) -> Bool {
    contentOffsetY <= -topInset + bottomEdgeTolerance
  }

  /// The chat table is inverted, so pulling up past the newest message overscrolls
  /// to a negative offset.
  static func isPulledUpPastBottom(contentOffsetY: CGFloat, topInset: CGFloat) -> Bool {
    contentOffsetY < -topInset - pullUpToFocusThreshold
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

  @MainActor
  static func latestVisiblePresentedMessageID(
    in tableView: UITableView,
    messages: [ExyteChat.Message]
  ) -> String? {
    layoutSnapshot(messages: messages).latestVisiblePresentedMessageID(in: tableView)
  }

  @MainActor
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
    guard let messageId else {
      return nil
    }
    guard let message = messages.first(where: { $0.id == messageId }) else {
      return nil
    }
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
    guard let messageId else {
      return nil
    }
    guard let message = messages.first(where: { $0.id == messageId }) else {
      return nil
    }

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
    guard let presentedMessageID else {
      return nil
    }

    return FriendsThreadChatViewportScrollRequest(
      kind: kind,
      messageID: presentedMessageID,
      presentedMessageID: presentedMessageID
    )
  }
}
