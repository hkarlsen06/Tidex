import ExyteChat
import Foundation
import SwiftUI
import UIKit

struct FriendsThreadChatViewportBridge: UIViewRepresentable {
  let messages: [ExyteChat.Message]
  let scrollRequest: FriendsThreadChatViewportScrollRequest?
  let observedPresentedMessageID: String?
  let highlightedPresentedMessageID: String?
  let onPinnedToBottomChanged: (Bool) -> Void
  let onLatestVisiblePresentedMessageIDChanged: (String?) -> Void
  let onObservedPresentedMessageVisible: (String) -> Void
  let onDidHandleScrollRequest: (FriendsThreadChatViewportScrollRequest) -> Void
  var onPulledUpPastBottom: () -> Void = {}

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  // swiftlint:disable:next explicit_acl type_contents_order
  func makeUIView(context _: Context) -> UIView {
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
        onDidHandleScrollRequest: onDidHandleScrollRequest,
        onPulledUpPastBottom: onPulledUpPastBottom
      )
    )
  }

  @MainActor
  final class Coordinator: NSObject {
    struct UpdateInput {
      let messages: [ExyteChat.Message]
      let scrollRequest: FriendsThreadChatViewportScrollRequest?
      let observedPresentedMessageID: String?
      let highlightedPresentedMessageID: String?
      let onPinnedToBottomChanged: (Bool) -> Void
      let onLatestVisiblePresentedMessageIDChanged: (String?) -> Void
      let onObservedPresentedMessageVisible: (String) -> Void
      let onDidHandleScrollRequest: (FriendsThreadChatViewportScrollRequest) -> Void
      let onPulledUpPastBottom: () -> Void
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
    private var onPulledUpPastBottom: (() -> Void)?
    private var didReportPullUpInCurrentDrag = false
    private var didStartDragAtBottomEdge: Bool?

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
      onPulledUpPastBottom = input.onPulledUpPastBottom

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
          attachIfNeeded(from: view)
          reportPinnedToBottomIfNeeded()
          attemptPendingScroll()
          reportObservedPresentedMessageVisibleIfNeeded()
        }
        return
      }

      guard tableView !== self.tableView else { return }

      self.tableView = tableView
      // Lets short threads overscroll so the pull-up-to-type gesture still works.
      tableView.alwaysBounceVertical = true
      tableView.panGestureRecognizer.addTarget(self, action: #selector(handleTablePan(_:)))
      contentOffsetObservation = tableView.observe(\.contentOffset, options: [.initial, .new]) {
        [weak self] tableView, _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          handleContentOffsetChange(for: tableView)
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
      reportPulledUpPastBottomIfNeeded(for: tableView)
      reportPinnedToBottomIfNeeded()
      reportLatestVisiblePresentedMessageIDIfNeeded()
      reportObservedPresentedMessageVisibleIfNeeded()
    }

    /// A drag that ends without moving the table sends no content offset change after it, so the
    /// flags are cleared when the next drag begins instead.
    @objc private func handleTablePan(_ recognizer: UIPanGestureRecognizer) {
      guard recognizer === tableView?.panGestureRecognizer, recognizer.state == .began else {
        return
      }
      didReportPullUpInCurrentDrag = false
      didStartDragAtBottomEdge = nil
    }

    private func reportPulledUpPastBottomIfNeeded(for tableView: UITableView) {
      // Only a drag that starts at the newest message counts, so a fast scroll
      // that overshoots the bottom doesn't open the keyboard.
      guard tableView.isTracking else {
        didReportPullUpInCurrentDrag = false
        didStartDragAtBottomEdge = nil
        return
      }
      if didStartDragAtBottomEdge == nil {
        didStartDragAtBottomEdge = FriendsThreadChatViewportResolver.isAtBottomEdge(
          contentOffsetY: tableView.contentOffset.y,
          topInset: tableView.adjustedContentInset.top
        )
      }
      guard didStartDragAtBottomEdge == true, !didReportPullUpInCurrentDrag else { return }
      guard
        FriendsThreadChatViewportResolver.isPulledUpPastBottom(
          contentOffsetY: tableView.contentOffset.y,
          topInset: tableView.adjustedContentInset.top
        )
      else { return }

      didReportPullUpInCurrentDrag = true
      DispatchQueue.main.async { [weak self] in
        self?.onPulledUpPastBottom?()
      }
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
      let animated = scrollRequest.kind == .reply && !UIAccessibility.isReduceMotionEnabled

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
      reportHandledScrollRequest(scrollRequest, animated: animated)
      reportLatestVisiblePresentedMessageIDIfNeeded()
    }

    private func reportHandledScrollRequest(
      _ scrollRequest: FriendsThreadChatViewportScrollRequest,
      animated: Bool
    ) {
      guard scrollRequest.kind != .reply else {
        settleReplyScroll(scrollRequest, animated: animated, attempt: 1, lastOffsetY: nil)
        return
      }
      DispatchQueue.main.async { [weak self] in
        self?.onDidHandleScrollRequest?(scrollRequest)
      }
    }

    private static let maxReplyScrollAttempts = 4

    /// Rows self-size as they scroll into view, and a table reload (pagination, the highlight
    /// flash) stops an animated scroll where it is. Both leave a reply jump short of its target,
    /// most often for image rows. So this waits for the offset to stop moving, scrolls again if
    /// the target is not centered, and only then reports the request as handled, which starts
    /// the highlight reload.
    private func settleReplyScroll(
      _ request: FriendsThreadChatViewportScrollRequest,
      animated: Bool,
      attempt: Int,
      lastOffsetY: CGFloat?
    ) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        guard let self, scrollRequest == request else { return }

        let finish = { [weak self] in
          DispatchQueue.main.async { [weak self] in
            guard let self, scrollRequest == request else { return }
            onDidHandleScrollRequest?(request)
          }
        }

        guard let tableView else { return finish() }
        // The user took over: stop correcting, and hold the highlight reload until the
        // scroll stops so it doesn't cut their deceleration short.
        guard !isUserInteracting(with: tableView) else {
          return settleReplyScroll(
            request, animated: animated, attempt: Self.maxReplyScrollAttempts, lastOffsetY: nil)
        }
        let offsetY = tableView.contentOffset.y
        guard offsetY == lastOffsetY else {
          return settleReplyScroll(
            request, animated: animated, attempt: attempt, lastOffsetY: offsetY)
        }
        guard
          attempt < Self.maxReplyScrollAttempts,
          let indexPath = offCenterRow(for: request, in: tableView)
        else { return finish() }

        if animated {
          tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
        } else {
          UIView.performWithoutAnimation {
            tableView.scrollToRow(at: indexPath, at: .middle, animated: false)
            tableView.layoutIfNeeded()
          }
        }
        settleReplyScroll(request, animated: animated, attempt: attempt + 1, lastOffsetY: nil)
      }
    }

    /// Returns the request's row when it sits more than a point away from where `.middle`
    /// would put it, clamped to the scrollable range.
    private func offCenterRow(
      for request: FriendsThreadChatViewportScrollRequest,
      in tableView: UITableView
    ) -> IndexPath? {
      guard
        let layoutSnapshot = resolvedLayoutSnapshot(),
        let indexPath = FriendsThreadChatViewportResolver.indexPath(
          for: request.presentedMessageID,
          in: layoutSnapshot
        ),
        tableView.numberOfSections > indexPath.section,
        tableView.numberOfRows(inSection: indexPath.section) > indexPath.row
      else { return nil }

      let rowRect = tableView.rectForRow(at: indexPath)
      let minOffsetY = -tableView.adjustedContentInset.top
      let maxOffsetY = max(
        minOffsetY,
        tableView.contentSize.height - tableView.bounds.height
          + tableView.adjustedContentInset.bottom
      )
      let targetOffsetY = min(
        max(rowRect.midY - tableView.bounds.height / 2, minOffsetY), maxOffsetY)
      return abs(targetOffsetY - tableView.contentOffset.y) > 1 ? indexPath : nil
    }

    private func isUserInteracting(with tableView: UITableView) -> Bool {
      tableView.isTracking || tableView.isDragging || tableView.isDecelerating
    }

    private func scheduleDeferredScroll(_ scrollRequest: FriendsThreadChatViewportScrollRequest) {
      guard deferredScrollRequest != scrollRequest else { return }
      deferredScrollRequest = scrollRequest

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self else { return }
        // swiftlint:disable:next conditional_returns_on_newline
        guard deferredScrollRequest == scrollRequest else { return }
        deferredScrollRequest = nil
        attemptPendingScroll()
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

      // swiftlint:disable:next explicit_type_interface
      let candidateIndexPaths = Set([previousIndexPath, currentIndexPath].compactMap(\.self))
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
      guard !messages.isEmpty else {
        return nil
      }

      let rebuiltLayoutSnapshot = FriendsThreadChatViewportResolver.layoutSnapshot(
        messages: messages)
      layoutSnapshot = rebuiltLayoutSnapshot
      return rebuiltLayoutSnapshot
    }

    private func findChatTableView(from view: UIView) -> UITableView? {
      let searchRoot = view.window ?? view.nearestRootView()
      let tableViews = searchRoot.descendantViews(ofType: UITableView.self)

      return tableViews.first(where: { candidate in
        guard let delegate = candidate.delegate else {
          return false
        }
        return String(reflecting: type(of: delegate)).contains("UIList")
      }) ?? tableViews.first
    }
  }
}

extension UIView {
  func nearestRootView() -> UIView {
    var currentView = self

    while let superview = currentView.superview {
      currentView = superview
    }

    return currentView
  }

  func descendantViews<T: UIView>(ofType type: T.Type) -> [T] {
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
