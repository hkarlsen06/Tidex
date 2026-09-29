import SwiftUI

enum FriendCardMessageState: Equatable {
  case outgoingSending
  case outgoingSent
  case outgoingOpened
  case outgoingFailed
  case incomingUnread
  case incomingOpened
}

struct FriendCardMessagePreview: Equatable {
  let text: String
  let timestamp: Date
  let state: FriendCardMessageState

  var metaColor: Color {
    switch state {
    case .incomingUnread: .tidexBlueText
    case .outgoingFailed: .tidexError
    default: .tidexTextMuted
    }
  }

  /// Paper planes for the user's messages, bubbles for the friend's. Filled means not yet opened.
  var metaSymbol: String {
    switch state {
    case .outgoingSending, .outgoingSent: "paperplane.fill"
    case .outgoingOpened: "paperplane"
    case .outgoingFailed: "xmark"
    case .incomingUnread: "message.fill"
    case .incomingOpened: "message"
    }
  }

  /// What VoiceOver reads in place of the icon.
  var metaLabel: LocalizedStringResource {
    switch state {
    case .outgoingSending: .friendsChatStatusSending
    case .outgoingSent: .friendsChatPreviewLabelSent
    case .outgoingOpened: .friendsChatPreviewLabelOpened
    case .outgoingFailed: .friendsChatStatusFailed
    case .incomingUnread: .friendsChatPreviewLabelNew
    case .incomingOpened: .friendsChatPreviewLabelReceived
    }
  }

  func metaText(at now: Date) -> String {
    FriendCardMessagePreviewTimestampFormatter.relativeTimestamp(
      messageDate: timestamp,
      referenceDate: now
    )
  }
}

/// The last message in a friend card as a chat bubble: gray from the friend, blue from the user.
struct FriendCardMessageBubble: View {
  let preview: FriendCardMessagePreview?
  let isTyping: Bool

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text(.friendsChatTypingToastBody))
      } else if let preview {
        Text(preview.text)
          .font(state == .incomingUnread ? .tidexSubheadline.weight(.semibold) : .tidexSubheadline)
          .foregroundColor(textColor)
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
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
    // The user's messages sit on the right, like in the chat.
    .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
  }

  private var fillColor: Color {
    switch state {
    case .incomingUnread, .incomingOpened, nil: .tidexSurfaceSecondary
    case .outgoingSent, .outgoingOpened, .outgoingSending: .tidexBlue
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
