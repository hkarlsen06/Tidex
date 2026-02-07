import SwiftUI

/// Scrollable list of chat messages with auto-scroll to bottom
struct ChatMessageList: View {
  let messages: [ChatMessage]
  let streamingContentBlocks: [ContentBlock]
  let isStreaming: Bool

  /// Callback when a suggestion chip is tapped
  var onSuggestionTapped: ((String) -> Void)?

  /// Namespace for scroll-to-bottom animation
  @Namespace private var bottomID

  /// Whether the "Copied!" confirmation is showing
  @State private var showCopiedConfirmation = false

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: Spacing.sm) {
          // Empty state when no messages
          if messages.isEmpty && !isStreaming {
            emptyStateView
              .padding(.top, Spacing.xxl)
          } else {
            // Message bubbles
            ForEach(messages) { message in
              ChatMessageBubble(message: message)
                .id(message.id)
            }

            // Streaming message
            if isStreaming {
              StreamingMessageBubble(contentBlocks: streamingContentBlocks)
                .id("streaming")
            }

            // Copy conversation button (after last assistant message, when not streaming)
            if !isStreaming, messages.last?.role == .assistant {
              copyConversationButton
            }
          }

          // Bottom anchor for scrolling
          Color.clear
            .frame(height: 1)
            .id("bottom")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
      }
      .onChange(of: messages.count) { _, _ in
        scrollToBottom(proxy: proxy)
      }
      .onChange(of: streamingContentBlocks.count) { _, _ in
        scrollToBottom(proxy: proxy)
      }
      .onChange(of: isStreaming) { _, streaming in
        if streaming {
          scrollToBottom(proxy: proxy)
        }
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .onTapGesture {
      // Dismiss keyboard when tapping on the message area
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
  }

  // MARK: - Empty State

  /// Suggestion card data pairing an icon with the localized text
  private var suggestions: [(icon: String, text: String)] {
    [
      ("calendar.badge.plus", String(localized: .wageyEmptyStateSuggestion1)),
      ("chart.bar.fill", String(localized: .wageyEmptyStateSuggestion2)),
      ("list.clipboard.fill", String(localized: .wageyEmptyStateSuggestion3)),
      ("banknote.fill", String(localized: .wageyEmptyStateSuggestion4)),
    ]
  }

  private var emptyStateView: some View {
    VStack(spacing: Spacing.xl) {
      VStack(spacing: 6) {
        Text(.wageyEmptyStateTitle)
          .font(.tidexLargeTitle)
          .foregroundColor(.tidexTextPrimary)

        Text(.wageyEmptyStateSubtitle)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextSecondary)
          .multilineTextAlignment(.center)
      }

      // Suggestion list
      VStack(spacing: 10) {
        ForEach(suggestions, id: \.text) { suggestion in
          suggestionRow(icon: suggestion.icon, text: suggestion.text)
        }
      }
    }
    .padding(.horizontal, Spacing.lg)
  }

  private func suggestionRow(icon: String, text: String) -> some View {
    Button {
      Haptics.play(.light)
      onSuggestionTapped?(text)
    } label: {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.system(size: 18))
          .foregroundColor(.tidexBlue)
          .frame(width: 24)

        Text(text)
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        Spacer(minLength: 0)

        Image(systemName: "chevron.right")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, 14)
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Copy Conversation

  private var copyConversationButton: some View {
    Button {
      Haptics.play(.light)
      copyConversation()
    } label: {
      Image(systemName: showCopiedConfirmation ? "checkmark" : "doc.on.doc")
        .font(.tidexLabel)
        .foregroundColor(showCopiedConfirmation ? .tidexSuccess : .tidexTextMuted)
        .contentTransition(.symbolEffect(.replace))
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, 18)
    .padding(.top, Spacing.xxs)
  }

  private func copyConversation() {
    let text = messages.map { message in
      let role = message.role == .user ? "You" : "Wagey"
      return "\(role): \(message.content)"
    }.joined(separator: "\n\n")

    UIPasteboard.general.string = text

    withAnimation(.easeInOut(duration: 0.2)) {
      showCopiedConfirmation = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      withAnimation(.easeInOut(duration: 0.2)) {
        showCopiedConfirmation = false
      }
    }
  }

  // MARK: - Scroll Helper

  private func scrollToBottom(proxy: ScrollViewProxy) {
    withAnimation(.easeOut(duration: 0.2)) {
      proxy.scrollTo("bottom", anchor: .bottom)
    }
  }
}

// MARK: - Previews

#Preview("Empty State") {
  ChatMessageList(
    messages: [],
    streamingContentBlocks: [],
    isStreaming: false
  )
  .background(Color.tidexBackground)
}

#Preview("With Messages") {
  ChatMessageList(
    messages: [
      ChatMessage(
        id: "1",
        role: MessageRole.user,
        content: "What shifts do I have this week?",
        toolCalls: nil,
        timestamp: Date()
      ),
      ChatMessage(
        id: "2",
        role: MessageRole.assistant,
        content:
          "You have 3 shifts scheduled this week:\n\n- Monday: 09:00-17:00\n- Wednesday: 14:00-22:00\n- Friday: 08:00-16:00\n\nTotal: 24 hours, approximately **4,800 kr** before taxes.",
        toolCalls: [
          ToolCall(id: "call_1", name: "get_shifts", arguments: nil, result: "{}", success: true)
        ],
        timestamp: Date()
      ),
    ],
    streamingContentBlocks: [],
    isStreaming: false
  )
  .background(Color.tidexBackground)
}

#Preview("Streaming") {
  ChatMessageList(
    messages: [
      ChatMessage(
        id: "1",
        role: MessageRole.user,
        content: "Add a shift tomorrow 9-17",
        toolCalls: nil,
        timestamp: Date()
      )
    ],
    streamingContentBlocks: [
      .text("I'll add that shift for you..."),
      .toolCall(
        ToolCall(id: "call_1", name: "manage_shift", arguments: nil, result: nil, success: nil)),
    ],
    isStreaming: true
  )
  .background(Color.tidexBackground)
}
