import SwiftUI
import UIKit

struct FriendsThreadSurfaceCallbacks {
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
  let onComposerDraftChanged: (String) -> Void
  let onComposerCancelReply: () -> Void
  let onComposerSend: (String, ImageAttachment?) async -> Bool
  let onBottomAccessoryInsetChanged: (CGFloat) -> Void
}

struct FriendsThreadSurfaceView: UIViewControllerRepresentable {
  let timelineConfiguration: FriendsChatTimelineConfiguration
  let composerConfiguration: FriendsThreadComposerConfiguration
  let callbacks: FriendsThreadSurfaceCallbacks

  func makeUIViewController(context: Context) -> FriendsThreadSurfaceViewController {
    let controller = FriendsThreadSurfaceViewController()
    controller.loadViewIfNeeded()
    controller.apply(
      timelineConfiguration: timelineConfiguration,
      composerConfiguration: composerConfiguration,
      callbacks: callbacks
    )
    return controller
  }

  func updateUIViewController(
    _ uiViewController: FriendsThreadSurfaceViewController,
    context: Context
  ) {
    uiViewController.apply(
      timelineConfiguration: timelineConfiguration,
      composerConfiguration: composerConfiguration,
      callbacks: callbacks
    )
  }
}

@MainActor
final class FriendsThreadSurfaceViewController: UIViewController {
  private let timelineController = FriendsChatTimelineViewController()
  private let composerBridge = FriendsThreadComposerBridge()
  private lazy var composerController = UIHostingController(
    rootView: FriendsThreadComposerHostedView(bridge: composerBridge)
  )
  private lazy var composerHeightConstraint = composerController.view.heightAnchor.constraint(
    equalToConstant: 0)

  private var callbacks: FriendsThreadSurfaceCallbacks?
  private var composerConfiguration = FriendsThreadComposerConfiguration(
    draftText: "",
    replyPreview: nil,
    isThreadReadOnly: false,
    sendErrorMessage: nil,
    placeholder: ""
  )

  private var lastReportedComposerHeight: CGFloat = 0
  private var lastAppliedTimelineBottomInset: CGFloat = 0
  private var baseTimelineBottomInset: CGFloat = 0
  private var latestMeasuredComposerHeight: CGFloat = 0

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .clear
    view.keyboardLayoutGuide.followsUndockedKeyboard = true
    if #available(iOS 16.0, *) {
      composerController.sizingOptions = [.intrinsicContentSize]
    }

    addChild(timelineController)
    timelineController.view.translatesAutoresizingMaskIntoConstraints = false
    timelineController.view.backgroundColor = .clear
    view.addSubview(timelineController.view)
    timelineController.didMove(toParent: self)

    addChild(composerController)
    composerController.view.translatesAutoresizingMaskIntoConstraints = false
    composerController.view.backgroundColor = .clear
    composerController.view.setContentHuggingPriority(.required, for: .vertical)
    composerController.view.setContentCompressionResistancePriority(.required, for: .vertical)
    view.addSubview(composerController.view)
    composerController.didMove(toParent: self)
    composerHeightConstraint.isActive = true

    composerBridge.onHeightChanged = { [weak self] height in
      self?.handleComposerPreferredHeightChange(height: height)
    }

    NSLayoutConstraint.activate([
      timelineController.view.topAnchor.constraint(equalTo: view.topAnchor),
      timelineController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      timelineController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      timelineController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      composerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      composerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      composerController.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let didUpdateComposerHeight = updateComposerHeightIfNeeded()
    guard !didUpdateComposerHeight else { return }
    updateTimelineBottomInsetIfNeeded()
    reportBottomAccessoryInsetIfNeeded()
  }

  func apply(
    timelineConfiguration: FriendsChatTimelineConfiguration,
    composerConfiguration: FriendsThreadComposerConfiguration,
    callbacks: FriendsThreadSurfaceCallbacks
  ) {
    loadViewIfNeeded()

    self.callbacks = callbacks
    self.composerConfiguration = composerConfiguration
    baseTimelineBottomInset = timelineConfiguration.bottomContentInset
    composerBridge.onDraftChanged = callbacks.onComposerDraftChanged
    composerBridge.onCancelReply = callbacks.onComposerCancelReply
    composerBridge.onSend = callbacks.onComposerSend

    timelineController.onBackgroundTap = { [weak self] in
      self?.view.endEditing(true)
      callbacks.onBackgroundTap()
    }
    timelineController.onPinnedToBottomChanged = callbacks.onPinnedToBottomChanged
    timelineController.onReachedTopMessage = callbacks.onReachedTopMessage
    timelineController.onReply = callbacks.onReply
    timelineController.onRetryMessage = callbacks.onRetryMessage
    timelineController.onReportMessage = callbacks.onReportMessage
    timelineController.onToggleReaction = callbacks.onToggleReaction
    timelineController.onOpenMessageActions = callbacks.onOpenMessageActions
    timelineController.onTapQuotedMessage = callbacks.onTapQuotedMessage

    refreshComposer()
    seedComposerHeightIfPossible()

    timelineController.apply(
      config: timelineConfiguration.withBottomContentInset(
        resolvedTimelineBottomInset(baseBottomInset: timelineConfiguration.bottomContentInset)
      ),
      onConsumeRestoreScrollTarget: callbacks.onConsumeRestoreScrollTarget,
      onConsumeReplyScrollTarget: callbacks.onConsumeReplyScrollTarget
    )
  }

  private func refreshComposer() {
    composerBridge.apply(configuration: composerConfiguration)
    view.setNeedsLayout()
  }

  private func seedComposerHeightIfPossible() {
    let targetWidth = view.bounds.width
    guard targetWidth > 0 else { return }
    composerHeightConstraint.constant = preferredComposerHeight(for: targetWidth)
  }

  @discardableResult
  private func updateComposerHeightIfNeeded(layoutImmediately: Bool = false) -> Bool {
    let targetWidth =
      composerController.view.bounds.width > 0
      ? composerController.view.bounds.width : view.bounds.width
    guard targetWidth > 0 else { return false }

    let measuredHeight = preferredComposerHeight(for: targetWidth)
    guard abs(measuredHeight - composerHeightConstraint.constant) > 0.5 else { return false }

    composerHeightConstraint.constant = measuredHeight
    if layoutImmediately, view.window != nil {
      view.layoutIfNeeded()
    } else {
      view.setNeedsLayout()
    }
    return true
  }

  private func handleComposerPreferredHeightChange(height: CGFloat) {
    latestMeasuredComposerHeight = height
    let didUpdateComposerHeight = updateComposerHeightIfNeeded(layoutImmediately: true)
    guard didUpdateComposerHeight else { return }
    updateTimelineBottomInsetIfNeeded()
    reportBottomAccessoryInsetIfNeeded()
  }

  private func preferredComposerHeight(for width: CGFloat) -> CGFloat {
    if latestMeasuredComposerHeight > 0 {
      return latestMeasuredComposerHeight
    }

    let fittedSize = composerController.sizeThatFits(
      in: CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
    )
    if fittedSize.height > 0 {
      return fittedSize.height
    }

    let targetSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
    let resolvedSize = composerController.view.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    return resolvedSize.height
  }

  private func updateTimelineBottomInsetIfNeeded() {
    let bottomInset = resolvedTimelineBottomInset(baseBottomInset: baseTimelineBottomInset)
    guard abs(bottomInset - lastAppliedTimelineBottomInset) > 0.5 else { return }

    lastAppliedTimelineBottomInset = bottomInset
    timelineController.setBottomContentInset(bottomInset)
  }

  private func reportBottomAccessoryInsetIfNeeded() {
    let bottomAccessoryInset = currentBottomAccessoryInset
    guard abs(bottomAccessoryInset - lastReportedComposerHeight) > 0.5 else { return }
    lastReportedComposerHeight = bottomAccessoryInset
    callbacks?.onBottomAccessoryInsetChanged(bottomAccessoryInset)
  }

  private var currentBottomAccessoryInset: CGFloat {
    guard composerController.view.frame.height > 0 else { return composerHeightConstraint.constant }
    return max(0, view.bounds.maxY - composerController.view.frame.minY)
  }

  private func resolvedTimelineBottomInset(baseBottomInset: CGFloat) -> CGFloat {
    baseBottomInset + currentBottomAccessoryInset
  }
}
