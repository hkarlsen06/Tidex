import SwiftUI

/// Scrollable list of chat messages with auto-scroll to bottom
struct ChatMessageList: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let messages: [ChatMessage]
  let streamingMessages: [ChatMessage]
  let streamingContentBlocks: [ContentBlock]
  let isStreaming: Bool
  let isThinking: Bool
  let showsConversationLengthWarning: Bool
  let remainingMessagesText: String?
  let showsHistoryButton: Bool
  let bottomContentInset: CGFloat
  @Binding var isScrolledToBottom: Bool
  let scrollToBottomTrigger: Int
  var onStreamEndedAwayFromBottom: (() -> Void)?

  /// Callback when a suggestion chip is tapped
  var onSuggestionTapped: ((String) -> Void)?
  var onHistoryTapped: (() -> Void)?

  /// Whether the "Copied!" confirmation is showing
  @State private var showCopiedConfirmation = false
  @State private var showsSuggestions = false

  init(
    messages: [ChatMessage],
    streamingMessages: [ChatMessage],
    streamingContentBlocks: [ContentBlock],
    isStreaming: Bool,
    isThinking: Bool,
    showsConversationLengthWarning: Bool = false,
    remainingMessagesText: String?,
    showsHistoryButton: Bool,
    bottomContentInset: CGFloat = Spacing.bottomScrollMargin,
    isScrolledToBottom: Binding<Bool>,
    scrollToBottomTrigger: Int = 0,
    onStreamEndedAwayFromBottom: (() -> Void)? = nil,
    onSuggestionTapped: ((String) -> Void)? = nil,
    onHistoryTapped: (() -> Void)? = nil
  ) {
    self.messages = messages
    self.streamingMessages = streamingMessages
    self.streamingContentBlocks = streamingContentBlocks
    self.isStreaming = isStreaming
    self.isThinking = isThinking
    self.showsConversationLengthWarning = showsConversationLengthWarning
    self.remainingMessagesText = remainingMessagesText
    self.showsHistoryButton = showsHistoryButton
    self.bottomContentInset = bottomContentInset
    self._isScrolledToBottom = isScrolledToBottom
    self.scrollToBottomTrigger = scrollToBottomTrigger
    self.onStreamEndedAwayFromBottom = onStreamEndedAwayFromBottom
    self.onSuggestionTapped = onSuggestionTapped
    self.onHistoryTapped = onHistoryTapped
  }

  private struct ScrollState: Equatable {
    let messageCount: Int
    let lastMessageID: String?
    let streamingSignature: Int
    let isStreaming: Bool
  }

  private var scrollState: ScrollState {
    let allMessages = renderedMessages
    return ScrollState(
      messageCount: allMessages.count,
      lastMessageID: allMessages.last?.id,
      streamingSignature: streamingContentSignature,
      isStreaming: isStreaming || isThinking
    )
  }

  private var renderedMessages: [ChatMessage] {
    messages + streamingMessages
  }

  private var streamingGroupContext: ChatMessageGroupContext {
    let placeholder = ChatMessage(
      role: .assistant,
      contentBlocks: streamingContentBlocks,
      timestamp: Date()
    )
    return WageyChatMessageGrouping.context(
      for: placeholder,
      previous: renderedMessages.last,
      next: nil
    )
  }

  private var streamingContentSignature: Int {
    streamingContentBlocks.reduce(into: 0) { result, block in
      switch block {
      case .text(let text):
        result = result &* 31 &+ text.count
      case .toolCall(let toolCall):
        result = result &* 31 &+ toolCall.name.count
        result = result &* 31 &+ (toolCall.result?.count ?? 0)
      case .image:
        result = result &* 31 &+ 1
      case .thoughtStatus(let status):
        result = result &* 31 &+ status.durationSeconds
      }
    }
  }

  var body: some View {
    ChatTimelineScrollView(
      scrollState: scrollState,
      bottomContentInset: bottomContentInset,
      contentSpacing: 0,
      isPinnedToBottom: $isScrolledToBottom,
      scrollToBottomTrigger: scrollToBottomTrigger,
      dismissKeyboardOnTap: true,
      onScrollStateChange: { oldValue, newValue, context in
        handleScrollStateChange(from: oldValue, to: newValue, context: context)
      }
    ) {
      // Empty state when no messages
      if messages.isEmpty && !isStreaming {
        emptyStateView
          .padding(.top, Spacing.xxl)
      } else {
        // Message bubbles
        ForEach(Array(renderedMessages.enumerated()), id: \.element.id) { index, message in
          ChatMessageBubble(
            message: message,
            groupContext: groupContext(for: index, in: renderedMessages)
          )
          .id(message.id)
        }

        // Streaming message
        if isStreaming {
          StreamingMessageBubble(
            contentBlocks: streamingContentBlocks,
            isThinking: isThinking,
            groupContext: streamingGroupContext
          )
          .id("streaming")
        }

        // Copy conversation button (after last assistant message, when not streaming)
        if !isStreaming, messages.last?.role == .assistant {
          copyConversationButton
        }

        if showsConversationLengthWarning {
          conversationLengthWarning
            .padding(.top, Spacing.sm)
        }
      }
    }
  }

  private func groupContext(for index: Int, in messages: [ChatMessage]) -> ChatMessageGroupContext {
    WageyChatMessageGrouping.context(
      for: messages[index],
      previous: index > 0 ? messages[index - 1] : nil,
      next: index < (messages.count - 1) ? messages[index + 1] : nil
    )
  }

  // MARK: - Empty State

  /// Suggestion card data pairing an icon with the localized text
  private var suggestions: [(icon: String, text: String)] {
    [
      ("doc.on.doc", String(localized: .wageyEmptyStateSuggestion1)),
      ("banknote.fill", String(localized: .wageyEmptyStateSuggestion2)),
      ("chart.bar.fill", String(localized: .wageyEmptyStateSuggestion3)),
      (
        "repeat.circle",
        String(localized: .wageyEmptyStateSuggestion4)
      ),
    ]
  }

  private var emptyStateView: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      welcomeHero

      if showsSuggestions {
        suggestionsSection
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
  }

  private var suggestionsSection: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "sparkles")
          .font(.tidexCaptionStrong)
          .foregroundColor(.tidexBlue)

        Text(.wageyEmptyStateQuickStart)
          .font(.tidexFootnoteStrong)
          .foregroundColor(.tidexTextPrimary)

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.top, Spacing.sm)

      VStack(spacing: 0) {
        ForEach(Array(suggestions.enumerated()), id: \.element.text) { index, suggestion in
          suggestionRow(icon: suggestion.icon, text: suggestion.text)

          if index < suggestions.count - 1 {
            Divider()
              .overlay(Color.tidexBorderSubtle.opacity(0.7))
              .padding(.leading, 42)
          }
        }
      }
    }
    .padding(Spacing.xxs)
    .background(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .fill(Color.tidexSurfacePrimary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
        .stroke(Color.tidexBorderSubtle, lineWidth: 1)
    )
  }

  private var welcomeHero: some View {
    VStack(alignment: .leading, spacing: Spacing.md) {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Image(systemName: "sparkles")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexBlue)
          .frame(width: 32, height: 32)
          .background(Color.tidexBlue.opacity(0.1), in: Circle())

        Text(.wageyEmptyStateWelcomeTitle)
          .font(.tidexScreenTitle)
          .foregroundColor(.tidexTextPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Text(.wageyEmptyStateWelcomeSubtitle)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: Spacing.sm) {
        if let remainingMessagesText, !remainingMessagesText.isEmpty {
          Text(remainingMessagesText)
            .font(.tidexFootnoteStrong)
            .foregroundColor(.tidexTextSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(Capsule())
        }

        if !showsSuggestions {
          Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
              showsSuggestions = true
            }
          } label: {
            HStack(spacing: Spacing.xs) {
              Image(systemName: "list.bullet")
                .font(.tidexFootnoteStrong)

              Text(.wageyEmptyStateQuickStart)
                .font(.tidexFootnoteStrong)
            }
            .foregroundColor(.tidexTextSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.top, Spacing.md)
    .padding(.trailing, showsHistoryButton ? 56 : 0)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .topTrailing) {
      if showsHistoryButton {
        Button {
          Haptics.play(.light)
          onHistoryTapped?()
        } label: {
          Image(systemName: "clock.arrow.circlepath")
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextSecondary)
            .frame(width: 40, height: 40)
            .background(Color.tidexSurfaceSecondary, in: Circle())
            .overlay(Circle().stroke(Color.tidexBorderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.sm)
        .padding(.trailing, Spacing.sm)
        .accessibilityLabel(Text(.wageyChatConversationHistory))
      }
    }
  }

  private func suggestionRow(icon: String, text: String) -> some View {
    Button {
      Haptics.play(.light)
      onSuggestionTapped?(text)
    } label: {
      HStack(alignment: .center, spacing: Spacing.sm) {
        Image(systemName: icon)
          .font(.tidexFootnoteStrong)
          .foregroundColor(.tidexBlue)
          .frame(width: 28, height: 28)
          .background(Color.tidexBlue.opacity(0.09), in: Circle())

        Text(text)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 0)

        Image(systemName: "pencil.circle.fill")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .contentShape(Rectangle())
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

  private var conversationLengthWarning: some View {
    HStack(spacing: Spacing.xs) {
      Image(systemName: "info.circle")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)

      Text(.wageyConversationLongWarning)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xsm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }

  private func copyConversation() {
    let text = messages.map(formatMessageForCopy).joined(separator: "\n\n")

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

  private func formatMessageForCopy(_ message: ChatMessage) -> String {
    let role = message.role == .user ? "You" : "Wagey"
    let sections = message.contentBlocks.compactMap(formatContentBlockForCopy)

    guard !sections.isEmpty else { return "\(role):" }
    guard sections.count == 1, !sections[0].contains("\n") else {
      return "\(role):\n\(sections.joined(separator: "\n\n"))"
    }

    return "\(role): \(sections[0])"
  }

  private func formatContentBlockForCopy(_ block: ContentBlock) -> String? {
    switch block {
    case .text(let text):
      return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    case .toolCall(let toolCall):
      return formatToolCallForCopy(toolCall)
    case .image:
      return nil
    case .thoughtStatus(let status):
      return status.localizedLabel
    }
  }

  private func formatToolCallForCopy(_ toolCall: ToolCall) -> String {
    let toolName = WageyToolLabelResolver.displayName(for: toolCall, isExecuting: false)
    var sections = ["\(String(localized: .wageyToolName)): \(toolName)"]

    if let arguments = toolCall.arguments, !arguments.isEmpty {
      sections.append("\(String(localized: .wageyToolRequest)):\n\(formatJSON(arguments))")
    }

    if let result = toolCall.result, !result.isEmpty {
      sections.append("\(String(localized: .wageyToolResponse)):\n\(formatJSON(result))")
    }

    return sections.joined(separator: "\n")
  }

  private func formatJSON(_ string: String) -> String {
    WageyToolJSONFormatter.format(string)
  }

  // MARK: - Scroll Helper

  private func handleScrollStateChange(
    from oldValue: ScrollState,
    to newValue: ScrollState,
    context: ChatTimelineScrollContext
  ) {
    let startedStreaming = !oldValue.isStreaming && newValue.isStreaming
    let finishedStreaming = oldValue.isStreaming && !newValue.isStreaming
    let appendedMessage =
      oldValue.messageCount != newValue.messageCount
      || oldValue.lastMessageID != newValue.lastMessageID

    if startedStreaming {
      context.scrollToBottom(false, true)
      return
    }

    if finishedStreaming && (!context.isPinnedToBottom || context.suppressAutoFollow) {
      onStreamEndedAwayFromBottom?()
    }

    if appendedMessage {
      guard context.shouldAutoFollow else { return }
      let shouldAnimate = !newValue.isStreaming
      context.scrollToBottom(shouldAnimate, false)
      return
    }

    if oldValue.streamingSignature != newValue.streamingSignature {
      // Let the stream grow naturally so the user can read older content without being snapped down.
      return
    }
  }

}

// MARK: - Previews

#Preview("Empty State") {
  ChatMessageList(
    messages: [],
    streamingMessages: [],
    streamingContentBlocks: [],
    isStreaming: false,
    isThinking: false,
    remainingMessagesText: "15 messages left",
    showsHistoryButton: true,
    isScrolledToBottom: .constant(true)
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
    streamingMessages: [],
    streamingContentBlocks: [],
    isStreaming: false,
    isThinking: false,
    remainingMessagesText: nil,
    showsHistoryButton: true,
    isScrolledToBottom: .constant(true)
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
    streamingMessages: [],
    streamingContentBlocks: [
      .text("I'll add that shift for you..."),
      .toolCall(
        ToolCall(id: "call_1", name: "manage_shift", arguments: nil, result: nil, success: nil)),
    ],
    isStreaming: true,
    isThinking: true,
    remainingMessagesText: nil,
    showsHistoryButton: false,
    isScrolledToBottom: .constant(true)
  )
  .background(Color.tidexBackground)
}
