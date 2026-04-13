import ExyteChat
import ImageIO
import SwiftUI
import UIKit

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

enum FriendsChatMessageStatus: Equatable {
  case sending
  case delivered
  case read
  case failed
}

struct FriendsChatMessageRowContent: View {
  private static let minimumBubbleWidthForTimestamp: CGFloat = 92
  private static let reactionHorizontalOffset: CGFloat = 12
  private static let reactionVerticalOffset: CGFloat = 8
  private static let statusHorizontalOffset: CGFloat = 5
  private static let statusVerticalOffset: CGFloat = 5
  private static let avatarSize = AvatarView.Size.small

  let message: FriendMessage
  let quotedPreview: FriendsChatReplyPreviewModel?
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let counterpartAvatarUrl: String?
  let counterpartAvatarInitials: String
  let isHighlighted: Bool
  let visibleMessageText: String
  let senderFirstName: String?
  let separatorDate: Date?
  let showsSenderLabel: Bool
  let showsTimestamp: Bool
  let messageStatus: FriendsChatMessageStatus?
  let stackingOrder: Double
  let onRetry: () -> Void
  let onToggleReaction: (String) -> Void
  let onTapQuotedMessage: () -> Void
  let onOpenImageAttachment: (FriendMessageAttachment) -> Void
  let onOpenShiftSnapshot: (FriendShiftSnapshot) -> Void
  let messageFrame: Binding<CGRect>?

  var body: some View {
    let hasMessageText = !visibleMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let imageAttachments = message.attachments.filter { $0.kind == .image }
    let shiftSnapshot = message.shiftSnapshot
    let fallbackPreviewText = message.previewText
    let showsFallbackBubble =
      !hasMessageText && imageAttachments.isEmpty && shiftSnapshot == nil
      && fallbackPreviewText != nil
    let showsMetadataRow = inlineMetadataStatus != nil || message.editedAt != nil
    let topPadding = groupContext.joinsPrevious ? Spacing.micro : Spacing.xxs
    let bottomPadding =
      if showsMetadataRow {
        Spacing.xxxs
      } else if groupContext.joinsNext {
        Spacing.micro
      } else {
        Spacing.xxs
      }

    return VStack(spacing: Spacing.xs) {
      if let separatorDate {
        FriendsChatDateSeparator(date: separatorDate)
      }

      ChatMessageRow(
        isCurrentUser: isCurrentUser,
        minSpacer: Spacing.xxxl,
        spacing: Spacing.xxs,
        horizontalInset: Spacing.sm
      ) {
        HStack(alignment: .top, spacing: Spacing.xs) {
          if !isCurrentUser {
            avatarSlot
          }

          VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {
            if showsSenderLabel, let senderFirstName, !senderFirstName.isEmpty {
              Text(senderFirstName)
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexTextMuted)
                .padding(.horizontal, CornerRadius.bubble)
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xxs) {
              if !hasMessageText, let quotedPreview {
                FriendsChatMessageReplyPreview(
                  preview: quotedPreview,
                  isCurrentUser: isCurrentUser,
                  isHighlighted: false,
                  onTap: onTapQuotedMessage
                )
              }

              ForEach(Array(imageAttachments.enumerated()), id: \.element.id) {
                index, attachment in
                if attachment.kind == .image {
                  FriendsChatImageView(
                    attachment: attachment,
                    isCurrentUser: isCurrentUser,
                    onOpenImageAttachment: onOpenImageAttachment
                  )
                  .friendsChatMessageFrame(
                    !hasMessageText && shiftSnapshot == nil && index == imageAttachments.count - 1
                      ? messageFrame : nil
                  )
                  .overlay(alignment: reactionAlignment) {
                    if !hasMessageText, !showsFallbackBubble, shiftSnapshot == nil,
                      index == imageAttachments.count - 1
                    {
                      reactionStrip
                    }
                  }
                  .overlay(alignment: bubbleStatusAlignment) {
                    if !hasMessageText, !showsFallbackBubble, shiftSnapshot == nil,
                      index == imageAttachments.count - 1
                    {
                      bubbleEdgeStatusBadge
                    }
                  }
                }
              }

              if let shiftSnapshot {
                ChatShiftSnapshotCard(
                  snapshot: shiftSnapshot,
                  isCurrentUser: isCurrentUser,
                  onTap: {
                    onOpenShiftSnapshot(shiftSnapshot)
                  }
                )
                .friendsChatMessageFrame(
                  hasMessageText || !imageAttachments.isEmpty ? nil : messageFrame
                )
                .overlay(alignment: reactionAlignment) {
                  if !hasMessageText, imageAttachments.isEmpty {
                    reactionStrip
                  }
                }
                .overlay(alignment: bubbleStatusAlignment) {
                  if !hasMessageText, imageAttachments.isEmpty {
                    bubbleEdgeStatusBadge
                  }
                }
              }

              if showsFallbackBubble, let fallbackPreviewText {
                FriendsChatReactionAnchoredBubbleCard(
                  isCurrentUser: isCurrentUser,
                  groupContext: groupContext,
                  minWidth: Self.minimumBubbleWidthForTimestamp,
                  maxWidth: 280,
                  messageFrame: messageFrame
                ) {
                  Text(fallbackPreviewText)
                    .font(.tidexBody)
                    .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                } reaction: {
                  reactionStrip
                } status: {
                  bubbleEdgeStatusBadge
                }
              }

              if hasMessageText {
                FriendsChatReactionAnchoredBubbleCard(
                  isCurrentUser: isCurrentUser,
                  groupContext: groupContext,
                  minWidth: Self.minimumBubbleWidthForTimestamp,
                  maxWidth: 280,
                  messageFrame: messageFrame
                ) {
                  VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let quotedPreview {
                      FriendsChatMessageReplyPreview(
                        preview: quotedPreview,
                        isCurrentUser: isCurrentUser,
                        isHighlighted: false,
                        onTap: onTapQuotedMessage
                      )
                    }

                    Text(visibleMessageText)
                      .font(.tidexBody)
                      .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
                      .multilineTextAlignment(.leading)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                } reaction: {
                  reactionStrip
                } status: {
                  bubbleEdgeStatusBadge
                }
              }
            }

            if showsMetadataRow {
              HStack(spacing: Spacing.xxs) {
                if isCurrentUser {
                  if let inlineMetadataStatus {
                    statusView(inlineMetadataStatus)
                  }

                  if message.editedAt != nil {
                    Text(String(localized: "friends.chat.edited", table: "Localizable"))
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                  }

                } else {
                  if message.editedAt != nil {
                    Text(String(localized: "friends.chat.edited", table: "Localizable"))
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                  }

                  if let inlineMetadataStatus {
                    statusView(inlineMetadataStatus)
                  }
                }
              }
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
              .fixedSize(horizontal: true, vertical: false)
            }
          }
        }
      }
      .zIndex(bubbleEdgeBadgeStackingOrder)
      .padding(.top, topPadding)
      .padding(.bottom, bottomPadding)
      .background(
        Rectangle()
          .fill(isHighlighted ? Color.tidexBlue.opacity(0.12) : Color.clear)
      )
    }
  }

  @ViewBuilder
  private func statusView(_ messageStatus: FriendsChatMessageStatus) -> some View {
    switch messageStatus {
    case .sending:
      HStack(spacing: 3) {
        ProgressView()
          .controlSize(.mini)

        Text(.friendsChatStatusSending)
          .lineLimit(1)
          .minimumScaleFactor(0.9)
          .fixedSize(horizontal: true, vertical: false)
      }

    case .delivered:
      HStack(spacing: 0) {
        Image(systemName: "checkmark")
          .font(.system(size: 11, weight: .semibold))
      }

    case .read:
      HStack(spacing: 0) {
        Image(systemName: "eye.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.tidexBlue)
      }

    case .failed:
      HStack(spacing: 4) {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.tidexError)

        Text(.friendsChatStatusFailed)
          .foregroundColor(.tidexError)
          .lineLimit(1)
          .minimumScaleFactor(0.9)
          .fixedSize(horizontal: true, vertical: false)

        Button {
          onRetry()
        } label: {
          Text(.commonRetry)
            .foregroundColor(.tidexBlue)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var inlineMetadataStatus: FriendsChatMessageStatus? {
    guard let messageStatus else { return nil }
    switch messageStatus {
    case .failed:
      return .failed
    case .sending, .delivered, .read:
      return nil
    }
  }

  private var showsBubbleEdgeStatusBadge: Bool {
    guard isCurrentUser, let messageStatus else { return false }
    switch messageStatus {
    case .sending, .delivered, .read:
      return true
    case .failed:
      return false
    }
  }

  private var bubbleEdgeBadgeStackingOrder: Double {
    showsBubbleEdgeStatusBadge ? stackingOrder : 0
  }

  @ViewBuilder
  private var bubbleEdgeStatusBadge: some View {
    if isCurrentUser, let messageStatus {
      switch messageStatus {
      case .sending:
        ProgressView()
          .controlSize(.mini)
          .padding(6)
          .background(.ultraThinMaterial, in: Circle())
          .overlay(
            Circle()
              .stroke(Color.tidexBorderSubtle, lineWidth: 1)
          )
          .offset(x: -Self.statusHorizontalOffset, y: Self.statusVerticalOffset)
          .zIndex(2)

      case .delivered:
        Image(systemName: "checkmark")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(.tidexTextMuted)
          .padding(6)
          .background(.ultraThinMaterial, in: Circle())
          .overlay(
            Circle()
              .stroke(Color.tidexBorderSubtle, lineWidth: 1)
          )
          .offset(x: -Self.statusHorizontalOffset, y: Self.statusVerticalOffset)
          .zIndex(2)

      case .read:
        Image(systemName: "eye.fill")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(.tidexBlue)
          .padding(6)
          .background(.ultraThinMaterial, in: Circle())
          .overlay(
            Circle()
              .stroke(Color.tidexBorderSubtle, lineWidth: 1)
          )
          .offset(x: -Self.statusHorizontalOffset, y: Self.statusVerticalOffset)
          .zIndex(2)

      case .failed:
        EmptyView()
      }
    }
  }

  private var bubbleStatusAlignment: Alignment {
    isCurrentUser ? .bottomLeading : .bottomTrailing
  }

  @ViewBuilder
  private var reactionStrip: some View {
    if !message.reactions.isEmpty {
      HStack(spacing: Spacing.xxxs) {
        ForEach(message.reactions) { reaction in
          Button {
            onToggleReaction(reaction.emoji)
          } label: {
            HStack(spacing: 4) {
              FriendsChatEmojiGlyph(emoji: reaction.emoji, size: 22)

              if reaction.count > 1 {
                Text("\(reaction.count)")
                  .font(.tidexCaptionRegular)
                  .foregroundColor(.tidexTextSecondary)
              }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(!message.canReact)
        }
      }
      .offset(
        x: isCurrentUser ? -Self.reactionHorizontalOffset : Self.reactionHorizontalOffset,
        y: -Self.reactionVerticalOffset
      )
      .zIndex(2)
    }
  }

  private var reactionAlignment: Alignment {
    isCurrentUser ? .topLeading : .topTrailing
  }

  @ViewBuilder
  private var avatarSlot: some View {
    if groupContext.showsAvatar {
      AvatarView(
        url: counterpartAvatarUrl,
        initials: counterpartAvatarInitials,
        size: Self.avatarSize,
        cornerRadius: CornerRadius.md
      )
      .padding(.top, 2)
    } else {
      Color.clear
        .frame(width: Self.avatarSize, height: Self.avatarSize)
    }
  }
}

extension FriendLastMessagePreviewKind {
  var friendsChatReplyIconSystemName: String? {
    switch self {
    case .text:
      return nil
    case .image:
      return "photo"
    case .shiftSnapshot:
      return "calendar.badge.clock"
    case .unknown:
      return "questionmark.circle"
    }
  }
}

struct FriendsChatEmojiGlyph: View {
  let emoji: String
  let size: CGFloat

  var body: some View {
    Text(verbatim: emoji)
      .font(.custom("Apple Color Emoji", size: size))
      .lineLimit(1)
      .fixedSize()
      .minimumScaleFactor(1)
      .accessibilityLabel(Text(verbatim: emoji))
  }
}

extension FriendMessageAttachment {
  func friendsChatImageFrameSize(
    maxDimension: CGFloat = 220,
    minDimension: CGFloat = 120
  ) -> CGSize {
    guard
      let width,
      let height,
      width > 0,
      height > 0
    else {
      return CGSize(width: 180, height: 180)
    }

    let aspectRatio = CGFloat(width) / CGFloat(height)

    if aspectRatio >= 1 {
      let scaledHeight = max(minDimension, maxDimension / aspectRatio)
      return CGSize(width: maxDimension, height: min(maxDimension, scaledHeight))
    }

    let scaledWidth = max(minDimension, maxDimension * aspectRatio)
    return CGSize(width: min(maxDimension, scaledWidth), height: maxDimension)
  }
}

struct FriendsChatReactionAnchoredBubbleCard<Content: View, Reaction: View, Status: View>: View {
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  var minWidth: CGFloat? = nil
  var maxWidth: CGFloat? = nil
  let messageFrame: Binding<CGRect>?
  @ViewBuilder let content: () -> Content
  @ViewBuilder let reaction: () -> Reaction
  @ViewBuilder let status: () -> Status

  var body: some View {
    Group {
      if let minWidth, let maxWidth {
        bubbleBody
          .frame(
            minWidth: minWidth,
            maxWidth: maxWidth,
            alignment: isCurrentUser ? .trailing : .leading
          )
      } else if let maxWidth {
        bubbleBody
          .frame(maxWidth: maxWidth, alignment: isCurrentUser ? .trailing : .leading)
      } else if let minWidth {
        bubbleBody
          .frame(minWidth: minWidth, alignment: isCurrentUser ? .trailing : .leading)
      } else {
        bubbleBody
      }
    }
  }

  private var bubbleBody: some View {
    content()
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(
        bubbleShape
          .fill(isCurrentUser ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary)
      )
      .overlay(
        bubbleShape
          .stroke(
            isCurrentUser ? Color.clear : Color.tidexBorderSubtle,
            lineWidth: 1
          )
      )
      .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) {
        reaction()
      }
      .overlay(alignment: isCurrentUser ? .bottomLeading : .bottomTrailing) {
        status()
      }
      .friendsChatMessageFrame(messageFrame)
  }

  private var bubbleShape: some InsettableShape {
    UnevenRoundedRectangle(
      cornerRadii: RectangleCornerRadii(
        topLeading: topLeadingRadius,
        bottomLeading: bottomLeadingRadius,
        bottomTrailing: bottomTrailingRadius,
        topTrailing: topTrailingRadius
      ),
      style: .continuous
    )
  }

  private var topLeadingRadius: CGFloat {
    if !isCurrentUser && groupContext.joinsPrevious {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var bottomLeadingRadius: CGFloat {
    if !isCurrentUser && groupContext.joinsNext {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var bottomTrailingRadius: CGFloat {
    if isCurrentUser && groupContext.joinsNext {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var topTrailingRadius: CGFloat {
    if isCurrentUser && groupContext.joinsPrevious {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }
}

extension FriendsChatReactionAnchoredBubbleCard where Status == EmptyView {
  init(
    isCurrentUser: Bool,
    groupContext: FriendsChatMessageGroupContext,
    minWidth: CGFloat? = nil,
    maxWidth: CGFloat? = nil,
    messageFrame: Binding<CGRect>?,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder reaction: @escaping () -> Reaction
  ) {
    self.isCurrentUser = isCurrentUser
    self.groupContext = groupContext
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.messageFrame = messageFrame
    self.content = content
    self.reaction = reaction
    self.status = { EmptyView() }
  }
}

extension View {
  @ViewBuilder
  fileprivate func friendsChatMessageFrame(_ messageFrame: Binding<CGRect>?) -> some View {
    if let messageFrame {
      frameGetter(messageFrame)
    } else {
      self
    }
  }
}

private struct FriendsChatDateSeparator: View {
  let date: Date

  var body: some View {
    HStack(spacing: Spacing.sm) {
      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)

      Text(separatorText)
        .font(.tidexMicro)
        .foregroundColor(.tidexTextMuted)
        .fixedSize(horizontal: true, vertical: false)

      Rectangle()
        .fill(Color.tidexBorderSubtle)
        .frame(height: 1)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xs)
  }

  private var separatorText: String {
    let calendar = Calendar.current
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

private struct FriendsChatMessageReplyPreview: View {
  let preview: FriendsChatReplyPreviewModel
  let isCurrentUser: Bool
  let isHighlighted: Bool
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

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .fill(replyBackgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(borderColor, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var replyBackgroundColor: Color {
    if isCurrentUser {
      return isHighlighted ? Color.black.opacity(0.24) : Color.black.opacity(0.18)
    }
    return isHighlighted ? Color.tidexBlue.opacity(0.08) : Color.tidexSurfaceSecondary.opacity(0.72)
  }

  private var textColor: Color {
    if isCurrentUser {
      return Color.tidexTextOnBrand.opacity(0.88)
    }
    return .tidexTextMuted
  }

  private var accentColor: Color {
    if isCurrentUser {
      return Color.white.opacity(0.78)
    }
    return Color.tidexBlue.opacity(0.7)
  }

  private var borderColor: Color {
    if isCurrentUser {
      return isHighlighted ? Color.white.opacity(0.32) : Color.white.opacity(0.18)
    }
    return isHighlighted ? Color.tidexBlue.opacity(0.45) : Color.tidexBorder.opacity(0.4)
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
              .frame(maxWidth: .infinity, alignment: .leading)
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
            .foregroundColor(textColor)
        }

        snippetLabel(preview.snippet)
      }
    }
  }

  private var senderNameLabel: some View {
    Text(preview.senderName)
      .font(.tidexCaptionStrong)
      .foregroundColor(accentColor)
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
      .foregroundColor(textColor)
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
                  .foregroundColor(.white)
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

struct ChatShiftSnapshotCard: View {
  let snapshot: FriendShiftSnapshot
  let isCurrentUser: Bool
  var onTap: (() -> Void)? = nil
  @State private var tapSuppressedUntil: Date?

  private var ownerPrimaryTextColor: Color {
    .tidexTextMuted
  }

  @ViewBuilder
  var body: some View {
    if let onTap {
      cardContent
        .contentShape(Rectangle())
        .onLongPressGesture(
          minimumDuration: FriendsThreadAttachmentTapGuard.messageMenuRecognitionDuration,
          maximumDistance: 20,
          perform: {
            tapSuppressedUntil =
              FriendsThreadAttachmentTapGuard.suppressedUntilAfterMenuRecognition()
          },
          onPressingChanged: { _ in }
        )
        .onTapGesture {
          guard
            FriendsThreadAttachmentTapGuard.shouldHandleTap(
              suppressedUntil: tapSuppressedUntil
            )
          else {
            return
          }
          onTap()
        }
    } else {
      cardContent
    }
  }

  private var cardContent: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(alignment: .center, spacing: Spacing.xs) {
        AvatarView(
          url: snapshot.ownerAvatarUrl,
          initials: snapshot.ownerInitials,
          size: AvatarView.Size.small,
          cornerRadius: CornerRadius.sm
        )

        Text(snapshot.ownerFirstName)
          .font(.tidexCaptionStrong)
          .foregroundColor(ownerPrimaryTextColor)
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)

      SharedShiftRow(
        shift: snapshot.renderableShift,
        isToday: snapshot.shiftDate == todayISO(),
        showEarnings: snapshot.includesEarnings,
        currency: snapshot.currency
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct FriendsChatImageView: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let onOpenImageAttachment: (FriendMessageAttachment) -> Void

  var body: some View {
    FriendsChatImageAttachmentCard(
      attachment: attachment,
      isCurrentUser: isCurrentUser
    ) {
      onOpenImageAttachment(attachment)
    }
  }
}

@MainActor
final class FriendsChatImageLoader: ObservableObject {
  enum Variant {
    case original
    case display(pixelSize: CGSize)
  }

  @Published private(set) var image: UIImage?
  @Published private(set) var isLoading = false

  private let variant: Variant

  init(initialImage: UIImage? = nil, variant: Variant = .original) {
    image = initialImage
    self.variant = variant
  }

  func loadIfNeeded(attachment: FriendMessageAttachment) async {
    if let image {
      self.image = image
      return
    }

    let cacheURL = Self.cacheURL(for: attachment.storagePath, variant: variant)

    if let cached = ImageCache.shared.get(for: cacheURL) {
      image = cached
      return
    }

    if let cached = await ImageCache.shared.getFromDisk(for: cacheURL) {
      image = cached
      return
    }

    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let data = try await FriendsMessagingService.shared.downloadAttachmentData(
        path: attachment.storagePath
      )
      guard let loadedImage = await Self.decodeImage(from: data, variant: variant) else { return }
      ImageCache.shared.set(loadedImage, for: cacheURL)
      image = loadedImage
    } catch {
      image = nil
    }
  }

  nonisolated static func cacheURL(for storagePath: String, variant: Variant = .original) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    switch variant {
    case .original:
      break
    case .display(let pixelSize):
      let width = Int(pixelSize.width.rounded())
      let height = Int(pixelSize.height.rounded())
      components.queryItems = [
        URLQueryItem(name: "variant", value: "display"),
        URLQueryItem(name: "w", value: "\(width)"),
        URLQueryItem(name: "h", value: "\(height)"),
      ]
    }
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  nonisolated private static func decodeImage(from data: Data, variant: Variant) async -> UIImage? {
    await Task.detached(priority: .utility) {
      autoreleasepool {
        switch variant {
        case .original:
          UIImage(data: data)
        case .display(let pixelSize):
          downsampleImage(from: data, pixelSize: pixelSize)
        }
      }
    }.value
  }

  nonisolated private static func downsampleImage(from data: Data, pixelSize: CGSize) -> UIImage? {
    let maxPixelSize = max(pixelSize.width, pixelSize.height)
    guard maxPixelSize > 0 else { return UIImage(data: data) }
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
      return UIImage(data: data)
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    else {
      return UIImage(data: data)
    }

    return UIImage(cgImage: cgImage)
  }
}

struct FriendsChatImageAttachmentCard: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let displaySize: CGSize?
  let cornerRadius: CGFloat
  let placeholderSymbolSize: CGFloat
  var onTap: (() -> Void)? = nil

  @StateObject private var loader: FriendsChatImageLoader

  init(
    attachment: FriendMessageAttachment,
    isCurrentUser: Bool,
    displaySize: CGSize? = nil,
    cornerRadius: CGFloat = CornerRadius.lg,
    placeholderSymbolSize: CGFloat = 22,
    onTap: (() -> Void)? = nil
  ) {
    self.attachment = attachment
    self.isCurrentUser = isCurrentUser
    self.displaySize = displaySize
    self.cornerRadius = cornerRadius
    self.placeholderSymbolSize = placeholderSymbolSize
    self.onTap = onTap
    let resolvedDisplaySize = displaySize ?? attachment.friendsChatImageFrameSize()
    let displayScale = UITraitCollection.current.displayScale
    let pixelSize = CGSize(
      width: resolvedDisplaySize.width * displayScale,
      height: resolvedDisplaySize.height * displayScale
    )
    let variant = FriendsChatImageLoader.Variant.display(pixelSize: pixelSize)
    let cacheURL = FriendsChatImageLoader.cacheURL(for: attachment.storagePath, variant: variant)
    let initialImage = ImageCache.shared.get(for: cacheURL)
    _loader = StateObject(
      wrappedValue: FriendsChatImageLoader(initialImage: initialImage, variant: variant)
    )
  }

  var body: some View {
    Group {
      if let image = loader.image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: imageFrameSize.width, height: imageFrameSize.height)
          .clipShape(imageShape)
          .overlay {
            imageShape
              .strokeBorder(
                isCurrentUser ? Color.white.opacity(0.2) : Color.tidexBorder,
                lineWidth: 1
              )
          }
          .contentShape(imageShape)
          .onTapGesture {
            onTap?()
          }
      } else if loader.isLoading {
        placeholder {
          ProgressView()
        }
      } else {
        placeholder {
          Image(systemName: "photo")
            .font(.system(size: placeholderSymbolSize, weight: .medium))
            .foregroundColor(.tidexTextMuted)
        }
      }
    }
    .task(id: attachment.id) {
      await loader.loadIfNeeded(attachment: attachment)
    }
  }

  private var imageFrameSize: CGSize {
    displaySize ?? attachment.friendsChatImageFrameSize()
  }

  private var imageShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }

  @ViewBuilder
  private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    imageShape
      .fill(Color.tidexSurfacePrimary)
      .frame(width: imageFrameSize.width, height: imageFrameSize.height)
      .overlay {
        content()
      }
      .overlay {
        imageShape
          .strokeBorder(
            isCurrentUser ? Color.white.opacity(0.2) : Color.tidexBorder,
            lineWidth: 1
          )
      }
  }
}

struct FriendsChatImageGalleryOverlay: View {
  let attachments: [FriendMessageAttachment]
  let initialAttachmentID: String
  let onDismiss: () -> Void
  let onSaveImage: (UIImage) -> Void

  @State private var selectedAttachmentID: String
  @State private var loadedImagesByAttachmentID: [String: UIImage] = [:]
  @State private var selectedPageIsZoomed = false
  @GestureState private var dismissTranslationY: CGFloat = 0

  private let galleryDismissThreshold: CGFloat = 120

  init(
    attachments: [FriendMessageAttachment],
    initialAttachmentID: String,
    onDismiss: @escaping () -> Void,
    onSaveImage: @escaping (UIImage) -> Void
  ) {
    self.attachments = attachments
    self.initialAttachmentID = initialAttachmentID
    self.onDismiss = onDismiss
    self.onSaveImage = onSaveImage
    _selectedAttachmentID = State(initialValue: initialAttachmentID)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      TabView(selection: $selectedAttachmentID) {
        ForEach(attachments) { attachment in
          FriendsChatImageGalleryPage(
            attachment: attachment,
            isSelected: attachment.id == selectedAttachmentID,
            onImageLoaded: { image in
              loadedImagesByAttachmentID[attachment.id] = image
            },
            onZoomStateChanged: { isZoomed in
              if attachment.id == selectedAttachmentID {
                selectedPageIsZoomed = isZoomed
              }
            }
          )
          .tag(attachment.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .offset(y: currentDismissOffsetY)

      VStack {
        topBar
          .padding(.horizontal, Spacing.mlg)
          .padding(.top, Spacing.mlg)
        Spacer()
        pageIndicator
          .padding(.bottom, Spacing.xl)
      }
    }
    .simultaneousGesture(verticalDismissGesture)
    .onChange(of: selectedAttachmentID) { _, _ in
      selectedPageIsZoomed = false
    }
    .statusBarHidden()
  }

  private var topBar: some View {
    HStack {
      if let selectedImage {
        Button {
          onSaveImage(selectedImage)
        } label: {
          Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 30))
            .foregroundColor(.white.opacity(0.88))
            .frame(width: 44, height: 44)
            .background(
              Circle()
                .fill(Color.black.opacity(0.32))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          Text(String(localized: "friends.chat.action.save_image", table: "Localizable"))
        )
      }

      Spacer()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 30))
          .foregroundColor(.white.opacity(0.88))
          .frame(width: 44, height: 44)
          .background(
            Circle()
              .fill(Color.black.opacity(0.32))
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
    }
    .padding(.vertical, Spacing.xs)
  }

  @ViewBuilder
  private var pageIndicator: some View {
    if let selectedIndex, attachments.count > 1 {
      Text("\(selectedIndex + 1) / \(attachments.count)")
        .font(.tidexFootnoteMedium)
        .foregroundColor(.white.opacity(0.88))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
          Capsule(style: .continuous)
            .fill(Color.black.opacity(0.35))
        )
        .allowsHitTesting(false)
    }
  }

  private var selectedImage: UIImage? {
    loadedImagesByAttachmentID[selectedAttachmentID]
  }

  private var selectedIndex: Int? {
    attachments.firstIndex(where: { $0.id == selectedAttachmentID })
  }

  private var currentDismissOffsetY: CGFloat {
    guard !selectedPageIsZoomed else { return 0 }
    return max(0, dismissTranslationY)
  }

  private var verticalDismissGesture: some Gesture {
    DragGesture(minimumDistance: 12)
      .updating($dismissTranslationY) { value, state, _ in
        guard !selectedPageIsZoomed else { return }

        let horizontal = abs(value.translation.width)
        let vertical = value.translation.height

        guard vertical > 0, vertical > horizontal else { return }
        state = vertical
      }
      .onEnded { value in
        guard !selectedPageIsZoomed else { return }

        let horizontal = abs(value.translation.width)
        let vertical = value.translation.height

        guard vertical > 0, vertical > horizontal else { return }

        if vertical >= galleryDismissThreshold {
          onDismiss()
        }
      }
  }
}

struct FriendsChatImageGalleryUnavailableOverlay: View {
  let onDismiss: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 30))
          .foregroundColor(.white.opacity(0.88))
          .frame(width: 44, height: 44)
          .background(
            Circle()
              .fill(Color.black.opacity(0.32))
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: .commonCancel)))
      .padding(.top, Spacing.mlg)
      .padding(.horizontal, Spacing.mlg)
    }
    .task {
      await MainActor.run {
        onDismiss()
      }
    }
    .statusBarHidden()
  }
}

private struct FriendsChatImageGalleryPage: View {
  let attachment: FriendMessageAttachment
  let isSelected: Bool
  let onImageLoaded: (UIImage) -> Void
  let onZoomStateChanged: (Bool) -> Void

  @StateObject private var loader: FriendsChatImageLoader

  init(
    attachment: FriendMessageAttachment,
    isSelected: Bool,
    onImageLoaded: @escaping (UIImage) -> Void,
    onZoomStateChanged: @escaping (Bool) -> Void
  ) {
    self.attachment = attachment
    self.isSelected = isSelected
    self.onImageLoaded = onImageLoaded
    self.onZoomStateChanged = onZoomStateChanged
    let cacheURL = FriendsChatImageLoader.cacheURL(for: attachment.storagePath)
    let initialImage = ImageCache.shared.get(for: cacheURL)
    _loader = StateObject(
      wrappedValue: FriendsChatImageLoader(initialImage: initialImage, variant: .original)
    )
  }

  var body: some View {
    ZStack {
      if let image = loader.image {
        FriendsChatZoomableImageView(
          image: image,
          isActive: isSelected,
          onZoomStateChanged: onZoomStateChanged
        )
      } else if loader.isLoading {
        ProgressView()
          .tint(.white.opacity(0.8))
      } else {
        Image(systemName: "photo")
          .font(.system(size: 28, weight: .medium))
          .foregroundColor(.white.opacity(0.6))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .task(id: attachment.id) {
      await loader.loadIfNeeded(attachment: attachment)
      if let image = loader.image {
        onImageLoaded(image)
      }
    }
    .onChange(of: loader.image) { _, newImage in
      guard let newImage else { return }
      onImageLoaded(newImage)
    }
    .onChange(of: isSelected) { _, newValue in
      if !newValue {
        onZoomStateChanged(false)
      }
    }
  }
}

private struct FriendsChatZoomableImageView: UIViewRepresentable {
  let image: UIImage
  let isActive: Bool
  let onZoomStateChanged: (Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onZoomStateChanged: onZoomStateChanged)
  }

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.delegate = context.coordinator
    scrollView.backgroundColor = .clear
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.bouncesZoom = true
    scrollView.decelerationRate = .fast
    scrollView.minimumZoomScale = 1
    scrollView.maximumZoomScale = 4
    scrollView.isScrollEnabled = false

    let imageView = context.coordinator.imageView
    imageView.image = image
    imageView.contentMode = .scaleAspectFit
    imageView.frame = scrollView.bounds
    imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    scrollView.addSubview(imageView)

    let doubleTapRecognizer = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleDoubleTap(_:))
    )
    doubleTapRecognizer.numberOfTapsRequired = 2
    scrollView.addGestureRecognizer(doubleTapRecognizer)
    context.coordinator.scrollView = scrollView

    return scrollView
  }

  func updateUIView(_ scrollView: UIScrollView, context: Context) {
    context.coordinator.onZoomStateChanged = onZoomStateChanged
    context.coordinator.imageView.image = image
    context.coordinator.imageView.frame = scrollView.bounds
    context.coordinator.updateInsets(for: scrollView)

    if !isActive, scrollView.zoomScale > scrollView.minimumZoomScale {
      scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
      scrollView.contentOffset = .zero
      scrollView.isScrollEnabled = false
      onZoomStateChanged(false)
    }
  }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    let imageView = UIImageView()
    weak var scrollView: UIScrollView?
    var onZoomStateChanged: (Bool) -> Void

    init(onZoomStateChanged: @escaping (Bool) -> Void) {
      self.onZoomStateChanged = onZoomStateChanged
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
      imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
      scrollView.isScrollEnabled = isZoomed
      updateInsets(for: scrollView)
      onZoomStateChanged(isZoomed)
    }

    func scrollViewDidEndZooming(
      _ scrollView: UIScrollView,
      with _: UIView?,
      atScale scale: CGFloat
    ) {
      let isZoomed = scale > scrollView.minimumZoomScale + 0.01
      scrollView.isScrollEnabled = isZoomed
      onZoomStateChanged(isZoomed)
    }

    @objc
    func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
      guard let scrollView else { return }

      if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        scrollView.isScrollEnabled = false
        onZoomStateChanged(false)
        return
      }

      let tapPoint = recognizer.location(in: imageView)
      let zoomScale = min(scrollView.maximumZoomScale, 2)
      let width = scrollView.bounds.size.width / zoomScale
      let height = scrollView.bounds.size.height / zoomScale
      let zoomRect = CGRect(
        x: tapPoint.x - (width / 2),
        y: tapPoint.y - (height / 2),
        width: width,
        height: height
      )
      scrollView.zoom(to: zoomRect, animated: true)
      scrollView.isScrollEnabled = true
      onZoomStateChanged(true)
    }

    func updateInsets(for scrollView: UIScrollView) {
      let horizontalInset = max((scrollView.bounds.width - imageView.frame.width) / 2, 0)
      let verticalInset = max((scrollView.bounds.height - imageView.frame.height) / 2, 0)
      scrollView.contentInset = UIEdgeInsets(
        top: verticalInset,
        left: horizontalInset,
        bottom: verticalInset,
        right: horizontalInset
      )
    }
  }
}
