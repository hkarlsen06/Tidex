import SwiftUI
import UIKit

struct FriendsChatReplyPreviewModel: Equatable {
  let senderName: String
  let previewKind: FriendLastMessagePreviewKind
  let iconPreviewKind: FriendLastMessagePreviewKind?
  let snippet: String

  init(senderName: String, message: FriendMessage) {
    self.senderName = senderName
    previewKind = message.previewKind
    iconPreviewKind = message.replyIconPreviewKind
    snippet = message.previewText ?? String(localized: .friendsChatPreviewUnsupported)
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
  private static let avatarSize = AvatarView.Size.small

  let message: FriendMessage
  let quotedPreview: FriendsChatReplyPreviewModel?
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let counterpartAvatarUrl: String?
  let counterpartAvatarInitials: String
  let isHighlighted: Bool
  let senderFirstName: String?
  let separatorDate: Date?
  let showsSenderLabel: Bool
  let showsTimestamp: Bool
  let messageStatus: FriendsChatMessageStatus?
  let onReply: () -> Void
  let onRetry: () -> Void
  let onToggleReaction: (String) -> Void
  let onTapQuotedMessage: () -> Void

  var body: some View {
    let messageText = message.body?.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasMessageText = !(messageText?.isEmpty ?? true)
    let imageAttachments = message.attachments.filter { $0.kind == .image }
    let shiftSnapshot = message.shiftSnapshot
    let fallbackPreviewText = message.previewText
    let showsFallbackBubble =
      !hasMessageText && imageAttachments.isEmpty && shiftSnapshot == nil
      && fallbackPreviewText != nil
    let showsMetadataRow = showsTimestamp || messageStatus != nil || message.editedAt != nil
    let topPadding =
      message.reactions.isEmpty
      ? (groupContext.joinsPrevious ? Spacing.micro : Spacing.xxs)
      : Spacing.md
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

            FriendsChatReplySwipeContainer(
              isCurrentUser: isCurrentUser,
              isEnabled: message.messageType == .user && message.deletedAt == nil,
              onReply: onReply
            ) {
              VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xxs) {
                if !hasMessageText, let quotedPreview {
                  FriendsChatMessageReplyPreview(
                    preview: quotedPreview,
                    isCurrentUser: isCurrentUser,
                    isHighlighted: false,
                    onTap: onTapQuotedMessage
                  )
                  .friendsChatFocusedBackground(
                    isHighlighted: false,
                    cornerRadius: CornerRadius.lg
                  )
                }

                ForEach(Array(imageAttachments.enumerated()), id: \.element.id) {
                  index, attachment in
                  if attachment.kind == .image {
                    FriendsChatImageView(
                      attachment: attachment,
                      isCurrentUser: isCurrentUser,
                      isHighlighted: isHighlighted
                    )
                    .overlay(alignment: reactionAlignment) {
                      if !hasMessageText, !showsFallbackBubble, shiftSnapshot == nil,
                        index == imageAttachments.count - 1
                      {
                        reactionStrip
                      }
                    }
                  }
                }

                if let shiftSnapshot {
                  ChatShiftSnapshotCard(
                    snapshot: shiftSnapshot,
                    isCurrentUser: isCurrentUser,
                    isHighlighted: isHighlighted
                  )
                  .overlay(alignment: reactionAlignment) {
                    if !hasMessageText, imageAttachments.isEmpty {
                      reactionStrip
                    }
                  }
                }

                if showsFallbackBubble, let fallbackPreviewText {
                  FriendsChatReactionAnchoredBubbleCard(
                    isCurrentUser: isCurrentUser,
                    groupContext: groupContext,
                    isHighlighted: isHighlighted,
                    minWidth: Self.minimumBubbleWidthForTimestamp,
                    maxWidth: 280
                  ) {
                    Text(fallbackPreviewText)
                      .font(.tidexBody)
                      .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
                      .multilineTextAlignment(.leading)
                      .fixedSize(horizontal: false, vertical: true)
                  } reaction: {
                    reactionStrip
                  }
                }

                if let messageText, !messageText.isEmpty {
                  FriendsChatReactionAnchoredBubbleCard(
                    isCurrentUser: isCurrentUser,
                    groupContext: groupContext,
                    isHighlighted: isHighlighted,
                    minWidth: Self.minimumBubbleWidthForTimestamp,
                    maxWidth: 280
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

                      Text(messageText)
                        .font(.tidexBody)
                        .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                  } reaction: {
                    reactionStrip
                  }
                }
              }
            }

            if showsMetadataRow {
              HStack(spacing: Spacing.xxs) {
                if isCurrentUser {
                  if let messageStatus {
                    statusView(messageStatus)
                  }

                  if message.editedAt != nil {
                    Text(String(localized: "friends.chat.edited", table: "Localizable"))
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                  }

                  if showsTimestamp {
                    Text(message.createdAt.formatted(.dateTime.hour().minute()))
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                  }
                } else {
                  if message.editedAt != nil {
                    Text(String(localized: "friends.chat.edited", table: "Localizable"))
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                  }

                  if showsTimestamp {
                    Text(message.createdAt.formatted(.dateTime.hour().minute()))
                      .lineLimit(1)
                      .fixedSize(horizontal: true, vertical: false)
                  }

                  if let messageStatus {
                    statusView(messageStatus)
                  }
                }
              }
              .font(.tidexMicro)
              .foregroundColor(.tidexTextMuted)
              .fixedSize(horizontal: true, vertical: false)
              .animation(.easeInOut(duration: 0.2), value: messageStatus)
            }
          }
        }
      }
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
          .transition(.offset(x: -6).combined(with: .opacity))
      }

    case .read:
      HStack(spacing: 0) {
        Image(systemName: "eye.fill")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.tidexBlue)
          .transition(.offset(x: -6).combined(with: .opacity))
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

private struct FriendsChatReplySwipeContainer<Content: View>: View {
  let isCurrentUser: Bool
  let isEnabled: Bool
  let onReply: () -> Void
  @ViewBuilder let content: () -> Content

  @GestureState private var dragTranslation: CGFloat = 0

  private let horizontalDominanceRatio: CGFloat = 1.75

  private var activationDistance: CGFloat { Spacing.huge + Spacing.md }
  private var recognitionDistance: CGFloat { Spacing.mlg + Spacing.micro }
  private var indicatorSize: CGFloat { Spacing.xl }
  private var indicatorHorizontalInset: CGFloat { Spacing.xs }
  private var indicatorFontSize: CGFloat { Spacing.iconSizeSmall }
  private var visualTravelLimit: CGFloat { Spacing.xxl }

  var body: some View {
    if isEnabled {
      content()
        .offset(x: limitedVisualOffset)
        .overlay(alignment: isCurrentUser ? .trailing : .leading) {
          replyIndicator
            .padding(.horizontal, indicatorHorizontalInset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(replyGesture)
        .animation(.easeOut(duration: 0.16), value: limitedVisualOffset)
    } else {
      content()
    }
  }

  private var directionalTranslation: CGFloat {
    if isCurrentUser {
      return max(0, -dragTranslation)
    }
    return max(0, dragTranslation)
  }

  private var limitedVisualOffset: CGFloat {
    let offset = min(directionalTranslation, visualTravelLimit)
    return isCurrentUser ? -offset : offset
  }

  private var replyIndicator: some View {
    Image(systemName: "arrowshape.turn.up.left.fill")
      .font(.system(size: indicatorFontSize, weight: .semibold))
      .foregroundColor(.tidexBlue)
      .frame(width: indicatorSize, height: indicatorSize)
      .background(
        Circle()
          .fill(Color.tidexBlue.opacity(0.14))
      )
      .opacity(min(directionalTranslation / activationDistance, 1))
      .scaleEffect(0.85 + (min(directionalTranslation / activationDistance, 1) * 0.15))
  }

  private var replyGesture: some Gesture {
    DragGesture(minimumDistance: recognitionDistance, coordinateSpace: .local)
      .updating($dragTranslation) { value, state, _ in
        let horizontalTravel = abs(value.translation.width)
        let verticalTravel = abs(value.translation.height)
        guard horizontalTravel >= recognitionDistance,
          horizontalTravel > verticalTravel * horizontalDominanceRatio
        else {
          state = 0
          return
        }
        state = value.translation.width
      }
      .onEnded { value in
        let horizontalTravel = abs(value.translation.width)
        let verticalTravel = abs(value.translation.height)
        guard horizontalTravel >= recognitionDistance,
          horizontalTravel > verticalTravel * horizontalDominanceRatio
        else { return }

        let directionalTravel = isCurrentUser ? -value.translation.width : value.translation.width
        guard directionalTravel >= activationDistance else { return }

        Haptics.play(.medium)
        onReply()
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

private struct FriendsChatReactionAnchoredBubbleCard<Content: View, Reaction: View>: View {
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  let isHighlighted: Bool
  var minWidth: CGFloat? = nil
  var maxWidth: CGFloat? = nil
  @ViewBuilder let content: () -> Content
  @ViewBuilder let reaction: () -> Reaction

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
      .friendsChatFocusedBackground(
        isHighlighted: isHighlighted,
        cornerRadius: CornerRadius.bubble
      )
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
    .frame(width: separatorWidth)
    .padding(.vertical, Spacing.xs)
  }

  private var separatorWidth: CGFloat {
    let screenWidth =
      UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first?
      .screen
      .bounds
      .width
      ?? 390

    return screenWidth - (Spacing.md * 2)
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

        VStack(alignment: .leading, spacing: 3) {
          Text(preview.senderName)
            .font(.tidexCaptionStrong)
            .foregroundColor(accentColor)

          HStack(alignment: .firstTextBaseline, spacing: Spacing.xxxs) {
            if let iconSystemName = preview.iconPreviewKind?.friendsChatReplyIconSystemName {
              Image(systemName: iconSystemName)
                .font(.tidexCaptionRegular)
                .foregroundColor(textColor)
            }

            Text(preview.snippet)
              .font(.tidexFootnote)
              .foregroundColor(textColor)
              .multilineTextAlignment(.leading)
              .lineLimit(2)
          }
        }

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

struct ChatShiftSnapshotCard: View {
  let snapshot: FriendShiftSnapshot
  let isCurrentUser: Bool
  let isHighlighted: Bool

  private var ownerPrimaryTextColor: Color {
    .tidexTextMuted
  }

  var body: some View {
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
    .friendsChatFocusedBackground(
      isHighlighted: isHighlighted,
      cornerRadius: CornerRadius.xl
    )
  }
}

private struct FriendsChatImageView: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let isHighlighted: Bool

  @State private var selectedImageViewer: FriendsChatSelectedImageViewer?

  var body: some View {
    FriendsChatImageAttachmentCard(
      attachment: attachment,
      isCurrentUser: isCurrentUser,
      isHighlighted: isHighlighted
    ) { image in
      selectedImageViewer = FriendsChatSelectedImageViewer(image: image)
    }
    .fullScreenCover(item: $selectedImageViewer) { viewer in
      ImageViewerOverlay(image: viewer.image) {
        selectedImageViewer = nil
      }
    }
  }
}

@MainActor
final class FriendsChatImageLoader: ObservableObject {
  @Published private(set) var image: UIImage?
  @Published private(set) var isLoading = false

  init(initialImage: UIImage? = nil) {
    image = initialImage
  }

  func loadIfNeeded(attachment: FriendMessageAttachment) async {
    if let image {
      self.image = image
      return
    }

    let cacheURL = Self.cacheURL(for: attachment.storagePath)

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
      guard let loadedImage = await Self.decodeImage(from: data) else { return }
      ImageCache.shared.set(loadedImage, for: cacheURL)
      image = loadedImage
    } catch {
      image = nil
    }
  }

  nonisolated static func cacheURL(for storagePath: String) -> URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "friends-message-cache.local"
    components.path = "/\(storagePath)"
    return components.url ?? URL(filePath: "/tmp/friends-message-cache-fallback")
  }

  nonisolated private static func decodeImage(from data: Data) async -> UIImage? {
    await Task.detached(priority: .utility) {
      autoreleasepool {
        UIImage(data: data)
      }
    }.value
  }
}

struct FriendsChatImageAttachmentCard: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let isHighlighted: Bool
  var onTap: ((UIImage) -> Void)? = nil

  @StateObject private var loader: FriendsChatImageLoader

  init(
    attachment: FriendMessageAttachment,
    isCurrentUser: Bool,
    isHighlighted: Bool,
    onTap: ((UIImage) -> Void)? = nil
  ) {
    self.attachment = attachment
    self.isCurrentUser = isCurrentUser
    self.isHighlighted = isHighlighted
    self.onTap = onTap
    let cacheURL = FriendsChatImageLoader.cacheURL(for: attachment.storagePath)
    let initialImage = ImageCache.shared.get(for: cacheURL)
    _loader = StateObject(
      wrappedValue: FriendsChatImageLoader(initialImage: initialImage)
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
            onTap?(image)
          }
      } else if loader.isLoading {
        placeholder {
          ProgressView()
        }
      } else {
        placeholder {
          Image(systemName: "photo")
            .font(.tidexTitle2)
            .foregroundColor(.tidexTextMuted)
        }
      }
    }
    .task(id: attachment.id) {
      await loader.loadIfNeeded(attachment: attachment)
    }
    .friendsChatFocusedBackground(
      isHighlighted: isHighlighted,
      cornerRadius: CornerRadius.lg
    )
  }

  private var imageFrameSize: CGSize {
    attachment.friendsChatImageFrameSize()
  }

  private var imageShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
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

private struct FriendsChatSelectedImageViewer: Identifiable {
  let id = UUID()
  let image: UIImage
}

private struct FriendsChatFocusedBackgroundModifier: ViewModifier {
  let isHighlighted: Bool
  let cornerRadius: CGFloat

  func body(content: Content) -> some View {
    content
  }
}

extension View {
  fileprivate func friendsChatFocusedBackground(isHighlighted: Bool, cornerRadius: CGFloat)
    -> some View
  {
    modifier(
      FriendsChatFocusedBackgroundModifier(
        isHighlighted: isHighlighted,
        cornerRadius: cornerRadius
      )
    )
  }
}
