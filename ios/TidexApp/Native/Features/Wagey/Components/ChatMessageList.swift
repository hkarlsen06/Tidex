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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Empty state when no messages
                    if messages.isEmpty && !isStreaming {
                        emptyStateView
                            .padding(.top, 40)
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
                    }

                    // Bottom anchor for scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
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
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Wagey icon
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.tidexBlue)

            VStack(spacing: 8) {
                Text(.wageyEmptyStateTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Text(.wageyEmptyStateSubtitle)
                    .font(.system(size: 15))
                    .foregroundColor(.tidexTextSecondary)
                    .multilineTextAlignment(.center)
            }

            // Suggestion chips
            VStack(spacing: 12) {
                suggestionChip(String(localized: .wageyEmptyStateSuggestion1))
                suggestionChip(String(localized: .wageyEmptyStateSuggestion2))
                suggestionChip(String(localized: .wageyEmptyStateSuggestion3))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
    }

    private func suggestionChip(_ text: String) -> some View {
        Button {
            Haptics.play(.light)
            onSuggestionTapped?(text)
        } label: {
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.tidexBlue)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.tidexBlue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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
                content: "You have 3 shifts scheduled this week:\n\n- Monday: 09:00-17:00\n- Wednesday: 14:00-22:00\n- Friday: 08:00-16:00\n\nTotal: 24 hours, approximately **4,800 kr** before taxes.",
                toolCalls: [
                    ToolCall(id: "call_1", name: "get_shifts", arguments: nil, result: "{}", success: true)
                ],
                timestamp: Date()
            )
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
            .toolCall(ToolCall(id: "call_1", name: "manage_shift", arguments: nil, result: nil, success: nil))
        ],
        isStreaming: true
    )
    .background(Color.tidexBackground)
}
