import ExyteChat
import ImageIO
import SwiftUI
import UIKit

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

    let aspectRatio: CGFloat = CGFloat(width) / CGFloat(height)

    if aspectRatio >= 1 {
      let scaledHeight: CGFloat = max(minDimension, maxDimension / aspectRatio)
      return CGSize(width: maxDimension, height: min(maxDimension, scaledHeight))
    }

    let scaledWidth: CGFloat = max(minDimension, maxDimension * aspectRatio)
    return CGSize(width: min(maxDimension, scaledWidth), height: maxDimension)
  }
}

struct FriendsChatReplySwipeConfiguration {
  let id: String
  let isCurrentUser: Bool
  let offset: CGFloat
  let actionAlignment: Alignment
  let actionLabel: AnyView
  let onChanged: (FriendsChatReplyDragValue) -> Void
  let onEnded: (FriendsChatReplyDragValue) -> Void
}

struct FriendsChatReactionAnchoredBubbleCard<Content: View, Reaction: View, Status: View>: View {
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext
  // swiftlint:disable:next explicit_acl
  var minWidth: CGFloat?
  // swiftlint:disable:next explicit_acl
  var maxWidth: CGFloat?
  let messageFrame: Binding<CGRect>?
  // swiftlint:disable:next explicit_acl
  var replySwipe: FriendsChatReplySwipeConfiguration?
  @ViewBuilder let content: () -> Content
  @ViewBuilder let reaction: () -> Reaction
  @ViewBuilder let status: () -> Status

  var body: some View {
    Group {
      if let minWidth, let maxWidth {
        swipeableBubbleBody
          .frame(
            minWidth: minWidth,
            maxWidth: maxWidth,
            alignment: isCurrentUser ? .trailing : .leading
          )
          .offset(x: bubbleOffset)
      } else if let maxWidth {
        swipeableBubbleBody
          .frame(maxWidth: maxWidth, alignment: isCurrentUser ? .trailing : .leading)
          .offset(x: bubbleOffset)
      } else if let minWidth {
        swipeableBubbleBody
          .frame(minWidth: minWidth, alignment: isCurrentUser ? .trailing : .leading)
          .offset(x: bubbleOffset)
      } else {
        swipeableBubbleBody
          .offset(x: bubbleOffset)
      }
    }
  }

  @ViewBuilder
  private var swipeableBubbleBody: some View {
    if let replySwipe {
      bubbleBody
        .background(replySwipeFramePreference(replySwipe.id))
        .contentShape(bubbleShape)
        .modifier(
          FriendsChatReplyGestureModifier(
            isCurrentUser: replySwipe.isCurrentUser,
            onChanged: replySwipe.onChanged,
            onEnded: replySwipe.onEnded
          )
        )
        .overlay(alignment: replySwipe.actionAlignment) {
          replySwipe.actionLabel
            .allowsHitTesting(false)
        }
    } else {
      bubbleBody
    }
  }

  private func replySwipeFramePreference(_ id: String) -> some View {
    GeometryReader { proxy in
      Color.clear.preference(
        key: FriendsChatReplyPayloadFramePreferenceKey.self,
        value: [id: proxy.frame(in: .global)]
      )
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
      .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) {
        reaction()
      }
      .overlay(alignment: isCurrentUser ? .bottomLeading : .bottomTrailing) {
        status()
      }
      .friendsChatMessageFrame(messageFrame)
  }

  private var bubbleOffset: CGFloat {
    replySwipe?.offset ?? 0
  }

  private var bubbleShape: some InsettableShape {
    FriendsChatMessageBubbleShapeResolver.shape(for: groupContext)
  }
}

enum FriendsChatMessageBubbleShapeResolver {
  static func shape(for groupContext: FriendsChatMessageGroupContext) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      cornerRadii: RectangleCornerRadii(
        topLeading: topLeadingRadius(for: groupContext),
        bottomLeading: bottomLeadingRadius(for: groupContext),
        bottomTrailing: bottomTrailingRadius(for: groupContext),
        topTrailing: topTrailingRadius(for: groupContext)
      ),
      style: .continuous
    )
  }

  static func uniformShape(cornerRadius: CGFloat) -> UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      cornerRadii: RectangleCornerRadii(
        topLeading: cornerRadius,
        bottomLeading: cornerRadius,
        bottomTrailing: cornerRadius,
        topTrailing: cornerRadius
      ),
      style: .continuous
    )
  }

  private static func topLeadingRadius(for groupContext: FriendsChatMessageGroupContext)
    -> CGFloat
  {
    if !groupContext.isCurrentUser, groupContext.joinsPrevious {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private static func bottomLeadingRadius(for groupContext: FriendsChatMessageGroupContext)
    -> CGFloat
  {
    if groupContext.showsIncomingBottomTail {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private static func bottomTrailingRadius(for groupContext: FriendsChatMessageGroupContext)
    -> CGFloat
  {
    if groupContext.showsOutgoingBottomTail {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private static func topTrailingRadius(for groupContext: FriendsChatMessageGroupContext)
    -> CGFloat
  {
    if groupContext.isCurrentUser, groupContext.joinsPrevious {
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
    replySwipe: FriendsChatReplySwipeConfiguration? = nil,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder reaction: @escaping () -> Reaction
  ) {
    self.isCurrentUser = isCurrentUser
    self.groupContext = groupContext
    self.minWidth = minWidth
    self.maxWidth = maxWidth
    self.messageFrame = messageFrame
    self.replySwipe = replySwipe
    self.content = content
    self.reaction = reaction
    self.status = { EmptyView() }
  }
}

extension View {
  @ViewBuilder
  func friendsChatMessageFrame(_ messageFrame: Binding<CGRect>?) -> some View {
    if let messageFrame {
      frameGetter(messageFrame)
    } else {
      self
    }
  }
}