import SwiftUI
import UIKit

struct FriendsThreadComposerConfiguration: Equatable {
  let draftText: String
  let replyPreview: FriendsChatReplyPreviewModel?
  let isThreadReadOnly: Bool
  let sendErrorMessage: String?
  let placeholder: String
}

enum FriendsThreadComposerLogic {
  static let attachmentCollapseCharacterThreshold = 32

  static func canSend(
    draftText: String,
    hasImage: Bool,
    isThreadReadOnly: Bool,
    isSubmitting: Bool,
    isProcessingImage: Bool
  ) -> Bool {
    let hasText = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return (hasText || hasImage) && !isThreadReadOnly && !isSubmitting && !isProcessingImage
  }

  static func shouldHideAttachmentButton(
    draftText: String,
    isFocused: Bool,
    hasImage: Bool
  ) -> Bool {
    guard isFocused, !hasImage else { return false }
    let draftLength = draftText.trimmingCharacters(in: .whitespacesAndNewlines).count
    return draftLength >= attachmentCollapseCharacterThreshold || draftText.contains("\n")
  }
}

@MainActor
protocol FriendsThreadComposerViewDelegate: AnyObject {
  func composerView(_ composerView: FriendsThreadComposerView, didChangeDraft draft: String)
  func composerViewDidCancelReply(_ composerView: FriendsThreadComposerView)
  func composerViewDidTapAttachment(_ composerView: FriendsThreadComposerView, sourceView: UIView)
  func composerViewDidRemoveAttachment(_ composerView: FriendsThreadComposerView)
  func composerViewDidTapSend(_ composerView: FriendsThreadComposerView)
}

@MainActor
final class FriendsThreadComposerView: UIView {
  private enum Layout {
    static let composerControlHeight: CGFloat = 56
    static let attachmentButtonSize: CGFloat = 50
    static let sendButtonSize: CGFloat = 38
    static let previewSize: CGFloat = 80
    static let maxVisibleLines: CGFloat = 7
    static let composerCornerRadius: CGFloat = 24
    static let previewCornerRadius: CGFloat = 10
  }

  weak var delegate: FriendsThreadComposerViewDelegate?
  var onPreferredHeightDidChange: (() -> Void)?

  private let rootStack = UIStackView()
  private let replyBannerView = FriendsThreadReplyBannerUIKitView()
  private let readOnlyRow = FriendsThreadComposerStatusRowView()
  private let sendErrorRow = FriendsThreadComposerStatusRowView()
  private let imageErrorRow = FriendsThreadComposerStatusRowView()
  private let attachmentPreviewView = FriendsThreadAttachmentPreviewView()
  private lazy var replyBannerContainer = wrapped(replyBannerView, horizontalInset: Spacing.md)
  private lazy var readOnlyRowContainer = wrapped(readOnlyRow, horizontalInset: Spacing.md)
  private lazy var sendErrorRowContainer = wrapped(sendErrorRow, horizontalInset: Spacing.md)
  private lazy var imageErrorRowContainer = wrapped(imageErrorRow, horizontalInset: Spacing.md)
  private lazy var attachmentPreviewContainer = wrapped(
    attachmentPreviewView, horizontalInset: Spacing.md)
  private let composerContainer = UIView()
  private let composerRowStack = UIStackView()
  private let textFieldContainerView = UIView()
  private let attachmentButton = UIButton(type: .system)
  private let textView = UITextView()
  private let placeholderLabel = UILabel()
  private let sendButton = UIButton(type: .system)
  private let sendActivityIndicator = UIActivityIndicatorView(style: .medium)
  private let textViewHeightConstraint: NSLayoutConstraint
  private let attachmentButtonWidthConstraint: NSLayoutConstraint

  private var currentConfiguration = FriendsThreadComposerConfiguration(
    draftText: "",
    replyPreview: nil,
    isThreadReadOnly: false,
    sendErrorMessage: nil,
    placeholder: ""
  )
  private var isProcessingImage = false
  private var isSubmitting = false
  private var attachedPreviewImage: UIImage?
  private var imageErrorMessage: String?
  private var isComposerFocused = false
  private var suppressDraftCallback = false

  override init(frame: CGRect) {
    textViewHeightConstraint = textView.heightAnchor.constraint(
      equalToConstant: Layout.composerControlHeight - (Spacing.sm * 2))
    attachmentButtonWidthConstraint = attachmentButton.widthAnchor.constraint(
      equalToConstant: Layout.attachmentButtonSize)
    super.init(frame: frame)
    configureViews()
    refreshVisualState()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func apply(
    configuration: FriendsThreadComposerConfiguration,
    attachedPreviewImage: UIImage?,
    imageErrorMessage: String?,
    isProcessingImage: Bool,
    isSubmitting: Bool
  ) {
    currentConfiguration = configuration
    self.attachedPreviewImage = attachedPreviewImage
    self.imageErrorMessage = imageErrorMessage
    self.isProcessingImage = isProcessingImage
    self.isSubmitting = isSubmitting

    updateDraftTextIfNeeded(configuration.draftText)
    placeholderLabel.text = configuration.placeholder
    replyBannerContainer.isHidden = configuration.replyPreview == nil
    if let replyPreview = configuration.replyPreview {
      replyBannerView.apply(preview: replyPreview)
    }

    readOnlyRowContainer.isHidden = !configuration.isThreadReadOnly
    if configuration.isThreadReadOnly {
      readOnlyRow.apply(
        iconSystemName: "hand.raised.fill",
        iconTintColor: Self.color(named: "TidexWarning", fallback: .systemOrange),
        message: String(localized: .friendsChatBlockedReadOnly),
        messageColor: Self.color(named: "TidexTextSecondary", fallback: .secondaryLabel),
        trailingButtonImage: nil
      )
    }

    sendErrorRowContainer.isHidden = configuration.sendErrorMessage == nil
    if let sendErrorMessage = configuration.sendErrorMessage {
      sendErrorRow.apply(
        iconSystemName: nil,
        iconTintColor: nil,
        message: sendErrorMessage,
        messageColor: Self.color(named: "TidexError", fallback: .systemRed),
        trailingButtonImage: nil
      )
    }

    imageErrorRowContainer.isHidden = imageErrorMessage == nil
    if let imageErrorMessage {
      imageErrorRow.apply(
        iconSystemName: "exclamationmark.triangle.fill",
        iconTintColor: Self.color(named: "TidexWarning", fallback: .systemOrange),
        message: imageErrorMessage,
        messageColor: Self.color(named: "TidexTextPrimary", fallback: .label),
        trailingButtonImage: UIImage(systemName: "xmark")
      ) { [weak self] in
        self?.imageErrorMessage = nil
        self?.refreshVisualState()
      }
    }

    attachmentPreviewContainer.isHidden = attachedPreviewImage == nil
    attachmentPreviewView.apply(image: attachedPreviewImage)

    refreshVisualState()
  }

  var currentDraftText: String {
    textView.text ?? ""
  }

  func measuredHeight(for width: CGFloat) -> CGFloat {
    let fittingSize = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
    let resolvedSize = rootStack.systemLayoutSizeFitting(
      fittingSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    return resolvedSize.height
  }

  private func configureViews() {
    backgroundColor = Self.color(named: "TidexBackground", fallback: .systemBackground)

    rootStack.axis = .vertical
    rootStack.spacing = Spacing.xs
    rootStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(rootStack)

    NSLayoutConstraint.activate([
      rootStack.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.xs),
      rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
      rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
      rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    replyBannerView.translatesAutoresizingMaskIntoConstraints = false
    replyBannerView.onCancel = { [weak self] in
      guard let self else { return }
      delegate?.composerViewDidCancelReply(self)
    }
    rootStack.addArrangedSubview(replyBannerContainer)

    readOnlyRow.translatesAutoresizingMaskIntoConstraints = false
    rootStack.addArrangedSubview(readOnlyRowContainer)

    sendErrorRow.translatesAutoresizingMaskIntoConstraints = false
    rootStack.addArrangedSubview(sendErrorRowContainer)

    imageErrorRow.translatesAutoresizingMaskIntoConstraints = false
    rootStack.addArrangedSubview(imageErrorRowContainer)

    attachmentPreviewView.translatesAutoresizingMaskIntoConstraints = false
    attachmentPreviewView.onRemove = { [weak self] in
      guard let self else { return }
      delegate?.composerViewDidRemoveAttachment(self)
    }
    rootStack.addArrangedSubview(attachmentPreviewContainer)

    composerContainer.translatesAutoresizingMaskIntoConstraints = false
    composerContainer.backgroundColor = Self.color(
      named: "TidexBackground", fallback: .systemBackground)
    rootStack.addArrangedSubview(composerContainer)

    composerRowStack.axis = .horizontal
    composerRowStack.alignment = .bottom
    composerRowStack.spacing = Spacing.xsm
    composerRowStack.translatesAutoresizingMaskIntoConstraints = false
    composerContainer.addSubview(composerRowStack)

    NSLayoutConstraint.activate([
      composerRowStack.topAnchor.constraint(equalTo: composerContainer.topAnchor),
      composerRowStack.leadingAnchor.constraint(
        equalTo: composerContainer.leadingAnchor, constant: MonthPickerLayout.horizontalPadding),
      composerRowStack.trailingAnchor.constraint(
        equalTo: composerContainer.trailingAnchor, constant: -MonthPickerLayout.horizontalPadding),
      composerRowStack.bottomAnchor.constraint(
        equalTo: composerContainer.bottomAnchor, constant: -MonthPickerLayout.bottomPadding),
    ])

    configureAttachmentButton()
    configureTextView()
    configureSendButton()

  }

  private func configureAttachmentButton() {
    attachmentButton.translatesAutoresizingMaskIntoConstraints = false
    attachmentButton.tintColor = Self.color(named: "TidexBlue", fallback: .systemBlue)
    attachmentButton.backgroundColor = Self.color(
      named: "TidexBackgroundSecondary", fallback: .secondarySystemBackground)
    attachmentButton.layer.cornerRadius = Layout.attachmentButtonSize / 2
    attachmentButton.setImage(UIImage(systemName: "photo.on.rectangle.angled"), for: .normal)
    attachmentButton.addTarget(self, action: #selector(handleAttachmentTap), for: .touchUpInside)
    attachmentButtonWidthConstraint.isActive = true
    attachmentButton.heightAnchor.constraint(equalToConstant: Layout.attachmentButtonSize)
      .isActive = true
    composerRowStack.addArrangedSubview(attachmentButton)
  }

  private func configureTextView() {
    textFieldContainerView.translatesAutoresizingMaskIntoConstraints = false
    textFieldContainerView.backgroundColor = Self.color(
      named: "TidexSurfacePrimary", fallback: .secondarySystemBackground)
    textFieldContainerView.layer.cornerRadius = Layout.composerCornerRadius
    textFieldContainerView.layer.borderWidth = 1

    composerRowStack.addArrangedSubview(textFieldContainerView)

    let innerRow = UIStackView()
    innerRow.axis = .horizontal
    innerRow.alignment = .bottom
    innerRow.spacing = Spacing.xs
    innerRow.translatesAutoresizingMaskIntoConstraints = false
    textFieldContainerView.addSubview(innerRow)

    NSLayoutConstraint.activate([
      innerRow.topAnchor.constraint(
        equalTo: textFieldContainerView.topAnchor, constant: Spacing.sm),
      innerRow.leadingAnchor.constraint(
        equalTo: textFieldContainerView.leadingAnchor, constant: Spacing.msm),
      innerRow.trailingAnchor.constraint(
        equalTo: textFieldContainerView.trailingAnchor, constant: -Spacing.msm),
      innerRow.bottomAnchor.constraint(
        equalTo: textFieldContainerView.bottomAnchor, constant: -Spacing.sm),
      textFieldContainerView.heightAnchor.constraint(
        greaterThanOrEqualToConstant: Layout.composerControlHeight),
    ])

    let textWrapper = UIView()
    textWrapper.translatesAutoresizingMaskIntoConstraints = false
    textWrapper.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textWrapper.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    innerRow.addArrangedSubview(textWrapper)

    textView.translatesAutoresizingMaskIntoConstraints = false
    textView.backgroundColor = .clear
    textView.isScrollEnabled = false
    textView.font = UIFont.preferredFont(forTextStyle: .body)
    textView.adjustsFontForContentSizeCategory = true
    textView.textColor = Self.color(named: "TidexTextPrimary", fallback: .label)
    textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
    textView.textContainer.lineFragmentPadding = 0
    textView.delegate = self
    textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textView.returnKeyType = .default
    textWrapper.addSubview(textView)

    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    placeholderLabel.font = UIFont.preferredFont(forTextStyle: .body)
    placeholderLabel.adjustsFontForContentSizeCategory = true
    placeholderLabel.textColor = Self.color(named: "TidexTextMuted", fallback: .secondaryLabel)
    textWrapper.addSubview(placeholderLabel)

    sendActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
    sendActivityIndicator.hidesWhenStopped = true
    sendActivityIndicator.color = Self.color(named: "TidexTextOnBrand", fallback: .white)

    sendButton.translatesAutoresizingMaskIntoConstraints = false
    sendButton.addSubview(sendActivityIndicator)
    sendButton.addTarget(self, action: #selector(handleSendTap), for: .touchUpInside)
    sendButton.setContentHuggingPriority(.required, for: .horizontal)
    sendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    innerRow.addArrangedSubview(sendButton)

    NSLayoutConstraint.activate([
      textView.topAnchor.constraint(equalTo: textWrapper.topAnchor),
      textView.leadingAnchor.constraint(equalTo: textWrapper.leadingAnchor),
      textView.trailingAnchor.constraint(equalTo: textWrapper.trailingAnchor),
      textView.bottomAnchor.constraint(equalTo: textWrapper.bottomAnchor),
      textViewHeightConstraint,

      placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
      placeholderLabel.leadingAnchor.constraint(equalTo: textWrapper.leadingAnchor),
      placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textWrapper.trailingAnchor),

      sendButton.widthAnchor.constraint(equalToConstant: Layout.sendButtonSize),
      sendButton.heightAnchor.constraint(equalToConstant: Layout.sendButtonSize),
      sendActivityIndicator.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
      sendActivityIndicator.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
    ])
  }

  private func configureSendButton() {
    sendButton.layer.cornerRadius = Layout.sendButtonSize / 2
    sendButton.clipsToBounds = true
    sendButton.setImage(
      UIImage(
        systemName: "arrow.up",
        withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
      ),
      for: .normal
    )
    sendButton.imageView?.contentMode = .center
  }

  private func wrapped(_ view: UIView, horizontalInset: CGFloat) -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: container.topAnchor),
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
  }

  private func updateDraftTextIfNeeded(_ draftText: String) {
    guard textView.text != draftText else { return }
    suppressDraftCallback = true
    textView.text = draftText
    suppressDraftCallback = false
    updatePlaceholderVisibility()
    updateTextViewHeight()
  }

  private func refreshVisualState() {
    updatePlaceholderVisibility()
    updateTextViewHeight()
    updateAttachmentVisibility()
    updateTextViewInteractivity()
    updateButtonStates()
    updateComposerChrome()
  }

  private func updatePlaceholderVisibility() {
    placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
  }

  private func updateTextViewHeight() {
    let fittingWidth = max(
      textView.bounds.width, bounds.width - (MonthPickerLayout.horizontalPadding * 2) - 120)
    let targetSize = CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
    let measuredSize = textView.sizeThatFits(targetSize)
    let lineHeight =
      textView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
    let maxHeight =
      (lineHeight * Layout.maxVisibleLines)
      + textView.textContainerInset.top
      + textView.textContainerInset.bottom
    textView.isScrollEnabled = measuredSize.height > maxHeight
    let nextHeight = min(max(measuredSize.height, 24), maxHeight)
    guard abs(textViewHeightConstraint.constant - nextHeight) > 0.5 else { return }
    textViewHeightConstraint.constant = nextHeight
    setNeedsLayout()
    superview?.setNeedsLayout()
    onPreferredHeightDidChange?()
  }

  private func updateAttachmentVisibility() {
    let shouldHide = FriendsThreadComposerLogic.shouldHideAttachmentButton(
      draftText: currentDraftText,
      isFocused: isComposerFocused,
      hasImage: attachedPreviewImage != nil
    )
    attachmentButton.isHidden = shouldHide
    attachmentButtonWidthConstraint.constant = shouldHide ? 0 : Layout.attachmentButtonSize
    composerRowStack.setCustomSpacing(shouldHide ? 0 : Spacing.xsm, after: attachmentButton)
  }

  private func updateTextViewInteractivity() {
    textView.isEditable = !currentConfiguration.isThreadReadOnly
    textView.isSelectable = !currentConfiguration.isThreadReadOnly
    attachmentButton.isEnabled = !currentConfiguration.isThreadReadOnly && !isProcessingImage
    attachmentPreviewView.isUserInteractionEnabled = true
  }

  private func updateButtonStates() {
    let canSend = FriendsThreadComposerLogic.canSend(
      draftText: currentDraftText,
      hasImage: attachedPreviewImage != nil,
      isThreadReadOnly: currentConfiguration.isThreadReadOnly,
      isSubmitting: isSubmitting,
      isProcessingImage: isProcessingImage
    )

    if isSubmitting {
      sendActivityIndicator.startAnimating()
      sendButton.setImage(nil, for: .normal)
    } else {
      sendActivityIndicator.stopAnimating()
      sendButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
    }

    sendButton.isEnabled = canSend
    sendButton.backgroundColor =
      canSend
      ? Self.color(named: "TidexBrandPrimary", fallback: .systemBlue)
      : Self.color(named: "TidexSurfaceSecondary", fallback: .tertiarySystemFill)
    sendButton.tintColor =
      canSend
      ? Self.color(named: "TidexTextOnBrand", fallback: .white)
      : Self.color(named: "TidexTextMuted", fallback: .secondaryLabel)

    if isProcessingImage {
      let imageConfig = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
      attachmentButton.setImage(nil, for: .normal)
      let indicator = UIActivityIndicatorView(style: .medium)
      indicator.translatesAutoresizingMaskIntoConstraints = false
      indicator.startAnimating()
      indicator.color = Self.color(named: "TidexBlue", fallback: .systemBlue)
      attachmentButton.subviews.filter { $0 is UIActivityIndicatorView }.forEach {
        $0.removeFromSuperview()
      }
      attachmentButton.addSubview(indicator)
      NSLayoutConstraint.activate([
        indicator.centerXAnchor.constraint(equalTo: attachmentButton.centerXAnchor),
        indicator.centerYAnchor.constraint(equalTo: attachmentButton.centerYAnchor),
      ])
      _ = imageConfig
    } else {
      attachmentButton.subviews.filter { $0 is UIActivityIndicatorView }.forEach {
        $0.removeFromSuperview()
      }
      attachmentButton.setImage(UIImage(systemName: "photo.on.rectangle.angled"), for: .normal)
    }
  }

  private func updateComposerChrome() {
    let borderColor =
      isComposerFocused
      ? Self.color(named: "TidexBlue", fallback: .systemBlue).withAlphaComponent(0.4)
      : Self.color(named: "TidexBorder", fallback: .separator).withAlphaComponent(0.38)
    let backgroundColor =
      isComposerFocused
      ? Self.color(named: "TidexSurfacePrimary", fallback: .secondarySystemBackground)
      : Self.color(named: "TidexSurfacePrimary", fallback: .secondarySystemBackground)
    textFieldContainerView.layer.borderColor = borderColor.cgColor
    textFieldContainerView.backgroundColor = backgroundColor

    attachmentButton.backgroundColor =
      attachedPreviewImage != nil
      ? Self.color(named: "TidexBlue", fallback: .systemBlue).withAlphaComponent(0.22)
      : Self.color(named: "TidexBlue", fallback: .systemBlue).withAlphaComponent(0.12)
  }

  @objc
  private func handleAttachmentTap() {
    delegate?.composerViewDidTapAttachment(self, sourceView: attachmentButton)
  }

  @objc
  private func handleSendTap() {
    delegate?.composerViewDidTapSend(self)
  }

  fileprivate static func color(named name: String, fallback: UIColor) -> UIColor {
    UIColor(named: name) ?? fallback
  }
}

extension FriendsThreadComposerView: UITextViewDelegate {
  func textViewDidBeginEditing(_ textView: UITextView) {
    isComposerFocused = true
    refreshVisualState()
  }

  func textViewDidEndEditing(_ textView: UITextView) {
    isComposerFocused = false
    refreshVisualState()
  }

  func textViewDidChange(_ textView: UITextView) {
    updatePlaceholderVisibility()
    updateTextViewHeight()
    updateAttachmentVisibility()
    updateButtonStates()
    guard !suppressDraftCallback else { return }
    delegate?.composerView(self, didChangeDraft: textView.text)
  }
}

@MainActor
private final class FriendsThreadComposerStatusRowView: UIView {
  private let stack = UIStackView()
  private let iconView = UIImageView()
  private let messageLabel = UILabel()
  private let actionButton = UIButton(type: .system)
  private var action: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false

    stack.axis = .horizontal
    stack.alignment = .top
    stack.spacing = Spacing.xs
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)

    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.setContentHuggingPriority(.required, for: .horizontal)
    iconView.setContentCompressionResistancePriority(.required, for: .horizontal)
    stack.addArrangedSubview(iconView)

    messageLabel.translatesAutoresizingMaskIntoConstraints = false
    messageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
    messageLabel.numberOfLines = 0
    stack.addArrangedSubview(messageLabel)

    actionButton.translatesAutoresizingMaskIntoConstraints = false
    actionButton.tintColor = FriendsThreadComposerView.color(
      named: "TidexTextMuted", fallback: .secondaryLabel)
    actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
    actionButton.isHidden = true
    stack.addArrangedSubview(actionButton)

    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func apply(
    iconSystemName: String?,
    iconTintColor: UIColor?,
    message: String,
    messageColor: UIColor,
    trailingButtonImage: UIImage?,
    action: (() -> Void)? = nil
  ) {
    if let iconSystemName {
      iconView.isHidden = false
      iconView.image = UIImage(systemName: iconSystemName)
      iconView.tintColor = iconTintColor
    } else {
      iconView.isHidden = true
      iconView.image = nil
    }

    messageLabel.text = message
    messageLabel.textColor = messageColor
    self.action = action
    if let trailingButtonImage {
      actionButton.isHidden = false
      actionButton.setImage(trailingButtonImage, for: .normal)
    } else {
      actionButton.isHidden = true
      actionButton.setImage(nil, for: .normal)
    }
  }

  @objc
  private func handleAction() {
    action?()
  }
}

@MainActor
private final class FriendsThreadReplyBannerUIKitView: UIView {
  var onCancel: (() -> Void)?

  private let accentBar = UIView()
  private let titleLabel = UILabel()
  private let snippetLabel = UILabel()
  private let cancelButton = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = FriendsThreadComposerView.color(
      named: "TidexSurfaceSecondary",
      fallback: .secondarySystemBackground
    )
    layer.cornerRadius = 14

    accentBar.translatesAutoresizingMaskIntoConstraints = false
    accentBar.backgroundColor = FriendsThreadComposerView.color(
      named: "TidexBlue", fallback: .systemBlue)
    accentBar.layer.cornerRadius = 1.5

    let labelsStack = UIStackView(arrangedSubviews: [titleLabel, snippetLabel])
    labelsStack.axis = .vertical
    labelsStack.spacing = 2
    labelsStack.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = UIFont.preferredFont(forTextStyle: .footnote).bold()
    titleLabel.textColor = FriendsThreadComposerView.color(
      named: "TidexTextPrimary", fallback: .label)

    snippetLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
    snippetLabel.textColor = FriendsThreadComposerView.color(
      named: "TidexTextSecondary", fallback: .secondaryLabel)
    snippetLabel.numberOfLines = 1

    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
    cancelButton.tintColor = FriendsThreadComposerView.color(
      named: "TidexTextMuted", fallback: .secondaryLabel)
    cancelButton.addTarget(self, action: #selector(handleCancel), for: .touchUpInside)

    addSubview(accentBar)
    addSubview(labelsStack)
    addSubview(cancelButton)

    NSLayoutConstraint.activate([
      accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.sm),
      accentBar.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.sm),
      accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.sm),
      accentBar.widthAnchor.constraint(equalToConstant: 3),

      labelsStack.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: Spacing.sm),
      labelsStack.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.sm),
      labelsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.sm),

      cancelButton.leadingAnchor.constraint(
        equalTo: labelsStack.trailingAnchor, constant: Spacing.sm),
      cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.sm),
      cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      cancelButton.widthAnchor.constraint(equalToConstant: 30),
      cancelButton.heightAnchor.constraint(equalToConstant: 30),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func apply(preview: FriendsChatReplyPreviewModel) {
    titleLabel.text = preview.senderName
    snippetLabel.text = preview.snippet
    snippetLabel.isHidden = preview.snippet == nil
  }

  @objc
  private func handleCancel() {
    onCancel?()
  }
}

@MainActor
private final class FriendsThreadAttachmentPreviewView: UIView {
  private enum Layout {
    static let previewSize: CGFloat = 80
  }

  var onRemove: (() -> Void)?

  private let imageView = UIImageView()
  private let removeButton = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFill
    imageView.clipsToBounds = true
    imageView.layer.cornerRadius = 10
    addSubview(imageView)

    removeButton.translatesAutoresizingMaskIntoConstraints = false
    removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    removeButton.tintColor = .white
    removeButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
    removeButton.layer.cornerRadius = 10
    removeButton.addTarget(self, action: #selector(handleRemove), for: .touchUpInside)
    addSubview(removeButton)

    NSLayoutConstraint.activate([
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.widthAnchor.constraint(equalToConstant: Layout.previewSize),
      imageView.heightAnchor.constraint(equalToConstant: Layout.previewSize),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

      removeButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -6),
      removeButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
      removeButton.widthAnchor.constraint(equalToConstant: 20),
      removeButton.heightAnchor.constraint(equalToConstant: 20),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func apply(image: UIImage?) {
    imageView.image = image
  }

  @objc
  private func handleRemove() {
    onRemove?()
  }
}

extension UIFont {
  fileprivate func bold() -> UIFont {
    UIFont.systemFont(ofSize: pointSize, weight: .semibold)
  }
}
