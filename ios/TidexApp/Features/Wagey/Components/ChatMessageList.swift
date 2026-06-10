import SwiftUI

/// Scrollable list of chat messages with auto-scroll to bottom
struct ChatMessageList: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  @Environment(\.accessibilityReduceMotion) private var reduceMotion  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  let messages: [ChatMessage]  // swiftlint:disable:this explicit_acl type_contents_order
  let streamingMessages: [ChatMessage]  // swiftlint:disable:this explicit_acl type_contents_order
  let streamingContentBlocks: [ContentBlock]  // swiftlint:disable:this explicit_acl type_contents_order
  let isStreaming: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let isThinking: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let showsConversationLengthWarning: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let remainingMessagesText: String?  // swiftlint:disable:this explicit_acl type_contents_order
  let showsHistoryButton: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let bottomContentInset: CGFloat  // swiftlint:disable:this explicit_acl type_contents_order
  @Binding var isScrolledToBottom: Bool  // swiftlint:disable:this explicit_acl type_contents_order
  let scrollToBottomTrigger: Int  // swiftlint:disable:this explicit_acl type_contents_order
  var onStreamEndedAwayFromBottom: (() -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order

  /// Callback when a suggestion chip is tapped
  var onSuggestionTapped: ((String) -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order
  var onHistoryTapped: (() -> Void)?  // swiftlint:disable:this explicit_acl type_contents_order

  /// Whether the "Copied!" confirmation is showing
  @State private var showCopiedConfirmation = false  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State private var showsSuggestions = false  // swiftlint:disable:this explicit_type_interface type_contents_order

  init(  // swiftlint:disable:this explicit_acl type_contents_order
    messages: [ChatMessage],
    streamingMessages: [ChatMessage],
    streamingContentBlocks: [ContentBlock],
    isStreaming: Bool,
    isThinking: Bool,
    showsConversationLengthWarning: Bool = false,  // swiftlint:disable:this function_default_parameter_at_end
    remainingMessagesText: String?,
    showsHistoryButton: Bool,
    bottomContentInset: CGFloat = Spacing.bottomScrollMargin,  // swiftlint:disable:this function_default_parameter_at_end line_length
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
    let allMessages = renderedMessages  // swiftlint:disable:this explicit_type_interface
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
    let placeholder = ChatMessage(  // swiftlint:disable:this explicit_type_interface
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
        result = result &* 31 &+ text.count  // swiftlint:disable:this no_magic_numbers

      case .toolCall(let toolCall):
        result = result &* 31 &+ toolCall.name.count  // swiftlint:disable:this no_magic_numbers
        result = result &* 31 &+ (toolCall.result?.count ?? 0)  // swiftlint:disable:this no_magic_numbers

      case .image:
        result = result &* 31 &+ 1  // swiftlint:disable:this no_magic_numbers

      case .thoughtStatus(let status):
        result = result &* 31 &+ status.durationSeconds  // swiftlint:disable:this no_magic_numbers
      }
    }
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
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
      if messages.isEmpty, !isStreaming {
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

  private func groupContext(for index: Int, in messages: [ChatMessage]) -> ChatMessageGroupContext
  {  // swiftlint:disable:this line_length type_contents_order
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
              .overlay(Color.tidexBorderSubtle.opacity(0.7))  // swiftlint:disable:this no_magic_numbers
              .padding(.leading, 42)  // swiftlint:disable:this no_magic_numbers
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
    VStack(alignment: .leading, spacing: Spacing.md) {  // swiftlint:disable:this closure_body_length
      VStack(alignment: .leading, spacing: Spacing.xs) {
        Image(systemName: "sparkles")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexBlue)
          .frame(width: 32, height: 32)  // swiftlint:disable:this no_magic_numbers
          .background(Color.tidexBlue.opacity(0.1), in: Circle())  // swiftlint:disable:this no_magic_numbers

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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {  // swiftlint:disable:this no_magic_numbers
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
    .padding(.trailing, showsHistoryButton ? 56 : 0)  // swiftlint:disable:this no_magic_numbers
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
            .frame(width: 40, height: 40)  // swiftlint:disable:this no_magic_numbers
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

  private func suggestionRow(icon: String, text: String) -> some View {  // swiftlint:disable:this type_contents_order
    Button {
      Haptics.play(.light)
      onSuggestionTapped?(text)
    } label: {
      HStack(alignment: .center, spacing: Spacing.sm) {
        Image(systemName: icon)
          .font(.tidexFootnoteStrong)
          .foregroundColor(.tidexBlue)
          .frame(width: 28, height: 28)  // swiftlint:disable:this no_magic_numbers
          .background(Color.tidexBlue.opacity(0.09), in: Circle())  // swiftlint:disable:this no_magic_numbers

        Text(text)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)  // swiftlint:disable:this no_magic_numbers
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
    .padding(.leading, 18)  // swiftlint:disable:this no_magic_numbers
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
    let text = messages.map(formatMessageForCopy).joined(separator: "\n\n")  // swiftlint:disable:this explicit_type_interface line_length

    UIPasteboard.general.string = text

    withAnimation(.easeInOut(duration: 0.2)) {  // swiftlint:disable:this no_magic_numbers
      showCopiedConfirmation = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {  // swiftlint:disable:this no_magic_numbers
      withAnimation(.easeInOut(duration: 0.2)) {  // swiftlint:disable:this no_magic_numbers
        showCopiedConfirmation = false
      }
    }
  }

  private func formatMessageForCopy(_ message: ChatMessage) -> String {
    let role = message.role == .user ? "You" : "Wagey"  // swiftlint:disable:this explicit_type_interface
    let sections = message.contentBlocks.compactMap(formatContentBlockForCopy)  // swiftlint:disable:this explicit_type_interface line_length

    guard !sections.isEmpty else { return "\(role):" }  // swiftlint:disable:this conditional_returns_on_newline
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
    let toolName = WageyToolLabelResolver.displayName(for: toolCall, isExecuting: false)  // swiftlint:disable:this explicit_type_interface line_length
    var sections = ["\(String(localized: .wageyToolName)): \(toolName)"]  // swiftlint:disable:this explicit_type_interface line_length

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
    let startedStreaming = !oldValue.isStreaming && newValue.isStreaming  // swiftlint:disable:this explicit_type_interface line_length
    let finishedStreaming = oldValue.isStreaming && !newValue.isStreaming  // swiftlint:disable:this explicit_type_interface line_length
    let appendedMessage =  // swiftlint:disable:this explicit_type_interface
      oldValue.messageCount != newValue.messageCount
      || oldValue.lastMessageID != newValue.lastMessageID

    if startedStreaming {
      context.scrollToBottom(false, true)
      return
    }

    if finishedStreaming, !context.isPinnedToBottom || context.suppressAutoFollow {
      onStreamEndedAwayFromBottom?()
    }

    if appendedMessage {
      guard context.shouldAutoFollow else { return }  // swiftlint:disable:this conditional_returns_on_newline
      let shouldAnimate = !newValue.isStreaming  // swiftlint:disable:this explicit_type_interface
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
          "You have 3 shifts scheduled this week:\n\n- Monday: 09:00-17:00\n- Wednesday: 14:00-22:00\n- Friday: 08:00-16:00\n\nTotal: 24 hours, approximately **4,800 kr** before taxes.",  // swiftlint:disable:this line_length
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
        ToolCall(id: "call_1", name: "manage_shift", arguments: nil, result: nil, success: nil)),  // swiftlint:disable:this line_length multiline_arguments_brackets
    ],
    isStreaming: true,
    isThinking: true,
    remainingMessagesText: nil,
    showsHistoryButton: false,
    isScrolledToBottom: .constant(true)
  )
  .background(Color.tidexBackground)
}  // swiftlint:disable:this file_length
