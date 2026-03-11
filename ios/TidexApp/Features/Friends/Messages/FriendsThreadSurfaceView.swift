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
  let onOpenMessageActions: (FriendMessage, CGRect?) -> Void
  let onTapQuotedMessage: (FriendMessage) -> Void
  let onConsumeRestoreScrollTarget: () -> Void
  let onConsumeReplyScrollTarget: (String) -> Void
  let onComposerDraftChanged: (String) -> Void
  let onComposerAttachmentChanged: (FriendsComposerAttachmentDraft?) -> Void
  let onComposerPrepareShiftSnapshot:
    (ShiftWithComputations) async -> FriendsComposerAttachmentDraft?
  let onComposerCancelReply: () -> Void
  let onComposerSend: (String) async -> Bool
  let onComposerAttachmentDrawerOpenChanged: (Bool) -> Void
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

struct FriendsThreadComposerKeyboardLayout {
  static func shouldAttachComposerToKeyboard(
    keyboardTop: CGFloat,
    viewBottom: CGFloat,
    bottomSafeAreaInset: CGFloat
  ) -> Bool {
    let keyboardOverlap = max(0, viewBottom - keyboardTop)
    return keyboardOverlap > (bottomSafeAreaInset + 0.5)
  }
}

@MainActor
final class FriendsThreadSurfaceViewController: UIViewController {
  private let timelineController = FriendsChatTimelineViewController()
  private let composerBridge = FriendsThreadComposerBridge()
  private lazy var composerController = UIHostingController(
    rootView: FriendsThreadComposerHostedView(bridge: composerBridge)
  )
  private lazy var composerBottomToSafeAreaConstraint = composerController.view.bottomAnchor
    .constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
  private lazy var composerBottomToKeyboardConstraint = composerController.view.bottomAnchor
    .constraint(equalTo: view.keyboardLayoutGuide.topAnchor)

  private var callbacks: FriendsThreadSurfaceCallbacks?
  private var composerConfiguration = FriendsThreadComposerConfiguration(
    draftText: "",
    replyPreview: nil,
    stagedAttachment: nil,
    isThreadReadOnly: false,
    sendErrorMessage: nil,
    placeholder: "",
    canSendShiftSnapshots: false
  )

  private var lastReportedComposerHeight: CGFloat = 0
  private var lastAppliedTimelineBottomInset: CGFloat = 0
  private var baseTimelineBottomInset: CGFloat = 0
  private var latestMeasuredComposerHeight: CGFloat = 0
  private var keyboardObservers: [NSObjectProtocol] = []

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
    composerBottomToSafeAreaConstraint.isActive = true
    composerBottomToKeyboardConstraint.isActive = false

    composerBridge.onHeightChanged = { [weak self] height in
      self?.handleComposerPreferredHeightChange(height: height)
    }

    startObservingKeyboardTransitions()

    NSLayoutConstraint.activate([
      timelineController.view.topAnchor.constraint(equalTo: view.topAnchor),
      timelineController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      timelineController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      timelineController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      composerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      composerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      composerController.view.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    synchronizeComposerLayoutForCurrentKeyboardState()
    DispatchQueue.main.async { [weak self] in
      self?.synchronizeComposerLayoutForCurrentKeyboardState()
    }
  }

  deinit {
    let notificationCenter = NotificationCenter.default
    keyboardObservers.forEach { notificationCenter.removeObserver($0) }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateComposerBottomConstraintForCurrentKeyboardState()
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
    composerBridge.onStagedAttachmentChanged = callbacks.onComposerAttachmentChanged
    composerBridge.onPrepareShiftSnapshotAttachment = callbacks.onComposerPrepareShiftSnapshot
    composerBridge.onCancelReply = callbacks.onComposerCancelReply
    composerBridge.onSend = callbacks.onComposerSend
    composerBridge.onAttachmentDrawerOpenChanged = callbacks.onComposerAttachmentDrawerOpenChanged

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
    updateComposerBottomConstraintForCurrentKeyboardState()
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
    composerController.view.invalidateIntrinsicContentSize()
    view.setNeedsLayout()
  }

  private func seedComposerHeightIfPossible() {
    let targetWidth = composerMeasurementWidth
    guard targetWidth > 0 else { return }

    let measuredHeight = measuredComposerHeight(for: targetWidth)
    guard measuredHeight > 0 else { return }
    latestMeasuredComposerHeight = measuredHeight
  }

  private func handleComposerPreferredHeightChange(height: CGFloat) {
    latestMeasuredComposerHeight = height
    composerController.view.invalidateIntrinsicContentSize()
    view.setNeedsLayout()
    if view.window != nil {
      updateComposerBottomConstraintForCurrentKeyboardState()
      view.layoutIfNeeded()
    }
    updateTimelineBottomInsetIfNeeded()
    reportBottomAccessoryInsetIfNeeded()
  }

  private var composerMeasurementWidth: CGFloat {
    if composerController.view.bounds.width > 0 {
      return composerController.view.bounds.width
    }
    return view.bounds.width
  }

  private func measuredComposerHeight(for width: CGFloat) -> CGFloat {
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
    return max(0, resolvedSize.height)
  }

  private func startObservingKeyboardTransitions() {
    let notificationCenter = NotificationCenter.default
    let keyboardNotifications: [NSNotification.Name] = [
      UIResponder.keyboardWillChangeFrameNotification,
      UIResponder.keyboardDidChangeFrameNotification,
      UIResponder.keyboardWillHideNotification,
      UIResponder.keyboardDidHideNotification,
    ]

    keyboardObservers = keyboardNotifications.map { name in
      notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.synchronizeComposerLayoutForCurrentKeyboardState()
        }
      }
    }
  }

  private func synchronizeComposerLayoutForCurrentKeyboardState() {
    guard isViewLoaded else { return }

    view.setNeedsLayout()
    if view.window != nil {
      view.layoutIfNeeded()
    }

    updateComposerBottomConstraintForCurrentKeyboardState()

    if view.window != nil {
      view.layoutIfNeeded()
    }

    updateTimelineBottomInsetIfNeeded()
    reportBottomAccessoryInsetIfNeeded()
  }

  private func updateComposerBottomConstraintForCurrentKeyboardState() {
    let keyboardTop = view.keyboardLayoutGuide.layoutFrame.minY
    let isKeyboardPresented =
      FriendsThreadComposerKeyboardLayout
      .shouldAttachComposerToKeyboard(
        keyboardTop: keyboardTop,
        viewBottom: view.bounds.maxY,
        bottomSafeAreaInset: view.safeAreaInsets.bottom
      )

    if isKeyboardPresented {
      guard
        !composerBottomToKeyboardConstraint.isActive || composerBottomToSafeAreaConstraint.isActive
      else { return }
      composerBottomToSafeAreaConstraint.isActive = false
      composerBottomToKeyboardConstraint.isActive = true
      return
    }

    guard
      !composerBottomToSafeAreaConstraint.isActive || composerBottomToKeyboardConstraint.isActive
    else { return }
    composerBottomToKeyboardConstraint.isActive = false
    composerBottomToSafeAreaConstraint.isActive = true
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
    guard composerController.view.frame.height > 0 else {
      return max(0, latestMeasuredComposerHeight + view.safeAreaInsets.bottom)
    }
    return max(0, view.bounds.maxY - composerController.view.frame.minY)
  }

  private func resolvedTimelineBottomInset(baseBottomInset: CGFloat) -> CGFloat {
    baseBottomInset + currentBottomAccessoryInset
  }
}
