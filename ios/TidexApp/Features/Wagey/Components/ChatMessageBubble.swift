import SwiftUI

/// A chat message bubble component
/// User messages are right-aligned with blue background
/// Assistant messages are left-aligned with surface background
struct ChatMessageBubble: View {
  let message: ChatMessage

  /// Maximum width ratio for message bubbles (relative to screen width)
  private let maxWidthRatio: CGFloat = 0.8

  /// State for full-screen image viewer
  @State private var selectedImageViewer: SelectedImageViewer?

  var body: some View {
    HStack {
      if message.role == .user {
        Spacer(minLength: 40)
      }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xs) {
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
    .fullScreenCover(item: $selectedImageViewer) { viewer in
      ImageViewerOverlay(image: viewer.image) {
        selectedImageViewer = nil
      }
    }
  }

  // MARK: - Message Content Views

  private func userMessageContent(text: String) -> some View {
    Text(text)
      .font(.tidexBody)
      .foregroundColor(.tidexTextOnBrand)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexBlue)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous))
      .contextMenu {
        Button {
          UIPasteboard.general.string = text
        } label: {
          Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
        }
      }
  }

  private func assistantMessageContent(text: String) -> some View {
    FormattedMessageContent(content: text)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous))
      .contextMenu {
        Button {
          UIPasteboard.general.string = text
        } label: {
          Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
        }
      }
  }

  private func imageContent(attachment: ImageAttachment, isUser: Bool) -> some View {
    Group {
      if let uiImage = UIImage(data: attachment.data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: 200, maxHeight: 200)
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
              .strokeBorder(
                isUser ? Color.white.opacity(0.2) : Color.tidexBorder,
                lineWidth: 1
              )
          )
          .onTapGesture {
            selectedImageViewer = SelectedImageViewer(image: uiImage)
          }
          .contextMenu {
            Button {
              UIPasteboard.general.image = uiImage
            } label: {
              Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
            }
          }
      }
    }
  }
}

private struct SelectedImageViewer: Identifiable {
  let id = UUID()
  let image: UIImage
}

// MARK: - Image Viewer Overlay

/// Full-screen image viewer with zoom and dismiss gestures
struct ImageViewerOverlay: View {
  let image: UIImage
  let onDismiss: () -> Void

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
                onDismiss()
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
            onDismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 30))
              .foregroundColor(.white.opacity(0.8))
              .background(
                Circle()
                  .fill(Color.black.opacity(0.3))
              )
          }
          .padding(Spacing.mlg)
        }
        Spacer()
      }
    }
    .statusBarHidden()
  }
}

// MARK: - Typing Indicator

/// Three pulsing dots indicator, similar to iMessage typing indicator
struct TypingIndicatorView: View {
  @State private var dotScales: [Bool] = [false, false, false]

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(Color.tidexTextMuted)
          .frame(width: 7, height: 7)
          .scaleEffect(dotScales[index] ? 1.0 : 0.5)
          .opacity(dotScales[index] ? 1.0 : 0.4)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.msm)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous))
    .onAppear {
      for index in 0..<3 {
        withAnimation(
          .easeInOut(duration: 0.5)
            .repeatForever(autoreverses: true)
            .delay(Double(index) * 0.15)
        ) {
          dotScales[index] = true
        }
      }
    }
  }
}

// MARK: - Streaming Message Bubble

/// A bubble showing the currently streaming assistant response
struct StreamingMessageBubble: View {
  let contentBlocks: [ContentBlock]

  /// Whether any text block has content
  private var hasAnyText: Bool {
    contentBlocks.contains { block in
      if case .text(let text) = block, !text.isEmpty { return true }
      return false
    }
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        // If no content blocks yet, show typing indicator
        if contentBlocks.isEmpty {
          TypingIndicatorView()
        } else {
          // Render content blocks in chronological order
          ForEach(Array(contentBlocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .text(let text):
              if !text.isEmpty {
                streamingTextView(text: text)
              }
            case .toolCall(let toolCall):
              ToolStatusView(toolCall: toolCall)
            case .image:
              EmptyView()
            }
          }

          // If blocks exist but no text yet (e.g., only tool calls), show typing indicator
          if !hasAnyText {
            TypingIndicatorView()
          }
        }
      }

      Spacer(minLength: 40)
    }
  }

  private func streamingTextView(text: String) -> some View {
    Group {
      if let attributedString = try? AttributedString(
        markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
      {
        Text(attributedString)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
      } else {
        Text(text)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous))
  }
}

// MARK: - Previews

#Preview("User Message") {
  VStack(spacing: Spacing.md) {
    ChatMessageBubble(
      message: ChatMessage(
        id: "1",
        role: MessageRole.user,
        content: "Add a shift tomorrow from 9 to 17",
        toolCalls: nil,
        timestamp: Date()
      ))

    ChatMessageBubble(
      message: ChatMessage(
        id: "2",
        role: MessageRole.assistant,
        content:
          "I've added a shift for tomorrow from 09:00 to 17:00. You'll earn approximately **1,600 kr** before taxes.",
        toolCalls: nil,
        timestamp: Date()
      ))
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("With Table") {
  ScrollView {
    VStack(spacing: Spacing.md) {
      ChatMessageBubble(
        message: ChatMessage(
          id: "1",
          role: MessageRole.user,
          content: "Show me my shifts this week",
          toolCalls: nil,
          timestamp: Date()
        ))

      ChatMessageBubble(
        message: ChatMessage(
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
  ChatMessageBubble(
    message: ChatMessage(
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
    )
  )
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Streaming - Typing") {
  StreamingMessageBubble(contentBlocks: [])
    .padding()
    .background(Color.tidexBackground)
}

#Preview("Streaming - With Text") {
  StreamingMessageBubble(
    contentBlocks: [
      .text("I'm looking up your shifts for this week..."),
      .toolCall(
        ToolCall(
          id: "call_1",
          name: "get_shifts",
          arguments: nil,
          result: nil,
          success: nil
        )),
    ]
  )
  .padding()
  .background(Color.tidexBackground)
}
