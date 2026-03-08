import SwiftUI

struct ChatMessageRow<Content: View>: View {
  let isCurrentUser: Bool
  var minSpacer: CGFloat = 40
  var spacing: CGFloat = Spacing.xs
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack {
      if isCurrentUser {
        Spacer(minLength: minSpacer)
      }

      VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: spacing) {
        content()
      }

      if !isCurrentUser {
        Spacer(minLength: minSpacer)
      }
    }
  }
}

struct ChatBubbleCard<Content: View>: View {
  let isCurrentUser: Bool
  var minWidth: CGFloat? = nil
  var maxWidth: CGFloat? = nil
  @ViewBuilder let content: () -> Content

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
        RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous)
          .fill(isCurrentUser ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous)
          .stroke(
            isCurrentUser ? Color.clear : Color.tidexBorderSubtle,
            lineWidth: 1
          )
      )
  }
}
