import SwiftUI

/// Main Wagey chat view
/// Composes the header, message list, input field, and conversation sidebar
struct WageyView: View {
  @EnvironmentObject private var coordinator: AppCoordinator
  @Environment(\.dismiss) private var dismiss

  /// Shared ViewModel for managing chat state
  /// Using shared instance ensures conversation persists when dismissing and reopening Wagey
  private let viewModel = WageyViewModel.shared

  /// Whether to show the conversation history sheet
  @State private var showHistory = false

  /// Whether to show the showcase for first-time free users
  /// Initialize based on ViewModel state so it shows immediately
  @State private var showShowcase: Bool

  init() {
    // Check if showcase should be shown at initialization time
    _showShowcase = State(initialValue: WageyViewModel.shared.shouldShowShowcase)
  }

  /// Input text for the chat field
  @State private var inputText: String = ""

  /// Whether to show the paywall when limit is reached
  @State private var showPaywall = false

  /// Tier before showing paywall (to detect upgrade)
  @State private var tierBeforePaywall: SubscriptionTier = .free

  /// Pending message to send after upgrade
  @State private var pendingMessage: String?

  var body: some View {
    // Show showcase directly (no animation) or the chat interface
    if showShowcase {
      WageyShowcaseView(
        onTryWagey: {
          viewModel.markShowcaseSeen()
          showShowcase = false
        },
        onClose: {
          // Close the entire Wagey flow
          dismiss()
        }
      )
      .environmentObject(coordinator)
    } else {
      chatInterface
    }
  }

  // MARK: - Chat Interface

  private var chatInterface: some View {
    NavigationStack {
      mainContent
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .principal) {
            headerTitle
          }

          // Left side: close button
          ToolbarItem(placement: .topBarLeading) {
            closeButton
          }

          // Right side: new chat, then history
          ToolbarItem(placement: .topBarTrailing) {
            newChatButton
          }
          ToolbarItem(placement: .topBarTrailing) {
            historyButton
          }
        }
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
      let currentTier = EntitlementService.shared.effectiveTier
      if isLimitReached && !showPaywall && currentTier == .free {
        tierBeforePaywall = currentTier
        showPaywall = true
      }
    }
    .task {
      await viewModel.fetchWageyUsage()
    }
  }

  /// Handle paywall dismiss - check if user upgraded
  private func handlePaywallDismiss() {
    let currentTier = EntitlementService.shared.effectiveTier

    // If tier changed from free to paid, user successfully upgraded
    if tierBeforePaywall == .free && currentTier != .free {
      // Retry sending the pending message if there was one
      if let message = pendingMessage {
        pendingMessage = nil
        Task {
          await viewModel.sendMessage(message)
        }
      }
    }
  }

  // MARK: - Main Content

  private var mainContent: some View {
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
        onSuggestionTapped: { suggestion in
          inputText = suggestion
        }
      )

      // Soft warning when conversation is getting long
      if viewModel.isConversationLong {
        conversationLengthWarning
      }

      // Input field with image support
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
    .background(Color.tidexBackground)
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
    let currentTier = EntitlementService.shared.effectiveTier

    // If limit reached AND user is on free tier, show paywall
    // If user has paid tier, don't show paywall even if server said limit reached
    // (this can happen due to server cache lag after subscribing)
    if viewModel.limitReached && currentTier == .free {
      pendingMessage = content
      tierBeforePaywall = currentTier
      showPaywall = true
      return
    }

    // If user upgraded but limitReached flag is stale, reset it
    if viewModel.limitReached && currentTier != .free {
      viewModel.resetLimitReached()
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
    VStack(spacing: Spacing.micro) {
      Text(localizedConversationTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)

      if shouldShowUsageSubtitle {
        Text(String(localized: .wageyMessagesRemaining(Int32(viewModel.remainingMessagesCount))))
          .font(.tidexMicro)
          .foregroundColor(
            viewModel.remainingMessagesCount <= 3 ? .tidexWarning : .tidexTextSecondary
          )
      }
    }
  }

  private var closeButton: some View {
    Button {
      dismiss()
    } label: {
      Image(systemName: "xmark")
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextMuted)
    }
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
}

// MARK: - Previews

#Preview("Empty") {
  WageyView()
    .environmentObject(AppCoordinator.shared)
}

#Preview("With Messages") {
  // Note: For preview purposes, the view will show empty state
  // as we can't inject state into @State property from preview
  WageyView()
    .environmentObject(AppCoordinator.shared)
}
