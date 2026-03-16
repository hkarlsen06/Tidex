import ExyteChat
import Foundation
import SwiftUI
import UIKit

enum FriendsThreadMessageMenuAction: MessageMenuAction, Sendable {
  case reply
  case copy
  case edit
  case delete
  case report

  func title() -> String {
    switch self {
    case .reply:
      return String(localized: .friendsChatActionReply)
    case .copy:
      return String(localized: .commonCopy)
    case .edit:
      return String(localized: "friends.chat.action.edit", table: "Localizable")
    case .delete:
      return String(localized: "friends.chat.action.delete", table: "Localizable")
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

    if message.user.isCurrentUser {
      var items: [Self] = [.reply]
      if hasText {
        items.append(.copy)
        items.append(.edit)
      }
      items.append(.delete)
      return items
    }

    var items: [Self] = [.reply]
    if hasText {
      items.append(.copy)
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

    if let counterpartLastReadMessageId,
      let readMessageIndex = messages.firstIndex(where: { $0.id == counterpartLastReadMessageId })
    {
      return messages[...readMessageIndex].last(where: { $0.senderUserId == viewerUserId })?.id
    }

    return messages.last(where: {
      $0.senderUserId == viewerUserId && $0.createdAt <= counterpartLastReadAt
    })?.id
  }

  static func latestOutgoingMessageId(messages: [FriendMessage], viewerUserId: String) -> String? {
    messages.last(where: { $0.senderUserId == viewerUserId })?.id
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
    guard !groupContext.joinsNext else { return false }
    guard isCurrentUser else { return true }

    switch messageStatus {
    case .sending, .failed:
      return false
    case .delivered, .read:
      return true
    case .none:
      return message.sendState == .sent
    }
  }
}

enum FriendsThreadMessageListChangeResolver {
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

struct FriendsThreadChatViewportScrollRequest: Equatable {
  enum Kind: Equatable {
    case reply
    case restore
  }

  let kind: Kind
  let messageID: String
  let presentedMessageID: String
}

enum FriendsThreadChatViewportResolver {
  private static let pinnedToBottomThreshold: CGFloat = 1

  static func isPinnedToBottom(contentOffsetY: CGFloat) -> Bool {
    contentOffsetY <= pinnedToBottomThreshold
  }

  static func indexPath(for presentedMessageID: String, in messages: [ExyteChat.Message])
    -> IndexPath?
  {
    let calendar = Calendar.current
    let sectionDates = Set(messages.map { calendar.startOfDay(for: $0.createdAt) }).sorted(by: >)

    for (sectionIndex, sectionDate) in sectionDates.enumerated() {
      let sectionMessages = Array(
        messages.filter {
          calendar.isDate($0.createdAt, inSameDayAs: sectionDate)
        }.reversed())

      if let rowIndex = sectionMessages.firstIndex(where: { $0.id == presentedMessageID }) {
        return IndexPath(row: rowIndex, section: sectionIndex)
      }
    }

    return nil
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

    return makeRequest(
      kind: .restore,
      messageId: restoreTargetMessageId,
      messages: messages,
      viewerUserId: viewerUserId
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
      highlightedMessage.text += redrawMarker
      return highlightedMessage
    }
  }

  static func isHighlighted(_ message: ExyteChat.Message) -> Bool {
    message.text.hasSuffix(redrawMarker)
  }

  static func visibleText(for message: ExyteChat.Message) -> String {
    guard isHighlighted(message) else { return message.text }
    return String(message.text.dropLast(redrawMarker.count))
  }
}

struct FriendsThreadChatViewportBridge: UIViewRepresentable {
  let messages: [ExyteChat.Message]
  let scrollRequest: FriendsThreadChatViewportScrollRequest?
  let highlightedPresentedMessageID: String?
  let onPinnedToBottomChanged: (Bool) -> Void
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
      messages: messages,
      scrollRequest: scrollRequest,
      highlightedPresentedMessageID: highlightedPresentedMessageID,
      onPinnedToBottomChanged: onPinnedToBottomChanged,
      onDidHandleScrollRequest: onDidHandleScrollRequest
    )
  }

  @MainActor
  final class Coordinator {
    private weak var tableView: UITableView?
    private var contentOffsetObservation: NSKeyValueObservation?
    private var contentSizeObservation: NSKeyValueObservation?
    private var messages: [ExyteChat.Message] = []
    private var scrollRequest: FriendsThreadChatViewportScrollRequest?
    private var highlightedPresentedMessageID: String?
    private var lastHighlightedPresentedMessageID: String?
    private var lastVisibleHighlightedIndexPath: IndexPath?
    private var handledScrollRequest: FriendsThreadChatViewportScrollRequest?
    private var lastPinnedToBottomState: Bool?
    private var onPinnedToBottomChanged: ((Bool) -> Void)?
    private var onDidHandleScrollRequest: ((FriendsThreadChatViewportScrollRequest) -> Void)?

    func update(
      from view: UIView,
      messages: [ExyteChat.Message],
      scrollRequest: FriendsThreadChatViewportScrollRequest?,
      highlightedPresentedMessageID: String?,
      onPinnedToBottomChanged: @escaping (Bool) -> Void,
      onDidHandleScrollRequest: @escaping (FriendsThreadChatViewportScrollRequest) -> Void
    ) {
      self.messages = messages
      self.scrollRequest = scrollRequest
      self.highlightedPresentedMessageID = highlightedPresentedMessageID
      self.onPinnedToBottomChanged = onPinnedToBottomChanged
      self.onDidHandleScrollRequest = onDidHandleScrollRequest

      if scrollRequest == nil {
        handledScrollRequest = nil
      }

      attachIfNeeded(from: view)
      reportPinnedToBottomIfNeeded()
      attemptPendingScroll()
      refreshHighlightedRowsIfNeeded(
        force: highlightedPresentedMessageID != lastHighlightedPresentedMessageID)
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
          self?.attemptPendingScroll()
        }
      }
    }

    private func handleContentOffsetChange(for tableView: UITableView) {
      guard tableView === self.tableView else { return }
      reportPinnedToBottomIfNeeded()
      refreshHighlightedRowsIfNeeded(force: false)
    }

    private func reportPinnedToBottomIfNeeded() {
      guard let tableView else { return }
      let isPinnedToBottom = FriendsThreadChatViewportResolver.isPinnedToBottom(
        contentOffsetY: tableView.contentOffset.y
      )
      guard lastPinnedToBottomState != isPinnedToBottom else { return }
      lastPinnedToBottomState = isPinnedToBottom
      onPinnedToBottomChanged?(isPinnedToBottom)
    }

    private func attemptPendingScroll() {
      guard let tableView, let scrollRequest else { return }
      guard handledScrollRequest != scrollRequest else { return }
      guard
        let indexPath = FriendsThreadChatViewportResolver.indexPath(
          for: scrollRequest.presentedMessageID,
          in: messages
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
      onDidHandleScrollRequest?(scrollRequest)
    }

    private func refreshHighlightedRowsIfNeeded(force: Bool) {
      guard let tableView else { return }
      let currentIndexPath =
        highlightedPresentedMessageID.flatMap {
          FriendsThreadChatViewportResolver.indexPath(for: $0, in: messages)
        }
      let previousIndexPath =
        lastHighlightedPresentedMessageID.flatMap {
          FriendsThreadChatViewportResolver.indexPath(for: $0, in: messages)
        }
      let currentVisibleIndexPath =
        currentIndexPath.flatMap { tableView.cellForRow(at: $0) == nil ? nil : $0 }

      let shouldRefresh =
        force
        || highlightedPresentedMessageID != lastHighlightedPresentedMessageID
        || currentVisibleIndexPath != lastVisibleHighlightedIndexPath

      guard shouldRefresh else { return }

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
      lastVisibleHighlightedIndexPath = currentVisibleIndexPath
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
    let normalizedClientId = message.clientId.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    if message.senderUserId == viewerUserId, !normalizedClientId.isEmpty {
      return "client:\(normalizedClientId)"
    }

    return "message:\(message.id)"
  }
}

enum FriendsThreadExyteMessageFactory {
  struct ConversationContext {
    let viewerUserId: String
    let currentUserDisplayName: String
    let counterpartDisplayName: String
    let counterpartAvatarUrl: String?
    let quotedMessagesById: [String: FriendMessage]
    let counterpartLastReadMessageId: String?
    let counterpartLastReadAt: Date?
  }

  struct Context {
    let messagesById: [String: FriendMessage]
    let viewerUserId: String
    let currentUserDisplayName: String
    let counterpartDisplayName: String
    let counterpartAvatarUrl: String?
    let latestOutgoingMessageId: String?
    let readReceiptMessageId: String?
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
      readReceiptMessageId: readReceiptMessageId
    )

    return messages.map { message in
      makeMessage(message, context: context)
    }
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
      reactions: exyteReactions(for: message, viewerUserId: context.viewerUserId),
      replyMessage: replyMessage
    )
  }

  static func exyteReactions(
    for message: FriendMessage,
    viewerUserId: String
  ) -> [ExyteChat.Reaction] {
    message.reactions.compactMap { reaction in
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
