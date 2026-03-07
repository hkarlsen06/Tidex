import SwiftUI

/// Main Wagey chat view
/// Composes the header, message list, input field, and conversation sidebar
struct WageyView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Binding private var selectedTab: MainTabView.Tab

  /// Shared ViewModel for managing chat state
  /// Using shared instance ensures conversation persists when dismissing and reopening Wagey
  private let viewModel = WageyViewModel.shared

  /// Whether to show the conversation history sheet
  @State private var showHistory = false

  init(selectedTab: Binding<MainTabView.Tab>) {
    _selectedTab = selectedTab
  }

  /// Input text for the chat field
  @State private var inputText: String = ""

  /// Whether to show the paywall when limit is reached
  @State private var showPaywall = false

  /// Pending message to send after upgrade
  @State private var pendingMessage: String?

  /// Whether the chat list is currently pinned to the bottom
  @State private var isChatScrolledToBottom = true

  /// Triggers an imperative scroll-to-bottom inside the chat list
  @State private var scrollToBottomTrigger = 0

  /// Explicit visibility state for the post-stream scroll affordance
  @State private var showScrollToBottomButton = false

  /// Measured height of the floating bottom chrome so messages can scroll underneath it.
  @State private var bottomChromeHeight: CGFloat = Spacing.bottomScrollMargin

  private var isShowingWelcomeState: Bool {
    viewModel.messages.isEmpty && !viewModel.isStreaming
  }

  private var showsScrollToBottomButton: Bool {
    showScrollToBottomButton
      && !viewModel.isStreaming
      && !isChatScrolledToBottom
      && (!viewModel.messages.isEmpty || !viewModel.activeContentBlocks.isEmpty)
  }

  var body: some View {
    Group {
      if !viewModel.hasResolvedEntryState {
        onboardingStatePlaceholder
      } else if viewModel.shouldShowShowcase {
        // Show showcase first so the user learns what Wagey is
        WageyShowcaseView(
          onTryWagey: {
            viewModel.markShowcaseSeen()
          }
        )
        .environmentObject(coordinator)
      } else if viewModel.shouldShowConsent {
        // Then ask for data-sharing consent before using Wagey
        WageyConsentView(
          onAgree: {
            viewModel.grantAIConsent()
          },
          onDecline: {
            selectedTab = .home
          }
        )
      } else {
        chatInterface
      }
    }
    .task(id: coordinator.userId) {
      viewModel.loadConversations()
      await viewModel.fetchWageyUsage()
    }
  }

  // MARK: - Chat Interface

  private var chatInterface: some View {
    NavigationStack {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        mainContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .navigationBarTitleDisplayMode(.inline)
      .iPadToolbarBackground()
      .toolbarBackground(.hidden, for: .tabBar)
      .toolbar {
        if shouldShowUsageSubtitle {
          ToolbarItem(placement: .topBarLeading) {
            messagesRemainingBadge
          }
          .sharedBackgroundVisibility(.hidden)
        }

        if !isShowingWelcomeState {
          ToolbarItem(placement: .principal) {
            headerTitle
          }
        }

        if !isShowingWelcomeState {
          ToolbarItem(placement: .topBarTrailing) {
            newChatButton
          }
        }

        if isShowingWelcomeState && !viewModel.conversations.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            historyButton
          }

          ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }

        if isShowingWelcomeState {
          ToolbarItem(placement: .topBarTrailing) {
            UserMenuButton(
              displayName: coordinator.userDisplayName,
              avatarUrl: coordinator.userAvatarUrl
            )
          }
        }

        if !isShowingWelcomeState && !viewModel.conversations.isEmpty {
          ToolbarItem(placement: .topBarTrailing) {
            historyButton
          }
        }
      }
      .iPadToolbarTransaction()
    }
    .sheet(isPresented: $showHistory) {
      conversationHistorySheet
    }
    .sheet(isPresented: $showPaywall, onDismiss: handlePaywallDismiss) {
      PaywallView(contextType: .wageyLimit)
        .interactiveDismissDisabled()
    }
    .alert(
      String(localized: .wageyErrorUnknown),
      isPresented: .init(
        get: { viewModel.error != nil },
        set: { if !$0 { viewModel.dismissError() } }
      )
    ) {
      Button("OK", role: .cancel) {
        viewModel.dismissError()
      }
    } message: {
      if let error = viewModel.error {
        Text(error.localizedDescription)
      }
    }
    .onChange(of: viewModel.limitReached) { _, isLimitReached in
      if isLimitReached && !showPaywall {
        showPaywall = true
      }
    }
  }

  private var onboardingStatePlaceholder: some View {
    Color.tidexBackground
      .ignoresSafeArea()
  }

  /// Handle paywall dismiss - check if user upgraded
  private func handlePaywallDismiss() {
    Task {
      await viewModel.fetchWageyUsage()

      if !viewModel.limitReached, let message = pendingMessage {
        pendingMessage = nil
        await viewModel.sendMessage(message)
      }
    }
  }

  // MARK: - Main Content

  private var mainContent: some View {
    ZStack(alignment: .bottomTrailing) {
      VStack(spacing: 0) {
        // Entitlement sync banner (when server/StoreKit mismatch detected)
        if let syncMessage = viewModel.entitlementSyncMessage {
          entitlementSyncBanner(syncMessage)
        }

        // Message list
        ChatMessageList(
          messages: viewModel.messages,
          streamingContentBlocks: viewModel.activeContentBlocks,
          isStreaming: viewModel.isStreaming,
          isThinking: viewModel.isModelThinking,
          remainingMessagesText: nil,
          showsHistoryButton: false,
          bottomContentInset: bottomChromeHeight + Spacing.lg,
          isScrolledToBottom: $isChatScrolledToBottom,
          scrollToBottomTrigger: scrollToBottomTrigger,
          onStreamEndedAwayFromBottom: {
            showScrollToBottomButton = true
          },
          onSuggestionTapped: { suggestion in
            inputText = suggestion
          }
        )
      }

      if showsScrollToBottomButton {
        scrollToBottomButton
          .padding(.trailing, MonthPickerLayout.horizontalPadding)
          .padding(.bottom, bottomChromeHeight + Spacing.md)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .overlay(alignment: .bottom) {
      bottomChrome
    }
    .animation(.easeInOut(duration: 0.2), value: showsScrollToBottomButton)
    .onPreferenceChange(WageyBottomChromeHeightPreferenceKey.self) { value in
      bottomChromeHeight = value
    }
    .onChange(of: viewModel.isStreaming) { _, isStreaming in
      if isStreaming {
        showScrollToBottomButton = false
      }
    }
    .onChange(of: isChatScrolledToBottom) { _, isScrolledToBottom in
      if isScrolledToBottom {
        showScrollToBottomButton = false
      }
    }
  }

  private var bottomChrome: some View {
    VStack(spacing: 0) {
      if viewModel.isConversationLong {
        conversationLengthWarning
      }

      ChatInputField(
        inputText: $inputText,
        onSend: { content in
          handleSendMessage(content)
        },
        onSendWithImage: { content, image in
          handleSendMessageWithImage(content, image: image)
        },
        disabled: viewModel.isStreaming
      )
    }
    .background(
      GeometryReader { geometry in
        Color.clear.preference(
          key: WageyBottomChromeHeightPreferenceKey.self,
          value: geometry.size.height
        )
      }
    )
  }

  // MARK: - Entitlement Sync Banner

  @ViewBuilder
  private func entitlementSyncBanner(_ message: String) -> some View {
    HStack(spacing: Spacing.xs) {
      if viewModel.isSyncingEntitlement {
        ProgressView()
          .scaleEffect(0.8)
      } else {
        Image(
          systemName: message.contains("Could not") || message.contains("Kunne ikke")
            ? "exclamationmark.triangle.fill"
            : "checkmark.circle.fill"
        )
        .foregroundColor(
          message.contains("Could not") || message.contains("Kunne ikke")
            ? .tidexWarning
            : .tidexSuccess)
      }

      Text(message)
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextPrimary)

      Spacer()

      Button {
        viewModel.dismissEntitlementSyncMessage()
      } label: {
        Image(systemName: "xmark")
          .font(.tidexMicro)
          .foregroundColor(.tidexTextMuted)
      }
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.xsm)
    .background(Color.tidexSurfaceSecondary)
  }

  // MARK: - Conversation Length Warning

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
  }

  // MARK: - Message Handling

  /// Handle sending a message, showing paywall if limit reached
  private func handleSendMessage(_ content: String) {
    handleSendMessageWithImage(content, image: nil)
  }

  /// Handle sending a message with an image, showing paywall if limit reached
  private func handleSendMessageWithImage(_ content: String, image: ImageAttachment?) {
    if viewModel.limitReached {
      if viewModel.remainingMessagesCount > 0 {
        viewModel.resetLimitReached()
      } else {
        pendingMessage = content
        showPaywall = true
        return
      }
    }

    // Send the message (with or without image)
    Task {
      await viewModel.sendMessage(content, image: image)
    }
  }

  // MARK: - Conversation History Sheet

  private var conversationHistorySheet: some View {
    NavigationStack {
      ConversationSidebarView(
        conversations: viewModel.conversations,
        currentConversationId: viewModel.currentConversationId,
        onSelectConversation: { id in
          viewModel.loadConversation(id: id)
          showHistory = false
        },
        onNewConversation: {
          viewModel.startNewConversation()
          showHistory = false
        },
        onDeleteConversation: { id in
          viewModel.deleteConversation(id: id)
        }
      )
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: .commonDone)) {
            showHistory = false
          }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  // MARK: - Header Components

  /// Localized conversation title - translates "New Conversation" to current locale
  private var localizedConversationTitle: String {
    let title = viewModel.currentConversationTitle
    if title == "New Conversation" {
      return String(localized: .wageyNewConversation)
    }
    return title
  }

  /// Show usage subtitle only when nearing the limit (>= 50% used)
  private var shouldShowUsageSubtitle: Bool {
    guard viewModel.messageLimit > 0 else { return false }
    let usage = Double(viewModel.messagesUsed) / Double(viewModel.messageLimit)
    return usage >= 0.5
  }

  private var headerTitle: some View {
    Text(localizedConversationTitle)
      .font(.tidexBodyMedium)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(1)
  }

  private var messagesRemainingBadge: some View {
    Text(
      isShowingWelcomeState
        ? String(localized: .wageyMessagesRemaining(Int32(viewModel.remainingMessagesCount)))
        : "\(viewModel.remainingMessagesCount)"
    )
    .font(.tidexFootnote)
    .monospacedDigit()
    .foregroundColor(
      viewModel.remainingMessagesCount <= 3 ? .tidexWarning : .tidexTextSecondary
    )
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityLabel(
      Text(String(localized: .wageyMessagesRemaining(Int32(viewModel.remainingMessagesCount))))
    )
  }

  private var historyButton: some View {
    Button {
      Haptics.play(.light)
      showHistory = true
    } label: {
      Image(systemName: "clock.arrow.circlepath")
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  private var newChatButton: some View {
    Button {
      Haptics.play(.light)
      viewModel.startNewConversation()
    } label: {
      Image(systemName: "square.and.pencil")
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextSecondary)
        .offset(y: -1)
    }
    .disabled(viewModel.messages.isEmpty && !viewModel.isStreaming)
    .opacity(viewModel.messages.isEmpty && !viewModel.isStreaming ? 0.4 : 1)
  }

  private var scrollToBottomButton: some View {
    Button {
      Haptics.play(.light)
      showScrollToBottomButton = false
      scrollToBottomTrigger += 1
    } label: {
      Image(systemName: "arrow.down")
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
        .frame(width: 44, height: 44)
        .background(Color.tidexSurfacePrimary.opacity(0.96))
        .overlay(
          Circle()
            .stroke(Color.tidexBorder.opacity(0.45), lineWidth: 1)
        )
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(String(localized: "wagey.chat.jump_to_latest")))
  }
}

private struct WageyBottomChromeHeightPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = Spacing.bottomScrollMargin

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

// MARK: - Previews

#Preview("Empty") {
  PreviewWageyView()
}

#Preview("With Messages") {
  // Note: For preview purposes, the view will show empty state
  // as we can't inject state into @State property from preview
  PreviewWageyView()
}

@MainActor
private struct PreviewWageyView: View {
  @StateObject private var coordinator = AppCoordinator.shared
  @State private var selectedTab: MainTabView.Tab = .wagey

  var body: some View {
    WageyView(selectedTab: $selectedTab)
      .environmentObject(coordinator)
  }
}
