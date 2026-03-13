import PhotosUI
import SwiftUI
import UIKit

/// Chat input field with send button and image attachment support
/// Supports multi-line input, image uploads, and disabled states
struct ChatInputField: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private enum ComposerLayout {
    static let defaultAttachmentCollapseCharacterThreshold = 32
  }

  /// Callback when user sends a message (text only)
  let onSend: (String) async -> Bool

  /// Callback when user sends a message with an image
  let onSendWithImage: ((String, ImageAttachment) async -> Bool)?

  /// Callback when the user cancels an in-flight stream
  let onCancel: (() -> Void)?

  /// Whether the input should be disabled
  let disabled: Bool
  let isStreaming: Bool
  let placeholder: String
  let horizontalPadding: CGFloat
  let focusedHorizontalPadding: CGFloat?
  let bottomPadding: CGFloat
  let showsCameraShortcut: Bool
  let showsImagePreview: Bool
  let hasSupplementalSendContent: Bool
  let showsAttachmentPicker: Bool
  let collapsesAttachmentButtonForLongDrafts: Bool
  let attachmentCollapseCharacterThreshold: Int
  let dismissKeyboardOnSend: Bool

  /// Current input text
  @Binding var inputText: String
  private let externalAttachedImage: Binding<ImageAttachment?>?

  /// Selected photo item from PhotosPicker
  @State private var selectedPhotoItem: PhotosPickerItem?

  /// Attached image data (compressed for upload)
  @State private var attachedImage: ImageAttachment?

  /// Whether image is being processed
  @State private var isProcessingImage = false
  @State private var isSubmitting = false
  @State private var isComposerFocused = false
  @State private var showCamera = false
  @State private var showLibrary = false
  @State private var showAttachmentSourcePicker = false

  /// Error message for image processing
  @State private var imageError: String?

  /// Initialize with text-only send callback
  init(
    inputText: Binding<String>,
    placeholder: String = String(localized: .wageyPlaceholderWelcome),
    horizontalPadding: CGFloat = MonthPickerLayout.horizontalPadding,
    focusedHorizontalPadding: CGFloat? = nil,
    bottomPadding: CGFloat = MonthPickerLayout.bottomPadding,
    showsCameraShortcut: Bool = false,
    attachedImage: Binding<ImageAttachment?>? = nil,
    showsImagePreview: Bool = true,
    hasSupplementalSendContent: Bool = false,
    showsAttachmentPicker: Bool = true,
    collapsesAttachmentButtonForLongDrafts: Bool = false,
    attachmentCollapseCharacterThreshold: Int = ComposerLayout
      .defaultAttachmentCollapseCharacterThreshold,
    dismissKeyboardOnSend: Bool = true,
    onSend: @escaping (String) async -> Bool,
    onCancel: (() -> Void)? = nil,
    isStreaming: Bool = false,
    disabled: Bool
  ) {
    self._inputText = inputText
    self.placeholder = placeholder
    self.horizontalPadding = horizontalPadding
    self.focusedHorizontalPadding = focusedHorizontalPadding
    self.bottomPadding = bottomPadding
    self.showsCameraShortcut = showsCameraShortcut
    self.externalAttachedImage = attachedImage
    self.showsImagePreview = showsImagePreview
    self.hasSupplementalSendContent = hasSupplementalSendContent
    self.showsAttachmentPicker = showsAttachmentPicker
    self.collapsesAttachmentButtonForLongDrafts = collapsesAttachmentButtonForLongDrafts
    self.attachmentCollapseCharacterThreshold = attachmentCollapseCharacterThreshold
    self.dismissKeyboardOnSend = dismissKeyboardOnSend
    self.onSend = onSend
    self.onSendWithImage = nil
    self.onCancel = onCancel
    self.isStreaming = isStreaming
    self.disabled = disabled
  }

  /// Initialize with both text and image send callbacks
  init(
    inputText: Binding<String>,
    placeholder: String = String(localized: .wageyPlaceholderWelcome),
    horizontalPadding: CGFloat = MonthPickerLayout.horizontalPadding,
    focusedHorizontalPadding: CGFloat? = nil,
    bottomPadding: CGFloat = MonthPickerLayout.bottomPadding,
    showsCameraShortcut: Bool = false,
    attachedImage: Binding<ImageAttachment?>? = nil,
    showsImagePreview: Bool = true,
    hasSupplementalSendContent: Bool = false,
    showsAttachmentPicker: Bool = true,
    collapsesAttachmentButtonForLongDrafts: Bool = false,
    attachmentCollapseCharacterThreshold: Int = ComposerLayout
      .defaultAttachmentCollapseCharacterThreshold,
    dismissKeyboardOnSend: Bool = true,
    onSend: @escaping (String) async -> Bool,
    onSendWithImage: @escaping (String, ImageAttachment) async -> Bool,
    onCancel: (() -> Void)? = nil,
    isStreaming: Bool = false,
    disabled: Bool
  ) {
    self._inputText = inputText
    self.placeholder = placeholder
    self.horizontalPadding = horizontalPadding
    self.focusedHorizontalPadding = focusedHorizontalPadding
    self.bottomPadding = bottomPadding
    self.showsCameraShortcut = showsCameraShortcut
    self.externalAttachedImage = attachedImage
    self.showsImagePreview = showsImagePreview
    self.hasSupplementalSendContent = hasSupplementalSendContent
    self.showsAttachmentPicker = showsAttachmentPicker
    self.collapsesAttachmentButtonForLongDrafts = collapsesAttachmentButtonForLongDrafts
    self.attachmentCollapseCharacterThreshold = attachmentCollapseCharacterThreshold
    self.dismissKeyboardOnSend = dismissKeyboardOnSend
    self.onSend = onSend
    self.onSendWithImage = onSendWithImage
    self.onCancel = onCancel
    self.isStreaming = isStreaming
    self.disabled = disabled
  }

  private var canPerformPrimaryAction: Bool {
    if isStreaming {
      return onCancel != nil
    }

    return canSend
  }

  private var actionAccessibilityLabel: String {
    if isStreaming {
      return String(localized: .commonCancel)
    }

    return String(localized: "Send message")
  }

  private var actionSystemImage: String {
    isStreaming ? "stop.fill" : "arrow.up"
  }

  private var actionForegroundColor: Color {
    .tidexTextOnBrand
  }

  private var actionBackgroundColor: Color {
    isStreaming ? .tidexWarning : .tidexBrandPrimary
  }

  private var composerTextDisabled: Bool {
    disabled
  }

  private var attachmentControlsDisabled: Bool {
    effectiveDisabled || isStreaming
  }

  private var allowsImageRemoval: Bool {
    !isSubmitting && !isStreaming
  }

  private func handlePrimaryAction() {
    if isStreaming {
      Haptics.play(.light)
      onCancel?()
      return
    }

    sendMessage()
  }

  /// Whether the send button can be tapped
  private var canSend: Bool {
    let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasImage = currentAttachedImage != nil
    return (hasText || hasImage || hasSupplementalSendContent)
      && !effectiveDisabled
      && !isProcessingImage
  }

  private var effectiveDisabled: Bool {
    disabled || isSubmitting
  }

  private var attachmentButtonTint: Color {
    currentAttachedImage != nil ? Color.tidexBlue.opacity(0.22) : Color.tidexBlue.opacity(0.12)
  }

  private var cameraAvailable: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera)
  }

  private var effectiveHorizontalPadding: CGFloat {
    guard isComposerFocused, let focusedHorizontalPadding else { return horizontalPadding }
    return focusedHorizontalPadding
  }

  private var shouldHideAttachmentButton: Bool {
    guard onSendWithImage != nil else { return false }
    guard collapsesAttachmentButtonForLongDrafts else { return false }
    guard currentAttachedImage == nil else { return false }
    guard isComposerFocused else { return false }

    let draftLength = inputText.trimmingCharacters(in: .whitespacesAndNewlines).count
    return draftLength >= attachmentCollapseCharacterThreshold
      || inputText.contains("\n")
  }

  var body: some View {
    VStack(spacing: 0) {
      // Image preview (if attached)
      if showsImagePreview, let image = currentAttachedImage,
        let uiImage = UIImage(data: image.data)
      {
        imagePreview(uiImage: uiImage)
      }

      // Error message
      if let error = imageError {
        errorBanner(message: error)
      }

      // Input area
      ChatComposerField(
        text: $inputText,
        placeholder: placeholder,
        disabled: composerTextDisabled,
        isSending: isSubmitting,
        canPerformAction: canPerformPrimaryAction,
        actionAccessibilityLabel: actionAccessibilityLabel,
        actionSystemImage: actionSystemImage,
        actionForegroundColor: actionForegroundColor,
        actionBackgroundColor: actionBackgroundColor,
        triggersSubmit: !isStreaming,
        onFocusChanged: { isComposerFocused = $0 },
        horizontalPadding: effectiveHorizontalPadding,
        topPadding: Spacing.xs,
        bottomPadding: bottomPadding,
        onAction: handlePrimaryAction
      ) {
        if onSendWithImage != nil && showsAttachmentPicker && !shouldHideAttachmentButton {
          attachmentPickerButton
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86),
        value: isComposerFocused
      )
      .animation(
        reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.9),
        value: shouldHideAttachmentButton
      )
    }
    .onChange(of: selectedPhotoItem) { _, newItem in
      processSelectedPhoto(newItem)
    }
    .photosPicker(
      isPresented: $showLibrary,
      selection: $selectedPhotoItem,
      matching: .images,
      photoLibrary: .shared()
    )
    .fullScreenCover(isPresented: $showCamera) {
      CameraPicker { image in
        processCapturedImage(image)
      }
      .ignoresSafeArea()
    }
    .confirmationDialog(
      String(localized: "profile.personalInfo.chooseImageSource"),
      isPresented: $showAttachmentSourcePicker,
      titleVisibility: .visible
    ) {
      if showsCameraShortcut && cameraAvailable {
        Button(String(localized: "profile.personalInfo.takePhoto")) {
          showCamera = true
        }
      }

      Button(String(localized: "profile.personalInfo.chooseFromLibrary")) {
        showLibrary = true
      }

      Button(String(localized: .commonCancel), role: .cancel) {}
    }
  }

  // MARK: - Attachment Button

  private var attachmentPickerButton: some View {
    Button {
      guard !attachmentControlsDisabled, !isProcessingImage else { return }
      showAttachmentSourcePicker = true
    } label: {
      ZStack {
        if isProcessingImage {
          ProgressView()
            .scaleEffect(0.8)
            .frame(width: 50, height: 50)
        } else {
          Image(systemName: "photo.on.rectangle.angled")
            .font(.system(size: 21))
            .foregroundColor(effectiveDisabled ? .tidexTextMuted : .tidexBlue)
        }
      }
      .frame(width: 50, height: 50)
      .tidexGlass(
        shape: .circle,
        tint: attachmentButtonTint,
        interactive: !attachmentControlsDisabled && !isProcessingImage,
        disabled: attachmentControlsDisabled || isProcessingImage,
        fallbackOpacity: 0.9
      )
      .shadow(color: Color.tidexBlue.opacity(0.05), radius: 12, y: 4)
    }
    .buttonStyle(.plain)
    .disabled(attachmentControlsDisabled || isProcessingImage)
    .frame(width: 50, height: 50)
    .contentShape(Rectangle())
    .accessibilityLabel(Text(String(localized: "profile.personalInfo.uploadImage")))
  }

  // MARK: - Image Preview

  private func imagePreview(uiImage: UIImage) -> some View {
    HStack {
      ZStack(alignment: .topTrailing) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: 80, height: 80)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))

        // Remove button
        Button {
          guard allowsImageRemoval else { return }
          if reduceMotion {
            currentAttachedImage = nil
            selectedPhotoItem = nil
          } else {
            withAnimation(.easeInOut(duration: 0.2)) {
              currentAttachedImage = nil
              selectedPhotoItem = nil
            }
          }
          Haptics.play(.light)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 20))
            .foregroundColor(.white)
            .background(
              Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 18, height: 18)
            )
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(String(localized: "profile.personalInfo.removeImage")))
        .offset(x: 6, y: -6)
      }

      Spacer()
    }
    .padding(.horizontal, Spacing.md)
    .padding(.top, Spacing.xs)
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
  }

  // MARK: - Error Banner

  private func errorBanner(message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundColor(.tidexWarning)
        .font(.tidexSubheadline)

      Text(message)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextPrimary)

      Spacer()

      Button {
        if reduceMotion {
          imageError = nil
        } else {
          withAnimation {
            imageError = nil
          }
        }
      } label: {
        Image(systemName: "xmark")
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(Text(String(localized: "screenshotShare.dismiss")))
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Photo Processing

  private func processSelectedPhoto(_ item: PhotosPickerItem?) {
    guard let item = item else { return }

    isProcessingImage = true
    imageError = nil

    Task {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          throw ImageProcessingError.loadFailed
        }

        try await processImageData(data)
      } catch {
        await MainActor.run {
          imageError = String(localized: .wageyImageError)
          isProcessingImage = false
          selectedPhotoItem = nil
          Haptics.play(.error)
        }
      }
    }
  }

  private func processCapturedImage(_ image: UIImage) {
    isProcessingImage = true
    imageError = nil

    Task {
      do {
        let compressed = await Task.detached(priority: .userInitiated) {
          ImageCompressor.compress(image)
        }.value

        guard let compressed else {
          throw ImageProcessingError.compressionFailed
        }

        await MainActor.run {
          currentAttachedImage = ImageAttachment(
            data: compressed.data,
            mediaType: compressed.mediaType
          )
          isProcessingImage = false
          Haptics.play(.success)
        }
      } catch {
        await MainActor.run {
          imageError = String(localized: .wageyImageError)
          isProcessingImage = false
          Haptics.play(.error)
        }
      }
    }
  }

  private func processImageData(_ data: Data) async throws {
    let compressed = await Task.detached(priority: .userInitiated) {
      ImageCompressor.compress(data)
    }.value

    guard let compressed else {
      throw ImageProcessingError.compressionFailed
    }

    await MainActor.run {
      currentAttachedImage = ImageAttachment(
        data: compressed.data,
        mediaType: compressed.mediaType
      )
      isProcessingImage = false
      Haptics.play(.success)
    }
  }

  private enum ImageProcessingError: Error {
    case loadFailed
    case compressionFailed
  }

  // MARK: - Actions

  private func sendMessage() {
    guard canSend else { return }

    let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    let image = currentAttachedImage

    // Provide haptic feedback
    Haptics.play(.medium)

    if dismissKeyboardOnSend {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    isSubmitting = true

    Task {
      let didSend: Bool
      if let image, let onSendWithImage {
        didSend = await onSendWithImage(message, image)
      } else if !message.isEmpty {
        didSend = await onSend(message)
      } else {
        didSend = false
      }

      await MainActor.run {
        isSubmitting = false

        if didSend {
          inputText = ""
          currentAttachedImage = nil
          selectedPhotoItem = nil
        }
      }
    }
  }

  private var currentAttachedImage: ImageAttachment? {
    get { externalAttachedImage?.wrappedValue ?? attachedImage }
    nonmutating set {
      if let externalAttachedImage {
        externalAttachedImage.wrappedValue = newValue
      } else {
        attachedImage = newValue
      }
    }
  }
}

// MARK: - Previews

#Preview("Default") {
  @Previewable @State var text = ""
  VStack {
    Spacer()
    ChatInputField(
      inputText: $text,
      onSend: { message in
        print("Sent: \(message)")
        return true
      },
      disabled: false
    )
  }
  .background(Color.tidexBackground)
}

#Preview("With Image Support") {
  @Previewable @State var text = ""
  VStack {
    Spacer()
    ChatInputField(
      inputText: $text,
      onSend: { message in
        print("Sent text: \(message)")
        return true
      },
      onSendWithImage: { message, image in
        print("Sent with image: \(message), size: \(image.data.count) bytes")
        return true
      },
      disabled: false
    )
  }
  .background(Color.tidexBackground)
}

#Preview("Disabled") {
  @Previewable @State var text = ""
  VStack {
    Spacer()
    ChatInputField(
      inputText: $text,
      onSend: { message in
        print("Sent: \(message)")
        return true
      },
      disabled: true
    )
  }
  .background(Color.tidexBackground)
}
