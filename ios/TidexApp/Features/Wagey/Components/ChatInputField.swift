import PhotosUI
import SwiftUI

/// Chat input field with send button and image attachment support
/// Supports multi-line input, image uploads, and disabled states
struct ChatInputField: View {
  /// Callback when user sends a message (text only)
  let onSend: (String) -> Void

  /// Callback when user sends a message with an image
  let onSendWithImage: ((String, ImageAttachment) -> Void)?

  /// Whether the input should be disabled
  let disabled: Bool

  /// Current input text
  @Binding var inputText: String

  /// Whether the text field is focused
  @FocusState private var isFocused: Bool

  /// Selected photo item from PhotosPicker
  @State private var selectedPhotoItem: PhotosPickerItem?

  /// Attached image data (compressed for upload)
  @State private var attachedImage: ImageAttachment?

  /// Whether image is being processed
  @State private var isProcessingImage = false

  /// Error message for image processing
  @State private var imageError: String?

  /// Initialize with text-only send callback
  init(inputText: Binding<String>, onSend: @escaping (String) -> Void, disabled: Bool) {
    self._inputText = inputText
    self.onSend = onSend
    self.onSendWithImage = nil
    self.disabled = disabled
  }

  /// Initialize with both text and image send callbacks
  init(
    inputText: Binding<String>,
    onSend: @escaping (String) -> Void,
    onSendWithImage: @escaping (String, ImageAttachment) -> Void,
    disabled: Bool
  ) {
    self._inputText = inputText
    self.onSend = onSend
    self.onSendWithImage = onSendWithImage
    self.disabled = disabled
  }

  /// Whether the send button can be tapped
  private var canSend: Bool {
    let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hasImage = attachedImage != nil
    return (hasText || hasImage) && !disabled && !isProcessingImage
  }

  var body: some View {
    VStack(spacing: 0) {
      // Image preview (if attached)
      if let image = attachedImage, let uiImage = UIImage(data: image.data) {
        imagePreview(uiImage: uiImage)
      }

      // Error message
      if let error = imageError {
        errorBanner(message: error)
      }

      // Input area
      HStack(alignment: .center, spacing: Spacing.xsm) {
        // Image picker button (outside the capsule)
        if onSendWithImage != nil {
          imagePickerButton
        }

        // Text field capsule
        HStack(alignment: .center, spacing: Spacing.xs) {
          TextField(
            String(localized: .wageyPlaceholder),
            text: $inputText,
            axis: .vertical
          )
          .textFieldStyle(.plain)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1...5)
          .focused($isFocused)
          .disabled(disabled)
          .submitLabel(.return)
          .onSubmit {
            sendMessage()
          }

          // Send button (inside capsule, appears when content ready)
          if canSend {
            Button(action: sendMessage) {
              Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28))
                .foregroundColor(.tidexBlue)
            }
            .transition(.scale.combined(with: .opacity))
          }
        }
        .padding(.horizontal, Spacing.msm)
        .padding(.vertical, Spacing.xs)
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .animation(.easeInOut(duration: 0.15), value: canSend)
    }
    .background(Color.tidexBackground)
    .safeAreaPadding(.bottom)
    .onChange(of: selectedPhotoItem) { _, newItem in
      processSelectedPhoto(newItem)
    }
  }

  // MARK: - Image Picker Button

  private var imagePickerButton: some View {
    PhotosPicker(
      selection: $selectedPhotoItem,
      matching: .images,
      photoLibrary: .shared()
    ) {
      if isProcessingImage {
        ProgressView()
          .scaleEffect(0.8)
          .frame(width: 28, height: 28)
      } else {
        Image(systemName: "photo.on.rectangle.angled")
          .font(.system(size: 22))
          .foregroundColor(disabled ? .tidexTextMuted : .tidexBlue)
      }
    }
    .disabled(disabled || isProcessingImage)
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
          withAnimation(.easeInOut(duration: 0.2)) {
            attachedImage = nil
            selectedPhotoItem = nil
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
        }
        .offset(x: 6, y: -6)
      }

      Spacer()
    }
    .padding(.horizontal, Spacing.md)
    .padding(.top, Spacing.xs)
    .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
        withAnimation {
          imageError = nil
        }
      } label: {
        Image(systemName: "xmark")
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
    .background(Color.tidexSurfaceSecondary)
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

        guard let compressed = ImageCompressor.compress(data) else {
          throw ImageProcessingError.compressionFailed
        }

        await MainActor.run {
          attachedImage = ImageAttachment(
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
          selectedPhotoItem = nil
          Haptics.play(.error)
        }
      }
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

    // Provide haptic feedback
    Haptics.play(.medium)

    // Dismiss keyboard
    isFocused = false

    // Clear input
    inputText = ""

    // Send message with or without image
    if let image = attachedImage, let onSendWithImage = onSendWithImage {
      // Clear image attachment
      attachedImage = nil
      selectedPhotoItem = nil

      // Send with image
      onSendWithImage(message, image)
    } else if !message.isEmpty {
      // Send text only
      onSend(message)
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
      },
      onSendWithImage: { message, image in
        print("Sent with image: \(message), size: \(image.data.count) bytes")
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
      },
      disabled: true
    )
  }
  .background(Color.tidexBackground)
}
