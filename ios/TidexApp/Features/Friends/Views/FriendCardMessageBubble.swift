import SwiftUI

/// The last message in a friend card as a chat bubble: gray from the friend, blue from the user.
struct FriendCardMessageBubble: View {
  let preview: FriendCardMessagePreview?
  let isTyping: Bool

  private var state: FriendCardMessageState? {
    isTyping ? nil : preview?.state
  }

  private var isOutgoing: Bool {
    switch state {
    case .outgoingSending, .outgoingSent, .outgoingOpened, .outgoingFailed: true
    case .incomingUnread, .incomingOpened, nil: false
    }
  }

  var body: some View {
    Group {
      if isTyping {
        TypingIndicatorView(background: .tidexSurfaceSecondary)
          .scaleEffect(0.8, anchor: .leading)
      } else if let preview {
        Text(preview.text)
          .font(state == .incomingUnread ? .tidexSubheadline.weight(.semibold) : .tidexSubheadline)
          .foregroundColor(textColor)
          .lineLimit(2)
          .padding(.horizontal, Spacing.sm)
          .padding(.vertical, Spacing.xxxs)
          .background(
            UnevenRoundedRectangle(
              topLeadingRadius: isOutgoing ? CornerRadius.bubble : CornerRadius.xxs,
              bottomLeadingRadius: CornerRadius.bubble,
              bottomTrailingRadius: CornerRadius.bubble,
              topTrailingRadius: isOutgoing ? CornerRadius.xxs : CornerRadius.bubble,
              style: .continuous
            )
            .fill(fillColor)
          )
      }
    }
  }

  private var fillColor: Color {
    switch state {
    case .incomingUnread, .incomingOpened, nil: .tidexSurfaceSecondary
    case .outgoingSent, .outgoingOpened: .tidexBlue
    case .outgoingSending: .tidexBlue.opacity(0.55)
    case .outgoingFailed: .tidexError.opacity(0.14)
    }
  }

  private var textColor: Color {
    switch state {
    case .incomingUnread, .incomingOpened, nil: .tidexTextPrimary
    case .outgoingSent, .outgoingOpened, .outgoingSending: .tidexTextOnBrand
    case .outgoingFailed: .tidexError
    }
  }
}

/// The name row with the message bubble under it. The name row takes the bubble's width, so the
/// time sits above the bubble's trailing edge rather than at the far edge of the card. A wider
/// name row widens the column instead.
struct FriendCardMessageColumn: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = measure(width: proposal.width, subviews: subviews)
    return CGSize(width: sizes.width, height: sizes.height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let sizes = measure(width: bounds.width, subviews: subviews)
    subviews[0].place(
      at: bounds.origin,
      proposal: ProposedViewSize(width: sizes.width, height: sizes.header.height)
    )
    guard let bubble = sizes.bubble, subviews.count > 1 else { return }
    subviews[1].place(
      at: CGPoint(
        x: bounds.minX,
        y: bounds.minY + sizes.header.height + spacing
      ),
      proposal: ProposedViewSize(bubble)
    )
  }

  private struct Sizes {
    let width: CGFloat
    let height: CGFloat
    let header: CGSize
    let bubble: CGSize?
  }

  private func measure(width available: CGFloat?, subviews: Subviews) -> Sizes {
    let bubble = subviews.count > 1
      ? subviews[1].sizeThatFits(ProposedViewSize(width: available, height: nil)) : nil
    let headerIdealWidth = subviews[0].sizeThatFits(.unspecified).width
    let width = min(max(bubble?.width ?? 0, headerIdealWidth), available ?? .infinity)
    let header = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
    let height = header.height + (bubble.map { spacing + $0.height } ?? 0)
    return Sizes(width: width, height: height, header: header, bubble: bubble)
  }
}
