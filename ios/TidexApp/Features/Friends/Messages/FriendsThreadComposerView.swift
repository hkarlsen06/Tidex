import SwiftUI

struct FriendsThreadComposerConfiguration: Equatable {
  let draftText: String
  let replyPreview: FriendsChatReplyPreviewModel?
  let isThreadReadOnly: Bool
  let sendErrorMessage: String?
  let placeholder: String
}

@MainActor
final class FriendsThreadComposerBridge: ObservableObject {
  @Published private(set) var draftText: String = ""
  @Published private(set) var replyPreview: FriendsChatReplyPreviewModel?
  @Published private(set) var isThreadReadOnly = false
  @Published private(set) var sendErrorMessage: String?
  @Published private(set) var placeholder: String = ""

  var onDraftChanged: ((String) -> Void)?
  var onCancelReply: (() -> Void)?
  var onSend: ((String, ImageAttachment?) async -> Bool)?
  var onHeightChanged: ((CGFloat) -> Void)?

  private var isApplyingExternalDraft = false

  var draftBinding: Binding<String> {
    Binding(
      get: { self.draftText },
      set: { [weak self] newValue in
        self?.updateDraftText(newValue)
      }
    )
  }

  func apply(configuration: FriendsThreadComposerConfiguration) {
    replyPreview = configuration.replyPreview
    isThreadReadOnly = configuration.isThreadReadOnly
    sendErrorMessage = configuration.sendErrorMessage
    placeholder = configuration.placeholder

    guard draftText != configuration.draftText else { return }
    isApplyingExternalDraft = true
    draftText = configuration.draftText
    isApplyingExternalDraft = false
  }

  func cancelReply() {
    onCancelReply?()
  }

  func send(content: String, image: ImageAttachment?) async -> Bool {
    guard let onSend else { return false }
    return await onSend(content, image)
  }

  func reportHeight(_ height: CGFloat) {
    onHeightChanged?(height)
  }

  private func updateDraftText(_ newValue: String) {
    guard draftText != newValue else { return }
    draftText = newValue
    guard !isApplyingExternalDraft else { return }
    onDraftChanged?(newValue)
  }
}

struct FriendsThreadComposerHostedView: View {
  @ObservedObject var bridge: FriendsThreadComposerBridge

  private let attachmentCollapseCharacterThreshold = 18

  var body: some View {
    VStack(spacing: Spacing.xs) {
      if let replyPreview = bridge.replyPreview {
        FriendsThreadComposerReplyBanner(
          preview: replyPreview,
          onCancel: bridge.cancelReply
        )
        .padding(.horizontal, Spacing.md)
      }

      if bridge.isThreadReadOnly {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "hand.raised.fill")
            .foregroundColor(.tidexWarning)

          Text(.friendsChatBlockedReadOnly)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)

          Spacer()
        }
        .padding(.horizontal, Spacing.md)
      }

      if let sendErrorMessage = bridge.sendErrorMessage {
        HStack(spacing: Spacing.xs) {
          Text(sendErrorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)

          Spacer()
        }
        .padding(.horizontal, Spacing.md)
      }

      ChatInputField(
        inputText: bridge.draftBinding,
        placeholder: bridge.placeholder,
        horizontalPadding: MonthPickerLayout.horizontalPadding,
        focusedHorizontalPadding: Spacing.xs,
        bottomPadding: MonthPickerLayout.bottomPadding,
        showsCameraShortcut: true,
        collapsesAttachmentButtonForLongDrafts: true,
        attachmentCollapseCharacterThreshold: attachmentCollapseCharacterThreshold,
        dismissKeyboardOnSend: false,
        onSend: { message in
          await bridge.send(content: message, image: nil)
        },
        onSendWithImage: { message, image in
          await bridge.send(content: message, image: image)
        },
        disabled: bridge.isThreadReadOnly
      )
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .bottom)
    .background(Color.tidexBackground)
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: FriendsThreadComposerHeightPreferenceKey.self,
          value: geometry.size.height
        )
      }
    )
    .onPreferenceChange(FriendsThreadComposerHeightPreferenceKey.self) { height in
      bridge.reportHeight(height)
    }
  }
}

private struct FriendsThreadComposerReplyBanner: View {
  let preview: FriendsChatReplyPreviewModel
  let onCancel: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      HStack(alignment: .top, spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
          .fill(Color.tidexBlue.opacity(0.7))
          .frame(width: 3, height: 30)

        VStack(alignment: .leading, spacing: 3) {
          Text(preview.senderName)
            .font(.tidexCaptionStrong)
            .foregroundColor(.tidexBlue)

          if preview.hasImageAttachment {
            Image(systemName: "photo")
              .font(.tidexCaptionRegular)
              .foregroundColor(.tidexTextMuted)
          }

          if let snippet = preview.snippet {
            Text(snippet)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfaceSecondary.opacity(0.72))
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
      )

      Button(action: onCancel) {
        Image(systemName: "xmark")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 32, height: 32)
          .background(
            Circle()
              .fill(Color.tidexSurfaceSecondary)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
    )
  }
}

private struct FriendsThreadComposerHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}
