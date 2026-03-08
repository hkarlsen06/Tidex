import ChatLayout
import SwiftUI
import UIKit

struct FriendsChatTimelineView: UIViewControllerRepresentable {
  let messages: [FriendMessage]
  let quotedMessagesById: [String: FriendMessage]
  let viewerUserId: String
  let currentUserDisplayName: String
  let counterpartDisplayName: String
  let highlightedMessageId: String?
  let bottomContentInset: CGFloat
  let scrollToBottomTrigger: Int
  let restoreScrollTargetMessageId: String?
  let replyScrollTargetMessageId: String?
  let onPinnedToBottomChanged: (Bool) -> Void
  let onReachedTopMessage: (String) -> Void
  let onReply: (FriendMessage) -> Void
  let onReportMessage: (String) -> Void
  let onTapQuotedMessage: (FriendMessage) -> Void
  let onConsumeRestoreScrollTarget: () -> Void
  let onConsumeReplyScrollTarget: (String) -> Void

  func makeUIViewController(context: Context) -> FriendsChatTimelineViewController {
    let controller = FriendsChatTimelineViewController()
    controller.onPinnedToBottomChanged = onPinnedToBottomChanged
    controller.onReachedTopMessage = onReachedTopMessage
    controller.onReply = onReply
    controller.onReportMessage = onReportMessage
    controller.onTapQuotedMessage = onTapQuotedMessage
    return controller
  }

  func updateUIViewController(
    _ uiViewController: FriendsChatTimelineViewController,
    context: Context
  ) {
    uiViewController.onPinnedToBottomChanged = onPinnedToBottomChanged
    uiViewController.onReachedTopMessage = onReachedTopMessage
    uiViewController.onReply = onReply
    uiViewController.onReportMessage = onReportMessage
    uiViewController.onTapQuotedMessage = onTapQuotedMessage
    uiViewController.apply(
      config: FriendsChatTimelineConfiguration(
        messages: messages,
        quotedMessagesById: quotedMessagesById,
        viewerUserId: viewerUserId,
        currentUserDisplayName: currentUserDisplayName,
        counterpartDisplayName: counterpartDisplayName,
        highlightedMessageId: highlightedMessageId,
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
  let currentUserDisplayName: String
  let counterpartDisplayName: String
  let highlightedMessageId: String?
  let bottomContentInset: CGFloat
  let scrollToBottomTrigger: Int
  let restoreScrollTargetMessageId: String?
  let replyScrollTargetMessageId: String?
}

@MainActor
final class FriendsChatTimelineViewController: UIViewController {
  var onPinnedToBottomChanged: ((Bool) -> Void)?
  var onReachedTopMessage: ((String) -> Void)?
  var onReply: ((FriendMessage) -> Void)?
  var onReportMessage: ((String) -> Void)?
  var onTapQuotedMessage: ((FriendMessage) -> Void)?

  private let chatLayout = CollectionViewChatLayout()
  private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: chatLayout)

  private var messages: [FriendMessage] = []
  private var quotedMessagesById: [String: FriendMessage] = [:]
  private var viewerUserId = ""
  private var currentUserDisplayName = ""
  private var counterpartDisplayName = ""
  private var highlightedMessageId: String?
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
    case prepend(
      insertedIndexPaths: [IndexPath],
      reloadedIndexPaths: [IndexPath],
      preservedSnapshot: ChatLayoutPositionSnapshot?
    )
    case append(insertedIndexPaths: [IndexPath], reloadedIndexPaths: [IndexPath])
    case reload(indexPaths: [IndexPath])
  }

  private struct RenderState {
    let messages: [FriendMessage]
    let quotedMessagesById: [String: FriendMessage]
    let highlightedMessageId: String?
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

    view.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  func apply(
    config: FriendsChatTimelineConfiguration,
    onConsumeRestoreScrollTarget: @escaping () -> Void,
    onConsumeReplyScrollTarget: @escaping (String) -> Void
  ) {
    let previousState = RenderState(
      messages: self.messages,
      quotedMessagesById: self.quotedMessagesById,
      highlightedMessageId: self.highlightedMessageId
    )
    let nextState = RenderState(
      messages: config.messages,
      quotedMessagesById: config.quotedMessagesById,
      highlightedMessageId: config.highlightedMessageId
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
    self.currentUserDisplayName = config.currentUserDisplayName
    self.counterpartDisplayName = config.counterpartDisplayName
    self.highlightedMessageId = config.highlightedMessageId
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

    guard !previousMessages.isEmpty else {
      return .fullReload(preservedSnapshot: nil)
    }

    guard !newMessages.isEmpty else {
      return .fullReload(preservedSnapshot: nil)
    }

    let previousIds = previousMessages.map(\.id)
    let newIds = newMessages.map(\.id)
    let reloadedIndexPaths = reloadedIndexPaths(previousState: previousState, nextState: nextState)

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

    case .prepend(let insertedIndexPaths, let reloadedIndexPaths, let preservedSnapshot):
      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates {
          collectionView.insertItems(at: insertedIndexPaths)
          reloadItems(at: reloadedIndexPaths)
        } completion: { [weak self] _ in
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
      } completion: { _ in
        completion()
      }

    case .reload(let indexPaths):
      guard !indexPaths.isEmpty else {
        completion()
        return
      }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates {
          reloadItems(at: indexPaths)
        } completion: { _ in
          completion()
        }
      }
    }
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
    messages.count
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
    let showsTimestamp: Bool
    if let nextMessage {
      showsTimestamp = !Calendar.current.isDate(
        message.createdAt,
        equalTo: nextMessage.createdAt,
        toGranularity: .minute
      )
    } else {
      showsTimestamp = true
    }
    let isCurrentUser = message.senderUserId == viewerUserId
    let showsSenderLabel = previousMessage?.senderUserId != message.senderUserId
    let senderFirstName = firstName(
      for: isCurrentUser ? currentUserDisplayName : counterpartDisplayName
    )

    cell.configure {
      FriendsChatMessageRowContent(
        message: message,
        quotedPreview: quotedPreview,
        isCurrentUser: isCurrentUser,
        isHighlighted: highlightedMessageId == message.id,
        senderFirstName: senderFirstName,
        showsSenderLabel: showsSenderLabel,
        showsTimestamp: showsTimestamp,
        onReply: { [weak self] in
          self?.onReply?(message)
        },
        onReportMessage: { [weak self] in
          self?.onReportMessage?(message.id)
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
    guard messages.indices.contains(indexPath.item) else { return .fullWidth }
    let message = messages[indexPath.item]
    return message.senderUserId == viewerUserId ? .trailing : .leading
  }

  private func firstName(for displayName: String) -> String {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "User" }
    return trimmed.components(separatedBy: .whitespacesAndNewlines).first ?? trimmed
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
}
