import SwiftUI
import UIKit

struct FriendsThreadComposerConfiguration: Equatable {
  let draftText: String
  let replyPreview: FriendsChatReplyPreviewModel?
  let stagedAttachment: FriendsComposerAttachmentDraft?
  let isThreadReadOnly: Bool
  let sendErrorMessage: String?
  let placeholder: String
}

@MainActor
final class FriendsThreadComposerBridge: ObservableObject {
  @Published private(set) var draftText: String = ""
  @Published private(set) var replyPreview: FriendsChatReplyPreviewModel?
  @Published private(set) var stagedAttachment: FriendsComposerAttachmentDraft?
  @Published private(set) var isThreadReadOnly = false
  @Published private(set) var sendErrorMessage: String?
  @Published private(set) var placeholder: String = ""

  var onDraftChanged: ((String) -> Void)?
  var onStagedAttachmentChanged: ((FriendsComposerAttachmentDraft?) -> Void)?
  var onCancelReply: (() -> Void)?
  var onSend: ((String) async -> Bool)?
  var onHeightChanged: ((CGFloat) -> Void)?

  private var isApplyingExternalDraft = false
  private var isApplyingExternalAttachment = false

  var draftBinding: Binding<String> {
    Binding(
      get: { self.draftText },
      set: { [weak self] newValue in
        self?.updateDraftText(newValue)
      }
    )
  }

  var stagedImageBinding: Binding<ImageAttachment?> {
    Binding(
      get: { self.stagedAttachment?.imageAttachment },
      set: { [weak self] newValue in
        self?.updateStagedImage(newValue)
      }
    )
  }

  var hasSupplementalSendContent: Bool {
    stagedAttachment?.shiftSnapshot != nil
  }

  var allowsImageSelection: Bool {
    stagedAttachment == nil
  }

  func apply(configuration: FriendsThreadComposerConfiguration) {
    replyPreview = configuration.replyPreview
    isThreadReadOnly = configuration.isThreadReadOnly
    sendErrorMessage = configuration.sendErrorMessage
    placeholder = configuration.placeholder

    if draftText != configuration.draftText {
      isApplyingExternalDraft = true
      draftText = configuration.draftText
      isApplyingExternalDraft = false
    }

    if stagedAttachment != configuration.stagedAttachment {
      isApplyingExternalAttachment = true
      stagedAttachment = configuration.stagedAttachment
      isApplyingExternalAttachment = false
    }
  }

  func cancelReply() {
    onCancelReply?()
  }

  func send(content: String) async -> Bool {
    guard let onSend else { return false }
    return await onSend(content)
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

  func removeStagedAttachment() {
    updateStagedAttachment(nil)
  }

  private func updateStagedImage(_ newValue: ImageAttachment?) {
    updateStagedAttachment(newValue.map(FriendsComposerAttachmentDraft.image))
  }

  private func updateStagedAttachment(_ newValue: FriendsComposerAttachmentDraft?) {
    guard stagedAttachment != newValue else { return }
    stagedAttachment = newValue
    guard !isApplyingExternalAttachment else { return }
    onStagedAttachmentChanged?(newValue)
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

      if let stagedAttachment = bridge.stagedAttachment {
        FriendsThreadComposerAttachmentPreview(
          attachment: stagedAttachment,
          onRemove: bridge.removeStagedAttachment
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
        attachedImage: bridge.stagedImageBinding,
        showsImagePreview: false,
        hasSupplementalSendContent: bridge.hasSupplementalSendContent,
        showsAttachmentPicker: bridge.allowsImageSelection,
        collapsesAttachmentButtonForLongDrafts: true,
        attachmentCollapseCharacterThreshold: attachmentCollapseCharacterThreshold,
        dismissKeyboardOnSend: false,
        onSend: { message in
          await bridge.send(content: message)
        },
        onSendWithImage: { message, _ in
          await bridge.send(content: message)
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

private struct FriendsThreadComposerAttachmentPreview: View {
  let attachment: FriendsComposerAttachmentDraft
  let onRemove: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Group {
        switch attachment {
        case .image(let image):
          FriendsThreadComposerImageAttachmentCard(image: image)
        case .shiftSnapshot(let draft):
          ChatShiftSnapshotCard(snapshot: draft.snapshot, isCurrentUser: false)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onRemove) {
        Image(systemName: "xmark")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 32, height: 32)
          .background(
            Circle()
              .fill(Color.tidexSurfacePrimary.opacity(0.96))
          )
          .overlay(
            Circle()
              .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.friendsChatComposerRemoveAttachment))
      .padding(Spacing.xxxs)
    }
  }
}

private struct FriendsThreadComposerImageAttachmentCard: View {
  let image: ImageAttachment

  var body: some View {
    HStack(spacing: Spacing.sm) {
      if let uiImage = UIImage(data: image.data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: 72, height: 72)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(Color.tidexSurfaceSecondary)
          .frame(width: 72, height: 72)
          .overlay {
            Image(systemName: "photo")
              .font(.tidexTitle2)
              .foregroundColor(.tidexTextMuted)
          }
      }

      VStack(alignment: .leading, spacing: 4) {
        Text(.friendsChatPreviewImage)
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextPrimary)

        Text(ByteCountFormatter.string(fromByteCount: Int64(image.data.count), countStyle: .file))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.4), lineWidth: 1)
    )
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

          HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
            if let iconSystemName = preview.previewKind.friendsChatReplyIconSystemName {
              Image(systemName: iconSystemName)
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexTextMuted)
            }

            Text(preview.snippet)
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
