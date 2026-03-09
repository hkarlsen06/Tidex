import ChatLayout
import SwiftUI
import UIKit

struct FriendsChatTimelineView: UIViewControllerRepresentable {
  let messages: [FriendMessage]
  let quotedMessagesById: [String: FriendMessage]
  let viewerUserId: String
  let counterpartLastReadMessageId: String?
  let counterpartLastReadAt: Date?
  let currentUserDisplayName: String
  let counterpartDisplayName: String
  let highlightedMessageId: String?
  let showTypingIndicator: Bool
  let bottomContentInset: CGFloat
  let scrollToBottomTrigger: Int
  let restoreScrollTargetMessageId: String?
  let replyScrollTargetMessageId: String?
  let onBackgroundTap: () -> Void
  let onPinnedToBottomChanged: (Bool) -> Void
  let onReachedTopMessage: (String) -> Void
  let onReply: (FriendMessage) -> Void
  let onRetryMessage: (String) -> Void
  let onReportMessage: (String) -> Void
  let onToggleReaction: (FriendMessage, String) -> Void
  let onOpenMessageActions: (FriendMessage, CGRect) -> Void
  let onTapQuotedMessage: (FriendMessage) -> Void
  let onConsumeRestoreScrollTarget: () -> Void
  let onConsumeReplyScrollTarget: (String) -> Void

  func makeUIViewController(context: Context) -> FriendsChatTimelineViewController {
    let controller = FriendsChatTimelineViewController()
    controller.onBackgroundTap = onBackgroundTap
    controller.onPinnedToBottomChanged = onPinnedToBottomChanged
    controller.onReachedTopMessage = onReachedTopMessage
    controller.onReply = onReply
    controller.onRetryMessage = onRetryMessage
    controller.onReportMessage = onReportMessage
    controller.onToggleReaction = onToggleReaction
    controller.onOpenMessageActions = onOpenMessageActions
    controller.onTapQuotedMessage = onTapQuotedMessage
    return controller
  }

  func updateUIViewController(
    _ uiViewController: FriendsChatTimelineViewController,
    context: Context
  ) {
    uiViewController.onBackgroundTap = onBackgroundTap
    uiViewController.onPinnedToBottomChanged = onPinnedToBottomChanged
    uiViewController.onReachedTopMessage = onReachedTopMessage
    uiViewController.onReply = onReply
    uiViewController.onRetryMessage = onRetryMessage
    uiViewController.onReportMessage = onReportMessage
    uiViewController.onToggleReaction = onToggleReaction
    uiViewController.onOpenMessageActions = onOpenMessageActions
    uiViewController.onTapQuotedMessage = onTapQuotedMessage
    uiViewController.apply(
      config: FriendsChatTimelineConfiguration(
        messages: messages,
        quotedMessagesById: quotedMessagesById,
        viewerUserId: viewerUserId,
        counterpartLastReadMessageId: counterpartLastReadMessageId,
        counterpartLastReadAt: counterpartLastReadAt,
        currentUserDisplayName: currentUserDisplayName,
        counterpartDisplayName: counterpartDisplayName,
        highlightedMessageId: highlightedMessageId,
        showTypingIndicator: showTypingIndicator,
        bottomContentInset: bottomContentInset,
        scrollToBottomTrigger: scrollToBottomTrigger,
        restoreScrollTargetMessageId: restoreScrollTargetMessageId,
        replyScrollTargetMessageId: replyScrollTargetMessageId
      ),
      onConsumeRestoreScrollTarget: onConsumeRestoreScrollTarget,
      onConsumeReplyScrollTarget: onConsumeReplyScrollTarget
    )
  }
}

struct FriendsChatTimelineConfiguration {
  let messages: [FriendMessage]
  let quotedMessagesById: [String: FriendMessage]
  let viewerUserId: String
  let counterpartLastReadMessageId: String?
  let counterpartLastReadAt: Date?
  let currentUserDisplayName: String
  let counterpartDisplayName: String
  let highlightedMessageId: String?
  let showTypingIndicator: Bool
  let bottomContentInset: CGFloat
  let scrollToBottomTrigger: Int
  let restoreScrollTargetMessageId: String?
  let replyScrollTargetMessageId: String?
}

@MainActor
final class FriendsChatTimelineViewController: UIViewController, UIGestureRecognizerDelegate {
  var onBackgroundTap: (() -> Void)?
  var onPinnedToBottomChanged: ((Bool) -> Void)?
  var onReachedTopMessage: ((String) -> Void)?
  var onReply: ((FriendMessage) -> Void)?
  var onRetryMessage: ((String) -> Void)?
  var onReportMessage: ((String) -> Void)?
  var onToggleReaction: ((FriendMessage, String) -> Void)?
  var onOpenMessageActions: ((FriendMessage, CGRect) -> Void)?
  var onTapQuotedMessage: ((FriendMessage) -> Void)?

  private let chatLayout = CollectionViewChatLayout()
  private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: chatLayout)
  private lazy var backgroundTapRecognizer: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap))
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = self
    return recognizer
  }()

  private var messages: [FriendMessage] = []
  private var quotedMessagesById: [String: FriendMessage] = [:]
  private var viewerUserId = ""
  private var counterpartLastReadMessageId: String?
  private var counterpartLastReadAt: Date?
  private var currentUserDisplayName = ""
  private var counterpartDisplayName = ""
  private var highlightedMessageId: String?
  private var showTypingIndicator = false
  private var lastAppliedBottomInset: CGFloat = 0
  private var lastScrollToBottomTrigger = 0
  private var lastRestoreTargetMessageId: String?
  private var lastReplyTargetMessageId: String?
  private var didInitialScroll = false
  private var isPinnedToBottom = true {
    didSet {
      guard oldValue != isPinnedToBottom else { return }
      onPinnedToBottomChanged?(isPinnedToBottom)
    }
  }

  private enum UpdatePlan {
    case none
    case fullReload(preservedSnapshot: ChatLayoutPositionSnapshot?)
    case insertTypingIndicator(indexPath: IndexPath, reloadedIndexPaths: [IndexPath])
    case removeTypingIndicator(indexPath: IndexPath, reloadedIndexPaths: [IndexPath])
    case prepend(
      insertedIndexPaths: [IndexPath],
      reloadedIndexPaths: [IndexPath],
      preservedSnapshot: ChatLayoutPositionSnapshot?
    )
    case append(insertedIndexPaths: [IndexPath], reloadedIndexPaths: [IndexPath])
    case reload(indexPaths: [IndexPath])
  }

  private struct RenderState {
    let viewerUserId: String
    let messages: [FriendMessage]
    let quotedMessagesById: [String: FriendMessage]
    let counterpartLastReadMessageId: String?
    let counterpartLastReadAt: Date?
    let highlightedMessageId: String?
    let showTypingIndicator: Bool
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .clear

    chatLayout.settings.interItemSpacing = Spacing.sm
    chatLayout.settings.estimatedItemSize = CGSize(width: 320, height: 88)
    chatLayout.settings.additionalInsets = UIEdgeInsets(
      top: Spacing.sm,
      left: Spacing.md,
      bottom: Spacing.sm,
      right: Spacing.md
    )
    chatLayout.keepContentOffsetAtBottomOnBatchUpdates = true
    chatLayout.keepContentAtBottomOfVisibleArea = true
    chatLayout.processOnlyVisibleItemsOnAnimatedBatchUpdates = false
    chatLayout.delegate = self

    collectionView.backgroundColor = .clear
    collectionView.alwaysBounceVertical = true
    collectionView.keyboardDismissMode = .interactive
    collectionView.showsHorizontalScrollIndicator = false
    collectionView.isPrefetchingEnabled = false
    collectionView.selfSizingInvalidation = .disabled
    chatLayout.supportSelfSizingInvalidation = false
    collectionView.dataSource = self
    collectionView.delegate = self
    collectionView.contentInsetAdjustmentBehavior = .never
    collectionView.register(
      FriendsChatTimelineCell.self,
      forCellWithReuseIdentifier: FriendsChatTimelineCell.reuseIdentifier)
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.addGestureRecognizer(backgroundTapRecognizer)

    view.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  @objc
  private func handleBackgroundTap() {
    onBackgroundTap?()
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    true
  }

  func apply(
    config: FriendsChatTimelineConfiguration,
    onConsumeRestoreScrollTarget: @escaping () -> Void,
    onConsumeReplyScrollTarget: @escaping (String) -> Void
  ) {
    let previousState = RenderState(
      viewerUserId: self.viewerUserId,
      messages: self.messages,
      quotedMessagesById: self.quotedMessagesById,
      counterpartLastReadMessageId: self.counterpartLastReadMessageId,
      counterpartLastReadAt: self.counterpartLastReadAt,
      highlightedMessageId: self.highlightedMessageId,
      showTypingIndicator: self.showTypingIndicator
    )
    let nextState = RenderState(
      viewerUserId: config.viewerUserId,
      messages: config.messages,
      quotedMessagesById: config.quotedMessagesById,
      counterpartLastReadMessageId: config.counterpartLastReadMessageId,
      counterpartLastReadAt: config.counterpartLastReadAt,
      highlightedMessageId: config.highlightedMessageId,
      showTypingIndicator: config.showTypingIndicator
    )
    let wasPinnedToBottom = isNearBottom()
    let updatePlan = makeUpdatePlan(
      previousState: previousState,
      nextState: nextState,
      wasPinnedToBottom: wasPinnedToBottom
    )

    self.messages = config.messages
    self.quotedMessagesById = config.quotedMessagesById
    self.viewerUserId = config.viewerUserId
    self.counterpartLastReadMessageId = config.counterpartLastReadMessageId
    self.counterpartLastReadAt = config.counterpartLastReadAt
    self.currentUserDisplayName = config.currentUserDisplayName
    self.counterpartDisplayName = config.counterpartDisplayName
    self.highlightedMessageId = config.highlightedMessageId
    self.showTypingIndicator = config.showTypingIndicator
    updateInsets(config.bottomContentInset)

    apply(updatePlan: updatePlan) { [weak self] in
      guard let self else { return }
      var consumedRestoreScrollTarget = false
      var consumedReplyScrollTarget = false

      if !didInitialScroll, !config.messages.isEmpty {
        didInitialScroll = true
        scrollToBottom(animated: false)
      } else if config.scrollToBottomTrigger != lastScrollToBottomTrigger {
        scrollToBottom(animated: true)
      } else if wasPinnedToBottom,
        didAppendMessages(old: previousState.messages, new: config.messages)
      {
        scrollToBottom(animated: true)
      }

      if let restoreScrollTargetMessageId = config.restoreScrollTargetMessageId,
        restoreScrollTargetMessageId != lastRestoreTargetMessageId
      {
        scrollToMessage(id: restoreScrollTargetMessageId, position: .top, animated: false)
        onConsumeRestoreScrollTarget()
        consumedRestoreScrollTarget = true
      }

      if let replyScrollTargetMessageId = config.replyScrollTargetMessageId,
        replyScrollTargetMessageId != lastReplyTargetMessageId
      {
        scrollToMessage(
          id: replyScrollTargetMessageId, position: .centeredVertically, animated: true)
        onConsumeReplyScrollTarget(replyScrollTargetMessageId)
        consumedReplyScrollTarget = true
      }

      lastScrollToBottomTrigger = config.scrollToBottomTrigger
      lastRestoreTargetMessageId =
        consumedRestoreScrollTarget ? nil : config.restoreScrollTargetMessageId
      lastReplyTargetMessageId =
        consumedReplyScrollTarget ? nil : config.replyScrollTargetMessageId
      updatePinnedState()
    }
  }

  private func updateInsets(_ bottomContentInset: CGFloat) {
    guard lastAppliedBottomInset != bottomContentInset else { return }
    lastAppliedBottomInset = bottomContentInset
    collectionView.contentInset.bottom = bottomContentInset
    collectionView.verticalScrollIndicatorInsets.bottom = bottomContentInset
  }

  private func makeUpdatePlan(
    previousState: RenderState,
    nextState: RenderState,
    wasPinnedToBottom: Bool
  ) -> UpdatePlan {
    let previousMessages = previousState.messages
    let newMessages = nextState.messages
    let reloadedIndexPaths = reloadedIndexPaths(previousState: previousState, nextState: nextState)

    if previousState.showTypingIndicator != nextState.showTypingIndicator,
      previousMessages.map(\.id) == newMessages.map(\.id)
    {
      let typingIndexPath = IndexPath(item: newMessages.count, section: 0)
      if nextState.showTypingIndicator {
        return .insertTypingIndicator(
          indexPath: typingIndexPath,
          reloadedIndexPaths: reloadedIndexPaths
        )
      } else {
        return .removeTypingIndicator(
          indexPath: typingIndexPath,
          reloadedIndexPaths: reloadedIndexPaths
        )
      }
    }

    guard previousState.showTypingIndicator == nextState.showTypingIndicator else {
      return .fullReload(preservedSnapshot: nil)
    }

    guard !previousMessages.isEmpty else {
      return .fullReload(preservedSnapshot: nil)
    }

    guard !newMessages.isEmpty else {
      return .fullReload(preservedSnapshot: nil)
    }

    let previousIds = previousMessages.map(\.id)
    let newIds = newMessages.map(\.id)

    if previousIds == newIds {
      return reloadedIndexPaths.isEmpty ? .none : .reload(indexPaths: reloadedIndexPaths)
    }

    if newMessages.count > previousMessages.count,
      Array(newIds.suffix(previousIds.count)) == previousIds
    {
      let insertedCount = newMessages.count - previousMessages.count
      let insertedIndexPaths = (0..<insertedCount).map { IndexPath(item: $0, section: 0) }
      let insertedItems = Set(insertedIndexPaths.map(\.item))
      return .prepend(
        insertedIndexPaths: insertedIndexPaths,
        reloadedIndexPaths: reloadedIndexPaths.filter { !insertedItems.contains($0.item) },
        preservedSnapshot: nil
      )
    }

    if newMessages.count > previousMessages.count,
      Array(newIds.prefix(previousIds.count)) == previousIds
    {
      let insertedIndexPaths = (previousMessages.count..<newMessages.count).map {
        IndexPath(item: $0, section: 0)
      }
      let insertedItems = Set(insertedIndexPaths.map(\.item))
      return .append(
        insertedIndexPaths: insertedIndexPaths,
        reloadedIndexPaths: reloadedIndexPaths.filter { !insertedItems.contains($0.item) }
      )
    }

    return .fullReload(preservedSnapshot: nil)
  }

  private func apply(updatePlan: UpdatePlan, completion: @escaping () -> Void) {
    switch updatePlan {
    case .none:
      completion()

    case .fullReload(let preservedSnapshot):
      UIView.performWithoutAnimation {
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
      }
      if let preservedSnapshot {
        chatLayout.restoreContentOffset(with: preservedSnapshot)
      }
      completion()

    case .insertTypingIndicator(let indexPath, let reloadedIndexPaths):
      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates {
          collectionView.insertItems(at: [indexPath])
          reloadItems(at: reloadedIndexPaths)
        } completion: { [weak self] _ in
          self?.invalidateTimelineLayout()
          completion()
        }
      }

    case .removeTypingIndicator(let indexPath, let reloadedIndexPaths):
      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates {
          collectionView.deleteItems(at: [indexPath])
          reloadItems(at: reloadedIndexPaths)
        } completion: { [weak self] _ in
          self?.invalidateTimelineLayout()
          completion()
        }
      }

    case .prepend(let insertedIndexPaths, let reloadedIndexPaths, let preservedSnapshot):
      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates {
          collectionView.insertItems(at: insertedIndexPaths)
          reloadItems(at: reloadedIndexPaths)
        } completion: { [weak self] _ in
          self?.invalidateTimelineLayout()
          if let preservedSnapshot, let self {
            self.chatLayout.restoreContentOffset(with: preservedSnapshot)
          }
          completion()
        }
      }

    case .append(let insertedIndexPaths, let reloadedIndexPaths):
      collectionView.performBatchUpdates {
        collectionView.insertItems(at: insertedIndexPaths)
        reloadItems(at: reloadedIndexPaths)
      } completion: { [weak self] _ in
        self?.invalidateTimelineLayout()
        completion()
      }

    case .reload(let indexPaths):
      guard !indexPaths.isEmpty else {
        completion()
        return
      }

      collectionView.performBatchUpdates {
        reloadItems(at: indexPaths)
      } completion: { [weak self] _ in
        self?.invalidateTimelineLayout()
        completion()
      }
    }
  }

  private func invalidateTimelineLayout() {
    collectionView.collectionViewLayout.invalidateLayout()
    collectionView.layoutIfNeeded()
  }

  private func reloadItems(at indexPaths: [IndexPath]) {
    guard !indexPaths.isEmpty else { return }
    collectionView.reloadItems(at: indexPaths)
  }

  private func reloadedIndexPaths(
    previousState: RenderState,
    nextState: RenderState
  ) -> [IndexPath] {
    let previousMessages = previousState.messages
    let newMessages = nextState.messages
    var indicesToReload = Set<Int>()

    for index in newMessages.indices {
      if previousMessages.indices.contains(index), previousMessages[index] != newMessages[index] {
        indicesToReload.insert(index)
      }

      guard let replyToMessageId = newMessages[index].replyToMessageId else { continue }
      let previousQuoted = resolvedQuotedMessage(
        withId: replyToMessageId,
        from: previousState.messages,
        quotedMessagesById: previousState.quotedMessagesById
      )
      let newQuoted = resolvedQuotedMessage(
        withId: replyToMessageId,
        from: nextState.messages,
        quotedMessagesById: nextState.quotedMessagesById
      )
      if previousQuoted != newQuoted {
        indicesToReload.insert(index)
      }
    }

    if let previousHighlightedMessageId = previousState.highlightedMessageId,
      let index = newMessages.firstIndex(where: { $0.id == previousHighlightedMessageId })
    {
      indicesToReload.insert(index)
    }

    if let newHighlightedMessageId = nextState.highlightedMessageId,
      let index = newMessages.firstIndex(where: { $0.id == newHighlightedMessageId })
    {
      indicesToReload.insert(index)
    }

    let previousReadReceiptMessageId = readReceiptMessageId(
      messages: previousState.messages,
      viewerUserId: previousState.viewerUserId,
      counterpartLastReadMessageId: previousState.counterpartLastReadMessageId,
      counterpartLastReadAt: previousState.counterpartLastReadAt
    )
    let newReadReceiptMessageId = readReceiptMessageId(
      messages: nextState.messages,
      viewerUserId: nextState.viewerUserId,
      counterpartLastReadMessageId: nextState.counterpartLastReadMessageId,
      counterpartLastReadAt: nextState.counterpartLastReadAt
    )

    if let previousReadReceiptMessageId,
      let index = newMessages.firstIndex(where: { $0.id == previousReadReceiptMessageId })
    {
      indicesToReload.insert(index)
    }

    if let newReadReceiptMessageId,
      let index = newMessages.firstIndex(where: { $0.id == newReadReceiptMessageId })
    {
      indicesToReload.insert(index)
    }

    return
      indicesToReload
      .sorted()
      .map { IndexPath(item: $0, section: 0) }
  }

  private func resolvedQuotedMessage(
    withId messageId: String,
    from messages: [FriendMessage],
    quotedMessagesById: [String: FriendMessage]
  ) -> FriendMessage? {
    messages.first(where: { $0.id == messageId }) ?? quotedMessagesById[messageId]
  }

  private func didAppendMessages(old: [FriendMessage], new: [FriendMessage]) -> Bool {
    guard !new.isEmpty else { return false }
    guard !old.isEmpty else { return true }

    let prependedOnly =
      new.count > old.count
      && new.first?.id != old.first?.id
      && new.last?.id == old.last?.id
    if prependedOnly {
      return false
    }

    return new.count != old.count || new.last?.id != old.last?.id
  }

  private func scrollToBottom(animated: Bool) {
    guard !messages.isEmpty else { return }
    let lastIndexPath = IndexPath(item: messages.count - 1, section: 0)
    if animated {
      collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: true)
    } else {
      UIView.performWithoutAnimation {
        collectionView.scrollToItem(at: lastIndexPath, at: .bottom, animated: false)
        collectionView.layoutIfNeeded()
      }
    }
  }

  private func scrollToMessage(
    id messageId: String,
    position: UICollectionView.ScrollPosition,
    animated: Bool
  ) {
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    let indexPath = IndexPath(item: index, section: 0)
    collectionView.scrollToItem(at: indexPath, at: position, animated: animated)
  }

  private func isNearBottom() -> Bool {
    let visibleBottom =
      collectionView.contentOffset.y
      + collectionView.bounds.height
      - collectionView.adjustedContentInset.bottom
    let distance = collectionView.contentSize.height - visibleBottom
    return distance <= 24
  }

  private func updatePinnedState() {
    isPinnedToBottom = isNearBottom()
  }
}

extension FriendsChatTimelineViewController: UICollectionViewDataSource {
  func numberOfSections(in collectionView: UICollectionView) -> Int {
    1
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
    -> Int
  {
    messages.count + (showTypingIndicator ? 1 : 0)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let reusableCell = collectionView.dequeueReusableCell(
      withReuseIdentifier: FriendsChatTimelineCell.reuseIdentifier,
      for: indexPath
    )
    guard let cell = reusableCell as? FriendsChatTimelineCell else {
      return reusableCell
    }

    if isTypingIndicatorItem(at: indexPath) {
      cell.configure {
        FriendsChatTypingRowContent()
      }
      return cell
    }

    let message = messages[indexPath.item]
    let quotedMessage = message.replyToMessageId.flatMap { replyId in
      messages.first(where: { $0.id == replyId }) ?? quotedMessagesById[replyId]
    }
    let quotedPreview = quotedMessage.map { quotedMessage in
      FriendsChatReplyPreviewModel(
        snippet: quotedMessage.body?
          .replacingOccurrences(of: "\n", with: " ")
          .trimmingCharacters(in: .whitespacesAndNewlines),
        hasImageAttachment: quotedMessage.hasImageAttachment
      )
    }
    let nextMessage = indexPath.item < messages.count - 1 ? messages[indexPath.item + 1] : nil
    let previousMessage = indexPath.item > 0 ? messages[indexPath.item - 1] : nil
    let readReceiptMessageId = readReceiptMessageId()
    let latestOutgoingMessageId = latestOutgoingMessageId()
    let showsDateSeparator =
      previousMessage == nil
      || !Calendar.current.isDate(
        previousMessage?.createdAt ?? message.createdAt,
        equalTo: message.createdAt,
        toGranularity: .day
      )
    let isCurrentUser = message.senderUserId == viewerUserId
    let showsSenderLabel = previousMessage?.senderUserId != message.senderUserId
    let senderFirstName = firstName(
      for: isCurrentUser ? currentUserDisplayName : counterpartDisplayName
    )
    let messageStatus = messageStatus(
      for: message,
      latestOutgoingMessageId: latestOutgoingMessageId,
      readReceiptMessageId: readReceiptMessageId
    )
    let shouldShowTimestamp = shouldShowTimestamp(
      for: message,
      isCurrentUser: isCurrentUser,
      defaultShowsTimestamp: defaultShowsTimestamp(for: message, nextMessage: nextMessage),
      messageStatus: messageStatus
    )

    cell.configure {
      FriendsChatMessageRowContent(
        message: message,
        quotedPreview: quotedPreview,
        isCurrentUser: isCurrentUser,
        isHighlighted: highlightedMessageId == message.id,
        senderFirstName: senderFirstName,
        separatorDate: showsDateSeparator ? message.createdAt : nil,
        showsSenderLabel: showsSenderLabel,
        showsTimestamp: shouldShowTimestamp,
        messageStatus: messageStatus,
        onReply: { [weak self] in
          self?.onReply?(message)
        },
        onRetry: { [weak self] in
          self?.onRetryMessage?(message.id)
        },
        onReportMessage: { [weak self] in
          self?.onReportMessage?(message.id)
        },
        onToggleReaction: { [weak self] emoji in
          self?.onToggleReaction?(message, emoji)
        },
        onOpenActions: { [weak self] in
          self?.openMessageActions(for: message)
        },
        onTapQuotedMessage: { [weak self] in
          self?.onTapQuotedMessage?(message)
        }
      )
    }

    return cell
  }
}

extension FriendsChatTimelineViewController: UICollectionViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    updatePinnedState()
  }

  func collectionView(
    _ collectionView: UICollectionView,
    willDisplay cell: UICollectionViewCell,
    forItemAt indexPath: IndexPath
  ) {
    guard indexPath.item == 0, messages.indices.contains(indexPath.item) else { return }
    onReachedTopMessage?(messages[indexPath.item].id)
  }
}

extension FriendsChatTimelineViewController: ChatLayoutDelegate {
  func sizeForItem(
    _ chatLayout: CollectionViewChatLayout,
    of kind: ItemKind,
    at indexPath: IndexPath
  ) -> ItemSize {
    .estimated(CGSize(width: collectionView.bounds.width, height: 88))
  }

  func alignmentForItem(
    _ chatLayout: CollectionViewChatLayout,
    of kind: ItemKind,
    at indexPath: IndexPath
  ) -> ChatItemAlignment {
    if isTypingIndicatorItem(at: indexPath) {
      return .leading
    }
    return .fullWidth
  }

  private func isTypingIndicatorItem(at indexPath: IndexPath) -> Bool {
    showTypingIndicator && indexPath.item == messages.count
  }

  private func firstName(for displayName: String) -> String {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "User" }
    return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
  }

  private func readReceiptMessageId() -> String? {
    readReceiptMessageId(
      messages: messages,
      viewerUserId: viewerUserId,
      counterpartLastReadMessageId: counterpartLastReadMessageId,
      counterpartLastReadAt: counterpartLastReadAt
    )
  }

  private func latestOutgoingMessageId() -> String? {
    messages.last(where: { $0.senderUserId == viewerUserId })?.id
  }

  private func messageStatus(
    for message: FriendMessage,
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

  private func shouldShowTimestamp(
    for message: FriendMessage,
    isCurrentUser: Bool,
    defaultShowsTimestamp: Bool,
    messageStatus: FriendsChatMessageStatus?
  ) -> Bool {
    guard isCurrentUser else { return defaultShowsTimestamp }

    switch messageStatus {
    case .sending, .failed:
      return false
    case .delivered, .read:
      return true
    case .none:
      return message.sendState == .sent && defaultShowsTimestamp
    }
  }

  private func defaultShowsTimestamp(
    for message: FriendMessage,
    nextMessage: FriendMessage?
  ) -> Bool {
    guard let nextMessage else { return true }

    let sharesSender = nextMessage.senderUserId == message.senderUserId
    let sharesMinute = Calendar.current.isDate(
      message.createdAt,
      equalTo: nextMessage.createdAt,
      toGranularity: .minute
    )

    return !(sharesSender && sharesMinute)
  }

  private func readReceiptMessageId(
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
      $0.senderUserId == viewerUserId && $0.createdAt < counterpartLastReadAt
    })?.id
  }

  private func openMessageActions(for message: FriendMessage) {
    guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
    let indexPath = IndexPath(item: index, section: 0)

    let sourceFrame: CGRect
    if let cell = collectionView.cellForItem(at: indexPath) {
      sourceFrame = cell.convert(cell.bounds, to: view)
    } else if let attributes = collectionView.layoutAttributesForItem(at: indexPath) {
      sourceFrame = collectionView.convert(attributes.frame, to: view)
    } else {
      sourceFrame = CGRect(x: Spacing.md, y: Spacing.huge, width: 280, height: 88)
    }

    onOpenMessageActions?(message, sourceFrame)
  }
}

private final class FriendsChatTimelineCell: UICollectionViewCell {
  static let reuseIdentifier = "FriendsChatTimelineCell"

  func configure<Content: View>(@ViewBuilder content: () -> Content) {
    contentConfiguration = UIHostingConfiguration {
      content()
    }
    .margins(.all, 0)
  }

  override func preferredLayoutAttributesFitting(
    _ layoutAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutAttributes {
    let fittedAttributes = super.preferredLayoutAttributesFitting(layoutAttributes)
    let targetWidth = layoutAttributes.size.width

    guard targetWidth > 0 else { return fittedAttributes }

    setNeedsLayout()
    layoutIfNeeded()

    let targetSize = CGSize(
      width: targetWidth,
      height: UIView.layoutFittingCompressedSize.height
    )
    let fittedSize = contentView.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )

    fittedAttributes.size = CGSize(
      width: targetWidth,
      height: ceil(fittedSize.height)
    )
    return fittedAttributes
  }
}

private struct FriendsChatTypingRowContent: View {
  var body: some View {
    ChatMessageRow(isCurrentUser: false, minSpacer: 48, spacing: Spacing.xxs) {
      TypingIndicatorView()
    }
    .padding(.top, Spacing.micro)
    .padding(.bottom, Spacing.xxxs)
  }
}
