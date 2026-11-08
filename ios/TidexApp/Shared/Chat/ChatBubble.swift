import SwiftUI

struct ChatMessageRow<Content: View>: View {
  let isCurrentUser: Bool
  var minSpacer: CGFloat = Spacing.xxl
  var spacing: CGFloat = Spacing.xs
  var horizontalInset: CGFloat = 0
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
    .padding(.horizontal, horizontalInset)
    .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
  }
}
