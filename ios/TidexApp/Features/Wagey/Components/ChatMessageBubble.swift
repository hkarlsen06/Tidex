import SwiftUI

/// A chat message bubble component
/// User messages are right-aligned with blue background
/// Assistant messages are left-aligned with surface background
struct ChatMessageBubble: View {
  let message: ChatMessage
  var groupContext: ChatMessageGroupContext? = nil

  /// State for full-screen image viewer
  @State private var selectedImageViewer: SelectedImageViewer?

  private var renderBlocks: [ContentBlock] {
    ContentBlock.normalized(message.contentBlocks)
  }

  private var effectiveGroupContext: ChatMessageGroupContext {
    groupContext ?? .standalone(isCurrentUser: message.role == .user)
  }

  private var topPadding: CGFloat {
    effectiveGroupContext.joinsPrevious ? Spacing.micro : Spacing.xxs
  }

  private var bottomPadding: CGFloat {
    effectiveGroupContext.joinsNext ? Spacing.micro : Spacing.xxs
  }

  private var containsDeeplinkButton: Bool {
    renderBlocks.contains { block in
      if case .text(let text) = block {
        return WageyDeeplinkTextSplitter.containsDeeplink(in: text)
      }
      return false
    }
  }

  var body: some View {
    ChatMessageRow(isCurrentUser: message.role == .user) {
      // Render content blocks in chronological order
      ForEach(Array(renderBlocks.enumerated()), id: \.offset) { _, block in
        switch block {
        case .text(let text):
          if !text.isEmpty {
            if message.role == .user {
              userMessageContent(text: text)
            } else {
              assistantMessageSegments(text: text, forceStandaloneBubbles: containsDeeplinkButton)
            }
          }
        case .toolCall(let toolCall):
          ToolStatusView(toolCall: toolCall)
        case .image(let attachment):
          imageContent(attachment: attachment, isUser: message.role == .user)
        case .thoughtStatus(let status):
          thoughtStatusContent(status)
        }
      }

      if message.role == .assistant, let sources = message.sources, !sources.isEmpty {
        MessageSourcesView(sources: sources)
      }
    }
    .padding(.top, topPadding)
    .padding(.bottom, bottomPadding)
    .fullScreenCover(item: $selectedImageViewer) { viewer in
      ImageViewerOverlay(image: viewer.image) {
        selectedImageViewer = nil
      }
    }
  }

  // MARK: - Message Content Views

  private func userMessageContent(text: String) -> some View {
    ChatBubbleCard(isCurrentUser: true, groupContext: effectiveGroupContext) {
      Text(text)
        .font(.tidexBody)
        .foregroundColor(.tidexTextOnBrand)
    }
    .contextMenu {
      Button {
        UIPasteboard.general.string = text
      } label: {
        Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
      }
    }
  }

  @ViewBuilder
  private func assistantMessageSegments(text: String, forceStandaloneBubbles: Bool) -> some View {
    let segments = WageyDeeplinkTextSplitter.split(text)
    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
      switch segment {
      case .text(let text):
        assistantMessageContent(
          text: text,
          forceStandaloneBubble: forceStandaloneBubbles || segments.count > 1
        )
      case .deeplink(let title, let url):
        WageyDeeplinkButton(title: title, url: url)
      }
    }
  }

  private func assistantMessageContent(text: String, forceStandaloneBubble: Bool = false)
    -> some View
  {
    ChatBubbleCard(
      isCurrentUser: false,
      groupContext: forceStandaloneBubble
        ? .standalone(isCurrentUser: false) : effectiveGroupContext
    ) {
      FormattedMessageContent(content: text)
    }
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
                isUser ? Color.tidexTextOnBrand.opacity(0.22) : Color.tidexBorder.opacity(0.45),
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

  private func thoughtStatusContent(_ status: ThoughtStatus) -> some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: "brain.head.profile")
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexTextMuted)

      Text(status.localizedLabel)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextMuted)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xxs)
  }
}

private struct WageyDeeplinkButton: View {
  let title: String
  let url: URL

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button {
      Task { @MainActor in
        AppCoordinator.shared.handleDeepLink(url)
      }
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "arrow.up.forward.app")
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexBlue)
          .frame(width: 28, height: 28)
          .background(Color.tidexBlue.opacity(0.12))
          .clipShape(Circle())
          .accessibilityHidden(true)

        Text(title)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        Spacer(minLength: 0)

        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.tidexBlue)
          .accessibilityHidden(true)
      }
      .padding(.leading, Spacing.xs)
      .padding(.trailing, Spacing.sm)
      .padding(.vertical, Spacing.xxs)
      .frame(minHeight: 44)
      .frame(maxWidth: 320, alignment: .leading)
      .tidexGlass(
        shape: .capsule,
        tint: Color.tidexBlue.opacity(0.16),
        clear: true,
        interactive: true,
        fallbackOpacity: 0.9
      )
      .shadow(color: Color.tidexBlue.opacity(0.08), radius: 14, y: 5)
      .contentShape(Capsule())
    }
    .buttonStyle(WageyDeeplinkButtonStyle(reduceMotion: reduceMotion))
    .accessibilityLabel(Text(title))
    .contextMenu {
      Button {
        UIPasteboard.general.string = url.absoluteString
      } label: {
        Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
      }
    }
  }
}

private struct WageyDeeplinkButtonStyle: ButtonStyle {
  let reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.12),
        value: configuration.isPressed
      )
  }
}

private struct MessageSourcesView: View {
  let sources: [MessageSource]
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          Text(.wageySourcesTitle)
            .font(.tidexCaptionStrong)
            .foregroundColor(.tidexTextSecondary)

          Text("\(sources.count)")
            .font(.tidexCaptionRegular)
            .foregroundColor(.tidexTextMuted)

          Spacer(minLength: 0)

          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.tidexTextMuted)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(Color.tidexSurfaceSecondary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      }
      .buttonStyle(.plain)

      if isExpanded {
        ForEach(sources) { source in
          if let url = URL(string: source.url) {
            Link(destination: url) {
              HStack(alignment: .top, spacing: Spacing.xs) {
                faviconView(for: url)
                  .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                  Text(source.title)
                    .font(.tidexFootnoteMedium)
                    .foregroundColor(.tidexTextPrimary)
                    .multilineTextAlignment(.leading)

                  Text(source.domain)
                    .font(.tidexCaptionRegular)
                    .foregroundColor(.tidexTextMuted)
                }

                Spacer(minLength: 0)
              }
              .padding(.horizontal, Spacing.sm)
              .padding(.vertical, Spacing.xs)
              .background(Color.tidexSurfaceSecondary.opacity(0.55))
              .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            }
          }
        }
      }
    }
    .frame(maxWidth: 320, alignment: .leading)
  }

  @ViewBuilder
  private func faviconView(for pageURL: URL) -> some View {
    if let faviconURL = faviconURL(for: pageURL) {
      CachedAsyncImage(url: faviconURL) { image in
        image
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      } placeholder: {
        fallbackFavicon
      }
      .frame(width: 16, height: 16)
    } else {
      fallbackFavicon
    }
  }

  private var fallbackFavicon: some View {
    Image(systemName: "globe")
      .font(.tidexCaptionRegular)
      .foregroundColor(.tidexBlue)
      .frame(width: 16, height: 16)
  }

  private func faviconURL(for pageURL: URL) -> URL? {
    guard let scheme = pageURL.scheme, let host = pageURL.host else {
      return nil
    }

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = "/favicon.ico"
    return components.url
  }
}

private struct SelectedImageViewer: Identifiable {
  let id = UUID()
  let image: UIImage
}

// MARK: - Image Viewer Overlay

/// Full-screen image viewer with zoom and dismiss gestures
struct ImageViewerOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let image: UIImage
  let onDismiss: () -> Void
  let onSave: (() -> Void)?

  @State private var scale: CGFloat = 1.0
  @State private var lastScale: CGFloat = 1.0
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero

  init(
    image: UIImage,
    onDismiss: @escaping () -> Void,
    onSave: (() -> Void)? = nil
  ) {
    self.image = image
    self.onDismiss = onDismiss
    self.onSave = onSave
  }

  var body: some View {
    ZStack {
      // Background
      Color.tidexDarkBackgroundColor.ignoresSafeArea()

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
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
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
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                  offset = .zero
                }
                lastOffset = .zero
              }
            }
        )
        .onTapGesture(count: 2) {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
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
          if let onSave {
            Button(action: onSave) {
              Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(.tidexTextOnBrand.opacity(0.86))
                .background(
                  Circle()
                    .fill(Color.tidexDarkBackgroundColor.opacity(0.58))
                )
            }
            .accessibilityLabel(
              Text(String(localized: "friends.chat.action.save_image", table: "Localizable"))
            )
          }

          Spacer()

          Button {
            onDismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 30))
              .foregroundColor(.tidexTextOnBrand.opacity(0.86))
              .background(
                Circle()
                  .fill(Color.tidexDarkBackgroundColor.opacity(0.58))
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

// MARK: - Streaming Message Bubble

/// A bubble showing the currently streaming assistant response
struct StreamingMessageBubble: View {
  let contentBlocks: [ContentBlock]
  let isThinking: Bool
  var groupContext: ChatMessageGroupContext? = nil

  private var renderBlocks: [ContentBlock] {
    ContentBlock.normalized(contentBlocks)
  }

  /// Whether any text block has content
  private var hasAnyText: Bool {
    renderBlocks.contains { block in
      if case .text(let text) = block, !text.isEmpty { return true }
      return false
    }
  }

  private var effectiveGroupContext: ChatMessageGroupContext {
    groupContext ?? .standalone(isCurrentUser: false)
  }

  private var topPadding: CGFloat {
    effectiveGroupContext.joinsPrevious ? Spacing.micro : Spacing.xxs
  }

  private var bottomPadding: CGFloat {
    effectiveGroupContext.joinsNext ? Spacing.micro : Spacing.xxs
  }

  private var containsDeeplinkButton: Bool {
    renderBlocks.contains { block in
      if case .text(let text) = block {
        return WageyDeeplinkTextSplitter.containsDeeplink(in: text)
      }
      return false
    }
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        if renderBlocks.isEmpty {
          if isThinking {
            ThinkingStatusBubble()
          } else {
            TypingIndicatorView()
          }
        } else {
          ForEach(Array(renderBlocks.enumerated()), id: \.offset) { _, block in
            switch block {
            case .text(let text):
              if !text.isEmpty {
                streamingTextSegments(text: text, forceStandaloneBubbles: containsDeeplinkButton)
              }
            case .toolCall(let toolCall):
              ToolStatusView(toolCall: toolCall)
            case .image:
              EmptyView()
            case .thoughtStatus(let status):
              ThinkingDurationInlineView(status: status)
            }
          }

          if isThinking {
            ThinkingStatusBubble()
          } else if !hasAnyText {
            TypingIndicatorView()
          }
        }
      }

      Spacer(minLength: 40)
    }
    .padding(.top, topPadding)
    .padding(.bottom, bottomPadding)
  }

  @ViewBuilder
  private func streamingTextSegments(text: String, forceStandaloneBubbles: Bool) -> some View {
    let segments = WageyDeeplinkTextSplitter.split(text)
    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
      switch segment {
      case .text(let text):
        streamingTextView(
          text: text,
          forceStandaloneBubble: forceStandaloneBubbles || segments.count > 1
        )
      case .deeplink(let title, let url):
        WageyDeeplinkButton(title: title, url: url)
      }
    }
  }

  private func streamingTextView(text: String, forceStandaloneBubble: Bool = false) -> some View {
    Group {
      if let attributedString = try? AttributedString(
        markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
      {
        ChatBubbleCard(
          isCurrentUser: false,
          groupContext: forceStandaloneBubble
            ? .standalone(isCurrentUser: false) : effectiveGroupContext
        ) {
          Text(attributedString)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
        }
      } else {
        ChatBubbleCard(
          isCurrentUser: false,
          groupContext: forceStandaloneBubble
            ? .standalone(isCurrentUser: false) : effectiveGroupContext
        ) {
          Text(text)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
        }
      }
    }
  }
}

private struct ThinkingDurationInlineView: View {
  let status: ThoughtStatus

  var body: some View {
    HStack(spacing: Spacing.xxs) {
      Image(systemName: "brain.head.profile")
        .font(.tidexCaptionStrong)
        .foregroundColor(.tidexTextMuted)

      Text(status.localizedLabel)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextMuted)
    }
    .padding(.horizontal, Spacing.sm)
    .padding(.vertical, Spacing.xxs)
  }
}

private struct ThinkingStatusBubble: View {
  var body: some View {
    HStack(spacing: 0) {
      Text(.wageyStreamingThinkingTitle)
        .font(.tidexFootnoteMedium)
        .foregroundColor(.tidexTextSecondary)

      InlineJumpingDotsView()
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.msm)
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
  StreamingMessageBubble(contentBlocks: [], isThinking: true)
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
    ],
    isThinking: true
  )
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Streaming - Thinking After Tool") {
  StreamingMessageBubble(
    contentBlocks: [
      .toolCall(
        ToolCall(
          id: "call_1",
          name: "web_search",
          arguments: nil,
          result: "{\"status\":\"completed\"}",
          success: true
        ))
    ],
    isThinking: true
  )
  .padding()
  .background(Color.tidexBackground)
}
