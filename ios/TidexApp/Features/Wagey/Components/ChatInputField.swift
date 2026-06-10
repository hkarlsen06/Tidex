import PhotosUI
import SwiftUI
import UIKit

/// Chat input field with send button and image attachment support
/// Supports multi-line input, image uploads, and disabled states
struct ChatInputField: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  private enum ComposerLayout {
    static let defaultAttachmentCollapseCharacterThreshold = 32  // swiftlint:disable:this explicit_type_interface identifier_name line_length
  }

  /// Callback when user sends a message (text only)
  let onSend: (String) async -> Bool  // swiftlint:disable:this explicit_acl type_contents_order

  /// Callback when user sends a message with an image
  let onSendWithImage: ((String, ImageAttachment) async -> Bool)?  // swiftlint:disable:this explicit_acl line_length type_contents_order

  /// Callback when the user cancels an in-flight stream
  let onCancel: (() -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order

  /// Whether the input should be disabled
  let disabled: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let isStreaming: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let placeholder: String  // swiftlint:disable:this explicit_acl type_contents_order
  let horizontalPadding: CGFloat  // swiftlint:disable:this explicit_acl type_contents_order
  let focusedHorizontalPadding: CGFloat?  // swiftlint:disable:this explicit_acl type_contents_order
  let bottomPadding: CGFloat  // swiftlint:disable:this explicit_acl type_contents_order
  let showsCameraShortcut: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let showsImagePreview: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let hasSupplementalSendContent: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let showsAttachmentPicker: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let collapsesAttachmentButtonForLongDrafts: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let attachmentCollapseCharacterThreshold: Int  // swiftlint:disable:this explicit_acl type_contents_order
  let dismissKeyboardOnSend: Bool  // swiftlint:disable:this explicit_acl type_contents_order

  /// Current input text
  @Binding var inputText: String  // swiftlint:disable:this explicit_acl type_contents_order
  private let externalAttachedImage: Binding<ImageAttachment?>?  // swiftlint:disable:this type_contents_order

  /// Selected photo item from PhotosPicker
  @State private var selectedPhotoItem: PhotosPickerItem?  // swiftlint:disable:this type_contents_order

  /// Attached image data (compressed for upload)
  @State private var attachedImage: ImageAttachment?  // swiftlint:disable:this type_contents_order

  /// Whether image is being processed
  @State private var isProcessingImage = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var isSubmitting = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var isComposerFocused = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var showCamera = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var showLibrary = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  @State private var showAttachmentSourcePicker = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  /// Error message for image processing
  @State private var imageError: String?  // swiftlint:disable:this type_contents_order

  /// Initialize with text-only send callback
  init(  // swiftlint:disable:this explicit_acl type_contents_order
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
    isStreaming: Bool = false,  // swiftlint:disable:this function_default_parameter_at_end
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
  init(  // swiftlint:disable:this explicit_acl type_contents_order
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
    isStreaming: Bool = false,  // swiftlint:disable:this function_default_parameter_at_end
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

  private var canPerformPrimaryAction: Bool {  // swiftlint:disable:this type_contents_order
    if isStreaming {
      return onCancel != nil
    }

    return canSend
  }

  private var actionAccessibilityLabel: String {  // swiftlint:disable:this type_contents_order
    if isStreaming {
      return String(localized: .commonCancel)
    }

    return String(localized: .commonSendMessage)
  }

  private var actionSystemImage: String {  // swiftlint:disable:this type_contents_order
    isStreaming ? "stop.fill" : "arrow.up"
  }

  private var actionForegroundColor: Color {  // swiftlint:disable:this type_contents_order
    .tidexTextOnBrand
  }

  private var actionBackgroundColor: Color {  // swiftlint:disable:this type_contents_order
    isStreaming ? .tidexWarning : .tidexBrandPrimary
  }

  private var composerTextDisabled: Bool {  // swiftlint:disable:this type_contents_order
    disabled
  }

  private var attachmentControlsDisabled: Bool {  // swiftlint:disable:this type_contents_order
    effectiveDisabled || isStreaming
  }

  private var allowsImageRemoval: Bool {  // swiftlint:disable:this type_contents_order
    !isSubmitting && !isStreaming
  }

  private func handlePrimaryAction() {  // swiftlint:disable:this type_contents_order
    if isStreaming {
      Haptics.play(.light)
      onCancel?()
      return
    }

    sendMessage()
  }

  /// Whether the send button can be tapped
  private var canSend: Bool {  // swiftlint:disable:this type_contents_order
    let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty  // swiftlint:disable:this explicit_type_interface line_length
    let hasImage = currentAttachedImage != nil  // swiftlint:disable:this explicit_type_interface
    return (hasText || hasImage || hasSupplementalSendContent)
      && !effectiveDisabled
      && !isProcessingImage
  }

  private var effectiveDisabled: Bool {  // swiftlint:disable:this type_contents_order
    disabled || isSubmitting
  }

  private var attachmentButtonTint: Color {  // swiftlint:disable:this type_contents_order
    currentAttachedImage != nil ? Color.tidexBlue.opacity(0.22) : Color.tidexBlue.opacity(0.12)  // swiftlint:disable:this line_length no_magic_numbers
  }

  private var cameraAvailable: Bool {  // swiftlint:disable:this type_contents_order
    UIImagePickerController.isSourceTypeAvailable(.camera)
  }

  private var shouldShowAttachmentSourcePicker: Bool {  // swiftlint:disable:this type_contents_order
    showsCameraShortcut && cameraAvailable
  }

  private var effectiveHorizontalPadding: CGFloat {  // swiftlint:disable:this type_contents_order
    guard isComposerFocused, let focusedHorizontalPadding else { return horizontalPadding }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return focusedHorizontalPadding
  }

  private var shouldHideAttachmentButton: Bool {  // swiftlint:disable:this type_contents_order
    guard onSendWithImage != nil else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    guard collapsesAttachmentButtonForLongDrafts else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard currentAttachedImage == nil else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    guard isComposerFocused else { return false }  // swiftlint:disable:this conditional_returns_on_newline

    let draftLength = inputText.trimmingCharacters(in: .whitespacesAndNewlines).count  // swiftlint:disable:this explicit_type_interface line_length
    return draftLength >= attachmentCollapseCharacterThreshold
      || inputText.contains("\n")
  }

  var body: some View {  // swiftlint:disable:this explicit_acl type_contents_order
    VStack(spacing: 0) {  // swiftlint:disable:this closure_body_length
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
        submitLabel: .return,
        triggersSubmit: !isStreaming,
        onFocusChanged: { isComposerFocused = $0 },
        horizontalPadding: effectiveHorizontalPadding,
        topPadding: Spacing.xs,
        bottomPadding: bottomPadding,
        onAction: handlePrimaryAction
      ) {
        if onSendWithImage != nil, showsAttachmentPicker, !shouldHideAttachmentButton {
          attachmentPickerButton
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
      }
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.16),  // swiftlint:disable:this no_magic_numbers
        value: isComposerFocused
      )
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.14),  // swiftlint:disable:this no_magic_numbers
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
      String(localized: .profilePersonalInfoChooseImageSource),
      isPresented: $showAttachmentSourcePicker,
      titleVisibility: .visible
    ) {
      if shouldShowAttachmentSourcePicker {
        Button(String(localized: .profilePersonalInfoTakePhoto)) {
          showCamera = true
        }
      }

      Button(String(localized: .profilePersonalInfoChooseFromLibrary)) {
        showLibrary = true
      }

      Button(String(localized: .commonCancel), role: .cancel) {}  // swiftlint:disable:this no_empty_block
    }
  }

  // MARK: - Attachment Button

  private var attachmentPickerButton: some View {  // swiftlint:disable:this type_contents_order
    Button {
      guard !attachmentControlsDisabled, !isProcessingImage else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
      if shouldShowAttachmentSourcePicker {
        showAttachmentSourcePicker = true
      } else {
        showLibrary = true
      }
    } label: {
      ZStack {
        if isProcessingImage {
          ProgressView()
            .scaleEffect(0.8)  // swiftlint:disable:this no_magic_numbers
            .frame(width: 50, height: 50)  // swiftlint:disable:this no_magic_numbers
        } else {
          Image(systemName: "photo.on.rectangle.angled")  // swiftlint:disable:this accessibility_label_for_image
            .font(.system(size: 21))  // swiftlint:disable:this no_magic_numbers
            .foregroundColor(attachmentControlsDisabled ? .tidexTextMuted : .tidexBlue)
        }
      }
      .frame(width: 50, height: 50)  // swiftlint:disable:this no_magic_numbers
      .tidexGlass(
        shape: .circle,
        tint: attachmentButtonTint,
        interactive: !attachmentControlsDisabled && !isProcessingImage,
        disabled: attachmentControlsDisabled || isProcessingImage,
        fallbackOpacity: 0.9  // swiftlint:disable:this no_magic_numbers
      )
      .shadow(color: Color.tidexBlue.opacity(0.05), radius: 12, y: 4)  // swiftlint:disable:this no_magic_numbers
    }
    .buttonStyle(.plain)
    .disabled(attachmentControlsDisabled || isProcessingImage)
    .frame(width: 50, height: 50)  // swiftlint:disable:this no_magic_numbers
    .contentShape(Rectangle())
    .accessibilityLabel(Text(.profilePersonalInfoUploadImage))
  }

  // MARK: - Image Preview

  private func imagePreview(uiImage: UIImage) -> some View {  // swiftlint:disable:this type_contents_order
    HStack {  // swiftlint:disable:this closure_body_length
      ZStack(alignment: .topTrailing) {  // swiftlint:disable:this closure_body_length
        Image(uiImage: uiImage)  // swiftlint:disable:this accessibility_label_for_image
          .resizable()
          .scaledToFill()
          .frame(width: 80, height: 80)  // swiftlint:disable:this no_magic_numbers
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))

        // Remove button
        Button {
          guard allowsImageRemoval else { return }  // swiftlint:disable:this conditional_returns_on_newline
          if reduceMotion {
            currentAttachedImage = nil
            selectedPhotoItem = nil
          } else {
            withAnimation(.easeInOut(duration: 0.2)) {  // swiftlint:disable:this no_magic_numbers
              currentAttachedImage = nil
              selectedPhotoItem = nil
            }
          }
          Haptics.play(.light)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 20))  // swiftlint:disable:this no_magic_numbers
            .foregroundColor(.tidexTextOnBrand)
            .background(
              Circle()
                .fill(Color.tidexDarkBackgroundColor.opacity(0.62))  // swiftlint:disable:this no_magic_numbers
                .frame(width: 18, height: 18)  // swiftlint:disable:this no_magic_numbers
            )
            .frame(minWidth: 44, minHeight: 44)  // swiftlint:disable:this no_magic_numbers
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(.profilePersonalInfoRemoveImage))
        .offset(x: 6, y: -6)  // swiftlint:disable:this no_magic_numbers
      }

      Spacer()
    }
    .padding(.horizontal, Spacing.md)
    .padding(.top, Spacing.xs)
    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))  // swiftlint:disable:this line_length no_magic_numbers
  }

  // MARK: - Error Banner

  private func errorBanner(message: String) -> some View {  // swiftlint:disable:this type_contents_order
    HStack(spacing: Spacing.xs) {
      Image(systemName: "exclamationmark.triangle.fill")  // swiftlint:disable:this accessibility_label_for_image
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
          .frame(minWidth: 44, minHeight: 44)  // swiftlint:disable:this no_magic_numbers
          .contentShape(Rectangle())
      }
      .accessibilityLabel(Text(.screenshotShareDismiss))
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Photo Processing

  private func processSelectedPhoto(_ item: PhotosPickerItem?) {  // swiftlint:disable:this type_contents_order
    guard let item else { return }  // swiftlint:disable:this conditional_returns_on_newline

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

  private func processCapturedImage(_ image: UIImage) {  // swiftlint:disable:this type_contents_order
    isProcessingImage = true
    imageError = nil

    Task {
      do {
        let compressed = await Task.detached(priority: .userInitiated) {  // swiftlint:disable:this explicit_type_interface line_length
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

  private func processImageData(_ data: Data) async throws {  // swiftlint:disable:this type_contents_order
    let compressed = await Task.detached(priority: .userInitiated) {  // swiftlint:disable:this explicit_type_interface
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

  private func sendMessage() {  // swiftlint:disable:this type_contents_order
    guard canSend else { return }  // swiftlint:disable:this conditional_returns_on_newline

    let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)  // swiftlint:disable:this explicit_type_interface line_length
    let image = currentAttachedImage  // swiftlint:disable:this explicit_type_interface

    // Provide haptic feedback
    Haptics.play(.medium)

    if dismissKeyboardOnSend {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)  // swiftlint:disable:this line_length multiline_arguments_brackets
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
  @Previewable @State var text = ""  // swiftlint:disable:this explicit_type_interface
  VStack {
    Spacer()
    ChatInputField(
      inputText: $text,
      onSend: { message in
        print("Sent: \(message)")  // swiftlint:disable:this no_direct_print
        return true
      },
      disabled: false
    )
  }
  .background(Color.tidexBackground)
}

#Preview("With Image Support") {
  @Previewable @State var text = ""  // swiftlint:disable:this explicit_type_interface
  VStack {
    Spacer()
    ChatInputField(
      inputText: $text,
      onSend: { message in
        print("Sent text: \(message)")  // swiftlint:disable:this no_direct_print
        return true
      },
      onSendWithImage: { message, image in
        print("Sent with image: \(message), size: \(image.data.count) bytes")  // swiftlint:disable:this no_direct_print
        return true
      },
      disabled: false
    )
  }
  .background(Color.tidexBackground)
}

#Preview("Disabled") {
  @Previewable @State var text = ""  // swiftlint:disable:this explicit_type_interface
  VStack {
    Spacer()
    ChatInputField(
      inputText: $text,
      onSend: { message in
        print("Sent: \(message)")  // swiftlint:disable:this no_direct_print
        return true
      },
      disabled: true
    )
  }
  .background(Color.tidexBackground)
}  // swiftlint:disable:this file_length
