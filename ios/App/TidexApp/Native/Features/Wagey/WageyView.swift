import SwiftUI

/// Main Wagey chat view
/// Composes the header, message list, input field, and conversation sidebar
struct WageyView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Shared ViewModel for managing chat state
    /// Using shared instance ensures conversation persists when dismissing and reopening Wagey
    private let viewModel = WageyViewModel.shared

    /// Sidebar visibility state
    @State private var showSidebar = false

    /// Whether to show the showcase for first-time free users
    /// Initialize based on ViewModel state so it shows immediately
    @State private var showShowcase: Bool

    init() {
        // Check if showcase should be shown at initialization time
        _showShowcase = State(initialValue: WageyViewModel.shared.shouldShowShowcase)
    }

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
            .environment(\.localization, localization)
        } else {
            chatInterface
        }
    }

    // MARK: - Chat Interface

    private var chatInterface: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                // Main chat content
                mainContent
                    .disabled(showSidebar && horizontalSizeClass == .compact)

                // Sidebar overlay for compact width (iPhone)
                if showSidebar && horizontalSizeClass == .compact {
                    sidebarOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerTitle
                }

                // Left side: history button, then new chat button
                ToolbarItem(placement: .topBarLeading) {
                    sidebarButton
                }
                ToolbarSpacer(.fixed, placement: .topBarLeading)
                ToolbarItem(placement: .topBarLeading) {
                    newChatButton
                }

                // Right side: close button
                ToolbarItem(placement: .topBarTrailing) {
                    closeButton
                }
            }
        }
        .sheet(isPresented: $showPaywall, onDismiss: handlePaywallDismiss) {
            PaywallView(contextType: .wageyLimit)
                .interactiveDismissDisabled()
        }
        .alert(
            localization.string("wagey.error.unknown"),
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
            // Show paywall when limit is reached (e.g., server responds with limit error)
            // But only if user is on free tier - don't show if already subscribed
            let currentTier = EntitlementService.shared.effectiveTier
            if isLimitReached && !showPaywall && currentTier == .free {
                tierBeforePaywall = currentTier
                showPaywall = true
            }
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
            // Usage bar (always show for free tier users)
            if viewModel.currentTier == .free {
                usageBar
            }

            // Message list
            ChatMessageList(
                messages: viewModel.messages,
                streamingContentBlocks: viewModel.activeContentBlocks,
                isStreaming: viewModel.isStreaming,
                onSuggestionTapped: { suggestion in
                    handleSendMessage(suggestion)
                }
            )

            // Input field
            ChatInputField(
                onSend: { content in
                    handleSendMessage(content)
                },
                disabled: viewModel.isStreaming
            )
        }
        .background(Color.tidexBackground)
    }

    // MARK: - Usage Bar

    private var usageBar: some View {
        VStack(spacing: 0) {
            WageyUsageBar(
                used: viewModel.messagesUsed,
                limit: viewModel.messageLimit
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
                .foregroundColor(.tidexBorder)
        }
        .background(Color.tidexSurfacePrimary)
    }

    // MARK: - Message Handling

    /// Handle sending a message, showing paywall if limit reached
    private func handleSendMessage(_ content: String) {
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

        // Send the message
        Task {
            await viewModel.sendMessage(content)
        }
    }

    // MARK: - Sidebar Overlay (iPhone)

    private var sidebarOverlay: some View {
        ZStack(alignment: .leading) {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSidebar = false
                    }
                }

            // Sidebar
            ConversationSidebarView(
                conversations: viewModel.conversations,
                currentConversationId: viewModel.currentConversationId,
                onSelectConversation: { id in
                    viewModel.loadConversation(id: id)
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSidebar = false
                    }
                },
                onNewConversation: {
                    viewModel.startNewConversation()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSidebar = false
                    }
                },
                onDeleteConversation: { id in
                    viewModel.deleteConversation(id: id)
                }
            )
            .frame(width: 280)
            .background(Color.tidexSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 2, y: 0)
            .transition(.move(edge: .leading))
        }
    }

    // MARK: - Header Components

    /// Localized conversation title - translates "New Conversation" to current locale
    private var localizedConversationTitle: String {
        let title = viewModel.currentConversationTitle
        if title == "New Conversation" {
            return localization.string("wagey.newConversation")
        }
        return title
    }

    private var headerTitle: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(localizedConversationTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
                    .lineLimit(1)

                if let remaining = viewModel.remainingMessages {
                    Text(localization.string("wagey.messagesRemaining", remaining))
                        .font(.system(size: 11))
                        .foregroundColor(.tidexTextSecondary)
                }
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.tidexTextMuted)
        }
    }

    private var sidebarButton: some View {
        Button {
            Haptics.play(.light)
            withAnimation(.easeInOut(duration: 0.25)) {
                showSidebar.toggle()
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.tidexBlue)
        }
    }

    private var newChatButton: some View {
        Button {
            Haptics.play(.light)
            viewModel.startNewConversation()
        } label: {
            Image(systemName: "plus.bubble")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.tidexBlue)
        }
        .disabled(viewModel.messages.isEmpty && !viewModel.isStreaming)
        .opacity(viewModel.messages.isEmpty && !viewModel.isStreaming ? 0.5 : 1)
    }
}

// MARK: - Previews

#Preview("Empty") {
    WageyView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}

#Preview("With Messages") {
    // Note: For preview purposes, the view will show empty state
    // as we can't inject state into @State property from preview
    WageyView()
        .environmentObject(AppCoordinator.shared)
        .environment(\.localization, LocalizationManager.shared)
}
