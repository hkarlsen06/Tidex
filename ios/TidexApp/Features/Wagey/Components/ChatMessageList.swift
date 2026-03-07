import SwiftUI

/// Scrollable list of chat messages with auto-scroll to bottom
struct ChatMessageList: View {
  private let pinnedBottomThreshold: CGFloat = 44

  let messages: [ChatMessage]
  let streamingContentBlocks: [ContentBlock]
  let isStreaming: Bool
  let isThinking: Bool
  let remainingMessagesText: String?
  let showsHistoryButton: Bool

  /// Callback when a suggestion chip is tapped
  var onSuggestionTapped: ((String) -> Void)?
  var onHistoryTapped: (() -> Void)?

  /// Whether the "Copied!" confirmation is showing
  @State private var showCopiedConfirmation = false
  @State private var showsSuggestions = false
  @State private var scrollTask: Task<Void, Never>?
  @State private var bottomAnchorMaxY: CGFloat = 0
  @State private var viewportMaxY: CGFloat = 0
  @State private var isPinnedToBottom = true
  @State private var suppressAutoFollow = false

  private struct ScrollState: Equatable {
    let messageCount: Int
    let lastMessageID: String?
    let streamingSignature: Int
    let isStreaming: Bool
  }

  private var scrollState: ScrollState {
    ScrollState(
      messageCount: messages.count,
      lastMessageID: messages.last?.id,
      streamingSignature: streamingContentSignature,
      isStreaming: isStreaming || isThinking
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
      }
    }
  }

  private var showsJumpToLatestButton: Bool {
    !isPinnedToBottom && (isStreaming || !messages.isEmpty)
  }

  private var shouldAutoFollow: Bool {
    isPinnedToBottom && !suppressAutoFollow
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: Spacing.sm) {
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
              StreamingMessageBubble(
                contentBlocks: streamingContentBlocks,
                isThinking: isThinking
              )
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
            .background(
              GeometryReader { geometry in
                Color.clear.preference(
                  key: ChatBottomAnchorMaxYPreferenceKey.self,
                  value: geometry.frame(in: .global).maxY
                )
              }
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
      }
      .background(
        GeometryReader { geometry in
          Color.clear.preference(
            key: ChatViewportMaxYPreferenceKey.self,
            value: geometry.frame(in: .global).maxY
          )
        }
      )
      .simultaneousGesture(
        DragGesture(minimumDistance: 4)
          .onChanged { _ in
            suppressAutoFollow = true
          }
      )
      .onAppear {
        isPinnedToBottom = true
        suppressAutoFollow = false
        scheduleScrollToBottom(proxy: proxy, animated: false)
      }
      .onChange(of: scrollState) { oldValue, newValue in
        handleScrollStateChange(from: oldValue, to: newValue, proxy: proxy)
      }
      .onPreferenceChange(ChatBottomAnchorMaxYPreferenceKey.self) { value in
        bottomAnchorMaxY = value
        updatePinnedToBottom()
      }
      .onPreferenceChange(ChatViewportMaxYPreferenceKey.self) { value in
        viewportMaxY = value
        updatePinnedToBottom()
      }
      .overlay(alignment: .bottomTrailing) {
        if showsJumpToLatestButton {
          jumpToLatestButton(proxy: proxy)
            .padding(.trailing, Spacing.lg)
            .padding(.bottom, Spacing.lg)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .onDisappear {
        scrollTask?.cancel()
        scrollTask = nil
      }
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
      ("banknote.fill", String(localized: .wageyEmptyStateSuggestion2)),
      ("list.clipboard.fill", String(localized: .wageyEmptyStateSuggestion3)),
      (
        "arrow.trianglehead.2.clockwise.rotate.90.circle.fill",
        String(localized: .wageyEmptyStateSuggestion4)
      ),
    ]
  }

  private var emptyStateView: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      welcomeHero

      if showsSuggestions {
        VStack(spacing: Spacing.sm) {
          ForEach(suggestions, id: \.text) { suggestion in
            suggestionRow(icon: suggestion.icon, text: suggestion.text)
          }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .padding(.horizontal, Spacing.md)
  }

  private var welcomeHero: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              Color.tidexSurfacePrimary,
              Color.tidexSurfacePrimary.opacity(0.95),
              Color.tidexBlue.opacity(0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      Circle()
        .fill(Color.tidexBlue.opacity(0.12))
        .frame(width: 180, height: 180)
        .blur(radius: 42)
        .offset(x: -16, y: -52)

      Circle()
        .fill(Color.white.opacity(0.08))
        .frame(width: 120, height: 120)
        .blur(radius: 40)
        .offset(x: 180, y: 24)

      VStack(alignment: .leading, spacing: Spacing.md) {
        HStack {
          Spacer()

          if showsHistoryButton {
            Button {
              Haptics.play(.light)
              onHistoryTapped?()
            } label: {
              Image(systemName: "clock.arrow.circlepath")
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexTextSecondary)
                .frame(width: 40, height: 40)
                .background(Color.tidexSurfacePrimary.opacity(0.9))
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Conversation history"))
          }
        }

        HStack(alignment: .top, spacing: Spacing.md) {
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
              .background(Color.tidexSurfaceSecondary.opacity(0.8))
              .clipShape(Capsule())
          }

          if !showsSuggestions {
            Button {
              withAnimation(.easeInOut(duration: 0.2)) {
                showsSuggestions = true
              }
            } label: {
              HStack(spacing: Spacing.xs) {
                Image(systemName: "sparkles")
                  .font(.tidexFootnoteStrong)

                Text(.wageyEmptyStateQuickStart)
                  .font(.tidexButton)
              }
              .foregroundColor(.tidexTextOnBrand)
              .padding(.horizontal, Spacing.md)
              .padding(.vertical, Spacing.sm)
              .background(Color.tidexBrandPrimary)
              .clipShape(Capsule())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(Spacing.lg)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous))
    .tidexCardShadow(cornerRadius: CornerRadius.card)
  }

  private func suggestionRow(icon: String, text: String) -> some View {
    Button {
      Haptics.play(.light)
      onSuggestionTapped?(text)
    } label: {
      HStack(spacing: Spacing.md) {
        ZStack {
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .fill(Color.tidexBlue.opacity(0.14))
            .frame(width: 44, height: 44)

          Image(systemName: icon)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexBlue)
        }

        VStack(alignment: .leading, spacing: Spacing.xxs) {
          Text(text)
            .font(.tidexBodyMedium)
            .foregroundColor(.tidexTextPrimary)
            .multilineTextAlignment(.leading)
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
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

  private func scheduleScrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
    scrollTask?.cancel()
    scrollTask = Task { @MainActor in
      await Task.yield()
      await Task.yield()
      guard !Task.isCancelled else { return }

      if animated {
        withAnimation(.easeOut(duration: 0.2)) {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      } else {
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
  }

  private func handleScrollStateChange(
    from oldValue: ScrollState,
    to newValue: ScrollState,
    proxy: ScrollViewProxy
  ) {
    let startedStreaming = !oldValue.isStreaming && newValue.isStreaming
    let appendedMessage =
      oldValue.messageCount != newValue.messageCount
      || oldValue.lastMessageID != newValue.lastMessageID
    let updatedStreamingContent = oldValue.streamingSignature != newValue.streamingSignature

    if startedStreaming {
      scheduleScrollToBottom(proxy: proxy, animated: false)
      return
    }

    if appendedMessage {
      guard shouldAutoFollow else { return }
      let shouldAnimate = !newValue.isStreaming
      scheduleScrollToBottom(proxy: proxy, animated: shouldAnimate)
      return
    }

    guard updatedStreamingContent, shouldAutoFollow else { return }
    scheduleScrollToBottom(proxy: proxy, animated: false)
  }

  private func updatePinnedToBottom() {
    guard viewportMaxY > 0, bottomAnchorMaxY > 0 else { return }
    let distanceFromBottom = bottomAnchorMaxY - viewportMaxY
    let isNearBottom = distanceFromBottom <= pinnedBottomThreshold
    isPinnedToBottom = isNearBottom
    if isNearBottom {
      suppressAutoFollow = false
    }
  }

  private func jumpToLatestButton(proxy: ScrollViewProxy) -> some View {
    Button {
      Haptics.play(.light)
      isPinnedToBottom = true
      suppressAutoFollow = false
      scheduleScrollToBottom(proxy: proxy, animated: true)
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "arrow.down")
          .font(.tidexFootnoteStrong)

        Text(String(localized: "wagey.chat.jump_to_latest"))
          .font(.tidexFootnoteStrong)
      }
      .foregroundColor(.tidexTextPrimary)
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexSurfacePrimary.opacity(0.96))
      .overlay(
        Capsule()
          .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
      )
      .clipShape(Capsule())
      .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(String(localized: "wagey.chat.jump_to_latest")))
  }
}

private struct ChatBottomAnchorMaxYPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

private struct ChatViewportMaxYPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - Previews

#Preview("Empty State") {
  ChatMessageList(
    messages: [],
    streamingContentBlocks: [],
    isStreaming: false,
    isThinking: false,
    remainingMessagesText: "15 messages left",
    showsHistoryButton: true
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
    isStreaming: false,
    isThinking: false,
    remainingMessagesText: nil,
    showsHistoryButton: true
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
    isStreaming: true,
    isThinking: true,
    remainingMessagesText: nil,
    showsHistoryButton: false
  )
  .background(Color.tidexBackground)
}
