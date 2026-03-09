import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
  private let composerView = FriendsThreadComposerView()
  private lazy var composerHeightConstraint = composerView.heightAnchor.constraint(
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
  private var pendingImageAttachment: ImageAttachment?
  private var pendingImagePreview: UIImage?
  private var imageErrorMessage: String?
  private var isProcessingImage = false
  private var isSubmitting = false

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .clear
    view.keyboardLayoutGuide.followsUndockedKeyboard = true

    addChild(timelineController)
    timelineController.view.translatesAutoresizingMaskIntoConstraints = false
    timelineController.view.backgroundColor = .clear
    view.addSubview(timelineController.view)
    timelineController.didMove(toParent: self)

    composerView.translatesAutoresizingMaskIntoConstraints = false
    composerView.delegate = self
    composerView.onPreferredHeightDidChange = { [weak self] in
      self?.handleComposerPreferredHeightChange()
    }
    composerView.setContentHuggingPriority(.required, for: .vertical)
    composerView.setContentCompressionResistancePriority(.required, for: .vertical)
    view.addSubview(composerView)
    composerHeightConstraint.isActive = true

    NSLayoutConstraint.activate([
      timelineController.view.topAnchor.constraint(equalTo: view.topAnchor),
      timelineController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      timelineController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      timelineController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      composerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      composerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      composerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
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
    composerView.apply(
      configuration: composerConfiguration,
      attachedPreviewImage: pendingImagePreview,
      imageErrorMessage: imageErrorMessage,
      isProcessingImage: isProcessingImage,
      isSubmitting: isSubmitting
    )
    view.setNeedsLayout()
  }

  private func seedComposerHeightIfPossible() {
    let targetWidth = view.bounds.width
    guard targetWidth > 0 else { return }
    composerHeightConstraint.constant = composerView.measuredHeight(for: targetWidth)
  }

  @discardableResult
  private func updateComposerHeightIfNeeded(layoutImmediately: Bool = false) -> Bool {
    let targetWidth = composerView.bounds.width > 0 ? composerView.bounds.width : view.bounds.width
    guard targetWidth > 0 else { return false }

    let measuredHeight = composerView.measuredHeight(for: targetWidth)
    guard abs(measuredHeight - composerHeightConstraint.constant) > 0.5 else { return false }

    composerHeightConstraint.constant = measuredHeight
    if layoutImmediately, view.window != nil {
      view.layoutIfNeeded()
    } else {
      view.setNeedsLayout()
    }
    return true
  }

  private func handleComposerPreferredHeightChange() {
    let didUpdateComposerHeight = updateComposerHeightIfNeeded(layoutImmediately: true)
    guard didUpdateComposerHeight else { return }
    updateTimelineBottomInsetIfNeeded()
    reportBottomAccessoryInsetIfNeeded()
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
    guard composerView.frame.height > 0 else { return composerHeightConstraint.constant }
    return max(0, view.bounds.maxY - composerView.frame.minY)
  }

  private func resolvedTimelineBottomInset(baseBottomInset: CGFloat) -> CGFloat {
    baseBottomInset + currentBottomAccessoryInset
  }

  private func presentAttachmentSourcePicker(from sourceView: UIView) {
    guard presentedViewController == nil else { return }

    let alertController = UIAlertController(
      title: String(localized: "profile.personalInfo.chooseImageSource"),
      message: nil,
      preferredStyle: .actionSheet
    )

    if UIImagePickerController.isSourceTypeAvailable(.camera) {
      alertController.addAction(
        UIAlertAction(
          title: String(localized: "profile.personalInfo.takePhoto"),
          style: .default
        ) { [weak self] _ in
          self?.presentCamera()
        }
      )
    }

    alertController.addAction(
      UIAlertAction(
        title: String(localized: "profile.personalInfo.chooseFromLibrary"),
        style: .default
      ) { [weak self] _ in
        self?.presentPhotoLibrary()
      }
    )

    alertController.addAction(
      UIAlertAction(title: String(localized: .commonCancel), style: .cancel)
    )

    if let popoverPresentationController = alertController.popoverPresentationController {
      popoverPresentationController.sourceView = sourceView
      popoverPresentationController.sourceRect = sourceView.bounds
    }

    present(alertController, animated: true)
  }

  private func presentPhotoLibrary() {
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 1

    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self
    present(picker, animated: true)
  }

  private func presentCamera() {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = self
    present(picker, animated: true)
  }

  private func clearPendingAttachment() {
    pendingImageAttachment = nil
    pendingImagePreview = nil
    imageErrorMessage = nil
    refreshComposer()
  }

  private func processPickedImageData(_ data: Data) {
    isProcessingImage = true
    imageErrorMessage = nil
    refreshComposer()

    Task {
      let compressed = await Task.detached(priority: .userInitiated) {
        ImageCompressor.compress(data)
      }.value

      await MainActor.run {
        self.isProcessingImage = false

        guard let compressed, let previewImage = UIImage(data: compressed.data) else {
          self.imageErrorMessage = String(localized: .wageyImageError)
          Haptics.play(.error)
          self.refreshComposer()
          return
        }

        self.pendingImageAttachment = ImageAttachment(
          data: compressed.data,
          mediaType: compressed.mediaType
        )
        self.pendingImagePreview = previewImage
        self.imageErrorMessage = nil
        Haptics.play(.success)
        self.refreshComposer()
      }
    }
  }

  private func processCapturedImage(_ image: UIImage) {
    isProcessingImage = true
    imageErrorMessage = nil
    refreshComposer()

    Task {
      let compressed = await Task.detached(priority: .userInitiated) {
        ImageCompressor.compress(image)
      }.value

      await MainActor.run {
        self.isProcessingImage = false

        guard let compressed, let previewImage = UIImage(data: compressed.data) else {
          self.imageErrorMessage = String(localized: .wageyImageError)
          Haptics.play(.error)
          self.refreshComposer()
          return
        }

        self.pendingImageAttachment = ImageAttachment(
          data: compressed.data,
          mediaType: compressed.mediaType
        )
        self.pendingImagePreview = previewImage
        self.imageErrorMessage = nil
        Haptics.play(.success)
        self.refreshComposer()
      }
    }
  }
}

extension FriendsThreadSurfaceViewController: FriendsThreadComposerViewDelegate {
  func composerView(_ composerView: FriendsThreadComposerView, didChangeDraft draft: String) {
    callbacks?.onComposerDraftChanged(draft)
  }

  func composerViewDidCancelReply(_ composerView: FriendsThreadComposerView) {
    callbacks?.onComposerCancelReply()
  }

  func composerViewDidTapAttachment(_ composerView: FriendsThreadComposerView, sourceView: UIView) {
    presentAttachmentSourcePicker(from: sourceView)
  }

  func composerViewDidRemoveAttachment(_ composerView: FriendsThreadComposerView) {
    clearPendingAttachment()
    Haptics.play(.light)
  }

  func composerViewDidTapSend(_ composerView: FriendsThreadComposerView) {
    guard !isSubmitting, let callbacks else { return }

    let draft = composerView.currentDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
    Haptics.play(.medium)
    isSubmitting = true
    refreshComposer()

    Task {
      let didSend = await callbacks.onComposerSend(draft, self.pendingImageAttachment)

      await MainActor.run {
        self.isSubmitting = false
        if didSend {
          self.pendingImageAttachment = nil
          self.pendingImagePreview = nil
          self.imageErrorMessage = nil
        }
        self.refreshComposer()
      }
    }
  }
}

extension FriendsThreadSurfaceViewController: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard let itemProvider = results.first?.itemProvider else { return }

    itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
      [weak self] data, _ in
      guard let self else { return }

      guard let data else {
        Task { @MainActor in
          self.imageErrorMessage = String(localized: .wageyImageError)
          self.refreshComposer()
        }
        return
      }

      Task { @MainActor in
        self.processPickedImageData(data)
      }
    }
  }
}

extension FriendsThreadSurfaceViewController: UIImagePickerControllerDelegate,
  UINavigationControllerDelegate
{
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)

    guard let image = info[.originalImage] as? UIImage else {
      imageErrorMessage = String(localized: .wageyImageError)
      refreshComposer()
      return
    }

    processCapturedImage(image)
  }
}
