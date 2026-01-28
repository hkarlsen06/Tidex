import SwiftUI

/// A chat message bubble component
/// User messages are right-aligned with blue background
/// Assistant messages are left-aligned with surface background
struct ChatMessageBubble: View {
    let message: ChatMessage

    /// Maximum width ratio for message bubbles (relative to screen width)
    private let maxWidthRatio: CGFloat = 0.8

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Tool calls (shown before message content for assistant messages)
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { toolCall in
                        ToolStatusView(toolCall: toolCall)
                    }
                }

                // Message content
                if !message.content.isEmpty {
                    messageContentView
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Message Content View

    @ViewBuilder
    private var messageContentView: some View {
        Group {
            if message.role == .user {
                userMessageContent
            } else {
                assistantMessageContent
            }
        }
    }

    private var userMessageContent: some View {
        Text(message.content)
            .font(.system(size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.tidexBlue)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var assistantMessageContent: some View {
        // For assistant messages, use FormattedMessageContent for rich formatting (tables, markdown)
        FormattedMessageContent(content: message.content)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.tidexSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Streaming Message Bubble

/// A bubble showing the currently streaming assistant response
struct StreamingMessageBubble: View {
    let text: String
    let toolCalls: [ToolCall]

    /// Whether to show the cursor animation
    @State private var showCursor = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                // Tool calls in progress
                ForEach(toolCalls) { toolCall in
                    ToolStatusView(toolCall: toolCall)
                }

                // Streaming text with cursor
                if !text.isEmpty || toolCalls.isEmpty {
                    streamingTextView
                }
            }

            Spacer(minLength: 40)
        }
        .onAppear {
            startCursorAnimation()
        }
    }

    private var streamingTextView: some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Try to render markdown for the streaming text
            if let attributedString = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributedString)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)
            } else {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)
            }

            // Blinking cursor
            Text("|")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tidexBlue)
                .opacity(showCursor ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func startCursorAnimation() {
        // Simple cursor blink animation
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                showCursor.toggle()
            }
        }
    }
}

// MARK: - Previews

#Preview("User Message") {
    VStack(spacing: 16) {
        ChatMessageBubble(message: ChatMessage(
            id: "1",
            role: MessageRole.user,
            content: "Add a shift tomorrow from 9 to 17",
            toolCalls: nil,
            timestamp: Date()
        ))

        ChatMessageBubble(message: ChatMessage(
            id: "2",
            role: MessageRole.assistant,
            content: "I've added a shift for tomorrow from 09:00 to 17:00. You'll earn approximately **1,600 kr** before taxes.",
            toolCalls: nil,
            timestamp: Date()
        ))
    }
    .padding()
    .background(Color.tidexBackground)
}

#Preview("With Table") {
    ScrollView {
        VStack(spacing: 16) {
            ChatMessageBubble(message: ChatMessage(
                id: "1",
                role: MessageRole.user,
                content: "Show me my shifts this week",
                toolCalls: nil,
                timestamp: Date()
            ))

            ChatMessageBubble(message: ChatMessage(
                id: "2",
                role: MessageRole.assistant,
                content: """
                Here are your shifts for this week:

                ```
                Day\tDate\tHours\tGross
                Monday\tJan 27\t8.0\t1,600 kr
                Wednesday\tJan 29\t6.5\t1,300 kr
                Friday\tJan 31\t7.5\t1,500 kr
                ```

                Total: **4,400 kr** before taxes.
                """,
                toolCalls: nil,
                timestamp: Date()
            ))
        }
        .padding()
    }
    .background(Color.tidexBackground)
}

#Preview("With Tool Call") {
    ChatMessageBubble(message: ChatMessage(
        id: "1",
        role: MessageRole.assistant,
        content: "Done! I've added the shift to your calendar.",
        toolCalls: [
            ToolCall(
                id: "call_1",
                name: "manage_shift",
                arguments: nil,
                result: "{\"success\": true}",
                success: true
            )
        ],
        timestamp: Date()
    ))
    .padding()
    .background(Color.tidexBackground)
}

#Preview("Streaming") {
    StreamingMessageBubble(
        text: "I'm looking up your shifts for this week...",
        toolCalls: [
            ToolCall(
                id: "call_1",
                name: "get_shifts",
                arguments: nil,
                result: nil,
                success: nil
            )
        ]
    )
    .padding()
    .background(Color.tidexBackground)
}
