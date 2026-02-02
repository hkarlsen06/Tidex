import SwiftUI

/// A chat message bubble component
/// User messages are right-aligned with blue background
/// Assistant messages are left-aligned with surface background
struct ChatMessageBubble: View {
    let message: ChatMessage

    /// Maximum width ratio for message bubbles (relative to screen width)
    private let maxWidthRatio: CGFloat = 0.8

    /// State for full-screen image viewer
    @State private var selectedImage: UIImage?
    @State private var showImageViewer = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Render content blocks in chronological order
                ForEach(Array(message.contentBlocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        if !text.isEmpty {
                            if message.role == .user {
                                userMessageContent(text: text)
                            } else {
                                assistantMessageContent(text: text)
                            }
                        }
                    case .toolCall(let toolCall):
                        ToolStatusView(toolCall: toolCall)
                    case .image(let attachment):
                        imageContent(attachment: attachment, isUser: message.role == .user)
                    }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            if let image = selectedImage {
                ImageViewerOverlay(image: image, isPresented: $showImageViewer)
            }
        }
    }

    // MARK: - Message Content Views

    private func userMessageContent(text: String) -> some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.tidexBlue)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func assistantMessageContent(text: String) -> some View {
        // For assistant messages, use FormattedMessageContent for rich formatting (tables, markdown)
        FormattedMessageContent(content: text)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.tidexSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func imageContent(attachment: ImageAttachment, isUser: Bool) -> some View {
        Group {
            if let uiImage = UIImage(data: attachment.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                isUser ? Color.white.opacity(0.2) : Color.tidexBorder,
                                lineWidth: 1
                            )
                    )
                    .onTapGesture {
                        selectedImage = uiImage
                        showImageViewer = true
                    }
            }
        }
    }
}

// MARK: - Image Viewer Overlay

/// Full-screen image viewer with zoom and dismiss gestures
struct ImageViewerOverlay: View {
    let image: UIImage
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Image with zoom
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let delta = value.magnification / lastScale
                            lastScale = value.magnification
                            scale = min(max(scale * delta, 1), 4)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            // Reset if zoomed out
                            if scale <= 1 {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = 1
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            } else {
                                // Drag down to dismiss when not zoomed
                                offset = CGSize(width: 0, height: max(0, value.translation.height))
                            }
                        }
                        .onEnded { value in
                            lastOffset = offset
                            // Dismiss if dragged down far enough when not zoomed
                            if scale <= 1 && value.translation.height > 100 {
                                isPresented = false
                            } else if scale <= 1 {
                                withAnimation(.spring(response: 0.3)) {
                                    offset = .zero
                                }
                                lastOffset = .zero
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1 {
                            scale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2
                        }
                    }
                }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                            )
                    }
                    .padding(20)
                }
                Spacer()
            }
        }
        .statusBarHidden()
    }
}

// MARK: - Streaming Message Bubble

/// A bubble showing the currently streaming assistant response
struct StreamingMessageBubble: View {
    let contentBlocks: [ContentBlock]

    /// Whether to show the cursor animation
    @State private var showCursor = true

    /// Check if the last block is a text block (cursor should appear after it)
    private var lastBlockIsText: Bool {
        if case .text = contentBlocks.last {
            return true
        }
        return false
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                // Render content blocks in chronological order
                ForEach(Array(contentBlocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .text(let text):
                        // Show cursor after the last text block
                        let isLastBlock = index == contentBlocks.count - 1
                        streamingTextView(text: text, showCursor: isLastBlock)
                    case .toolCall(let toolCall):
                        ToolStatusView(toolCall: toolCall)
                    case .image:
                        // Images are not expected in assistant streaming messages
                        EmptyView()
                    }
                }

                // If no blocks yet or last block isn't text, show empty text with cursor
                if contentBlocks.isEmpty || !lastBlockIsText {
                    streamingTextView(text: "", showCursor: true)
                }
            }

            Spacer(minLength: 40)
        }
        .onAppear {
            startCursorAnimation()
        }
    }

    private func streamingTextView(text: String, showCursor: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            // Try to render markdown for the streaming text
            if !text.isEmpty {
                if let attributedString = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(attributedString)
                        .font(.system(size: 16))
                        .foregroundColor(.tidexTextPrimary)
                } else {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundColor(.tidexTextPrimary)
                }
            }

            // Blinking cursor (only shown on the last text block)
            if showCursor {
                Text("|")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexBlue)
                    .opacity(self.showCursor ? 1 : 0)
            }
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
        contentBlocks: [
            .text("I'm looking up your shifts for this week..."),
            .toolCall(ToolCall(
                id: "call_1",
                name: "get_shifts",
                arguments: nil,
                result: nil,
                success: nil
            ))
        ]
    )
    .padding()
    .background(Color.tidexBackground)
}
