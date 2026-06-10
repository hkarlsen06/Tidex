// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl file_name implicit_optional_initialization
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers prefer_condition_list prefer_self_in_static_references sorted_enum_cases
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_contents_order vertical_whitespace_between_cases
import SwiftUI

enum ChatMessageGroupPosition: Equatable {
  case standalone
  case leading
  case middle
  case trailing
}

struct ChatMessageGroupContext: Equatable {
  let position: ChatMessageGroupPosition
  let isCurrentUser: Bool

  static func standalone(isCurrentUser: Bool) -> Self {
    Self(position: .standalone, isCurrentUser: isCurrentUser)
  }

  var joinsPrevious: Bool {
    switch position {
    case .middle, .trailing:
      return true

    case .standalone, .leading:
      return false
    }
  }

  var joinsNext: Bool {
    switch position {
    case .leading, .middle:
      return true

    case .standalone, .trailing:
      return false
    }
  }
}

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

struct ChatBubbleCard<Content: View>: View {
  let isCurrentUser: Bool
  var groupContext: ChatMessageGroupContext?
  var minWidth: CGFloat?
  var maxWidth: CGFloat?
  @ViewBuilder let content: () -> Content

  private var effectiveGroupContext: ChatMessageGroupContext {
    groupContext ?? .standalone(isCurrentUser: isCurrentUser)
  }

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
            isCurrentUser ? Color.clear : Color.tidexBorderSubtle.opacity(0.45),
            lineWidth: 1
          )
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
    if !isCurrentUser, effectiveGroupContext.joinsPrevious {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var bottomLeadingRadius: CGFloat {
    if !isCurrentUser, effectiveGroupContext.joinsNext {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var bottomTrailingRadius: CGFloat {
    if isCurrentUser, effectiveGroupContext.joinsNext {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }

  private var topTrailingRadius: CGFloat {
    if isCurrentUser, effectiveGroupContext.joinsPrevious {
      return CornerRadius.xxs
    }
    return CornerRadius.bubble
  }
}
