import ExyteChat
import ImageIO
import SwiftUI
import UIKit

struct FriendsChatDateSeparator: View {
  let date: Date

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Rectangle()
        .fill(Color.tidexSeparator)
        .frame(height: 1)

      Text(separatorText)
        .font(.tidexMicro)
        .foregroundStyle(Color.tidexTextMuted)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)

      Rectangle()
        .fill(Color.tidexSeparator)
        .frame(height: 1)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
  }

  private var separatorText: String {
    let calendar: Calendar = Calendar.gregorianCurrent
    if calendar.isDateInToday(date) {
      return String(localized: .commonToday)
    }
    if calendar.isDateInYesterday(date) {
      return String(localized: .commonYesterday)
    }

    if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
      return date.formatted(
        .dateTime
          .weekday(.wide)
          .day()
          .month(.wide)
      )
    }

    return date.formatted(
      .dateTime
        .weekday(.wide)
        .day()
        .month(.wide)
        .year()
    )
  }
}

struct FriendsChatMessageReplyPreview: View {
  let preview: FriendsChatReplyPreviewModel
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let isHighlighted: Bool
  var maxWidth: CGFloat?
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(alignment: .top, spacing: Spacing.xs) {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
          .fill(accentColor)
          .frame(width: 3)

        FriendsChatReplyPreviewContent(
          preview: preview,
          isCurrentUser: isCurrentUser,
          accentColor: accentColor,
          textColor: textColor,
          snippetLineLimit: 2,
          thumbnailSize: CGSize(width: 56, height: 56),
          hidesImageOnlySnippet: true
        )
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .fixedSize(horizontal: false, vertical: true)
      .background(
        replyShape
          .fill(replyBackgroundColor)
      )
      .overlay(
        replyShape
          .stroke(borderColor, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .frame(maxWidth: maxWidth, alignment: isCurrentUser ? .trailing : .leading)
    .accessibilityLabel(
      FriendsChatMessageAccessibility.join([
        "\(String(localized: .friendsChatReplyTo)) \(preview.senderName)", preview.snippet,
      ])
    )
    .accessibilityHint(Text(.friendsAccessibilityOpenRepliedMessage))
  }

  private var replyBackgroundColor: Color {
    if isCurrentUser {
      return isHighlighted ? Color.black.opacity(0.24) : Color.black.opacity(0.18)
    }
    return isHighlighted ? Color.tidexBlue.opacity(0.08) : Color.tidexSurfaceSecondary.opacity(0.72)
  }

  private var textColor: Color {
    if isCurrentUser {
      return Color.tidexTextOnBrand
    }
    return .tidexTextMuted
  }

  private var accentColor: Color {
    if isCurrentUser {
      return Color.tidexTextOnBrand
    }
    return Color.tidexBlueText
  }

  private var borderColor: Color {
    if isCurrentUser {
      return isHighlighted ? Color.white.opacity(0.32) : Color.white.opacity(0.18)
    }
    return isHighlighted ? Color.tidexBlue.opacity(0.45) : Color.tidexBorder.opacity(0.4)
  }

  private var replyShape: UnevenRoundedRectangle {
    FriendsChatMessageBubbleShapeResolver.shape(for: groupContext)
  }
}

struct FriendsChatReplyPreviewContent: View {
  enum ImageLayout {
    case thumbnailThenSnippet
  }

  let preview: FriendsChatReplyPreviewModel
  let isCurrentUser: Bool
  let accentColor: Color
  let textColor: Color
  let snippetLineLimit: Int
  let thumbnailSize: CGSize
  var imageLayout: ImageLayout = .thumbnailThenSnippet
  var hidesImageOnlySnippet = false

  var body: some View {
    Group {
      if !preview.imageAttachments.isEmpty {
        imageContent
      } else {
        textOnlyContent
      }
    }
  }

  private var imageContent: some View {
    switch imageLayout {
    case .thumbnailThenSnippet:
      VStack(alignment: .leading, spacing: 3) {
        senderNameLabel

        HStack(alignment: .top, spacing: Spacing.xs) {
          imageThumbnails

          if let snippetText {
            snippetLabel(snippetText)
          }
        }
      }
    }
  }

  private var textOnlyContent: some View {
    VStack(alignment: .leading, spacing: 3) {
      senderNameLabel

      HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
        if let iconSystemName = preview.iconPreviewKind?.friendsChatReplyIconSystemName {
          Image(systemName: iconSystemName)
            .font(.tidexCaptionRegular)
            .foregroundStyle(textColor)
            .accessibilityHidden(true)
        }

        snippetLabel(preview.snippet)
      }
    }
  }

  private var senderNameLabel: some View {
    Text(preview.senderName)
      .font(.tidexCaptionStrong)
      .foregroundStyle(accentColor)
  }

  private var snippetText: String? {
    if hidesImageOnlySnippet, preview.previewKind == .image {
      return nil
    }

    return preview.snippet
  }

  private func snippetLabel(_ text: String) -> some View {
    Text(text)
      .font(.tidexFootnote)
      .foregroundStyle(textColor)
      .multilineTextAlignment(.leading)
      .lineLimit(snippetLineLimit)
  }

  private var displayedImageAttachments: ArraySlice<FriendMessageAttachment> {
    preview.imageAttachments.prefix(3)
  }

  private var overflowImageCount: Int {
    max(0, preview.imageAttachments.count - displayedImageAttachments.count)
  }

  private var multiThumbnailSize: CGSize {
    CGSize(
      width: min(thumbnailSize.width, 34),
      height: min(thumbnailSize.height, 34)
    )
  }

  private var imageThumbnails: some View {
    HStack(spacing: Spacing.xxxs) {
      ForEach(Array(displayedImageAttachments.enumerated()), id: \.element.id) {
        index, attachment in
        thumbnail(
          for: attachment,
          size: preview.imageAttachments.count > 1 ? multiThumbnailSize : thumbnailSize
        )
        .overlay {
          if overflowImageCount > 0, index == displayedImageAttachments.count - 1 {
            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
              .fill(Color.black.opacity(0.45))
              .overlay {
                Text("+\(overflowImageCount)")
                  .font(.tidexCaptionStrong)
                  .foregroundStyle(Color.white)
              }
          }
        }
      }
    }
    .accessibilityHidden(true)
  }

  private func thumbnail(
    for imageAttachment: FriendMessageAttachment,
    size: CGSize
  ) -> some View {
    FriendsChatImageAttachmentCard(
      attachment: imageAttachment,
      isCurrentUser: isCurrentUser,
      displaySize: size,
      cornerRadius: CornerRadius.md,
      placeholderSymbolSize: 14
    )
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct FriendsChatReplyPreviewModel: Equatable {
  let senderName: String
  let previewKind: FriendLastMessagePreviewKind
  let iconPreviewKind: FriendLastMessagePreviewKind?
  let snippet: String
  let imageAttachments: [FriendMessageAttachment]

  init(senderName: String, message: FriendMessage) {
    self.senderName = senderName
    previewKind = message.previewKind
    iconPreviewKind = message.replyIconPreviewKind
    snippet = message.previewText ?? String(localized: .friendsChatPreviewUnsupported)
    imageAttachments = message.attachments
      .filter { $0.kind == .image }
      .sorted { $0.attachmentIndex < $1.attachmentIndex }
  }
}