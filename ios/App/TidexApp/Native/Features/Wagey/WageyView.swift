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
    private var viewModel: WageyViewModel { WageyViewModel.shared }

    /// Sidebar visibility state
    @State private var showSidebar = false

    var body: some View {
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
        .alert(
            localization.string("wagey.limitReached.title"),
            isPresented: .init(
                get: { viewModel.limitReached && viewModel.error == nil },
                set: { _ in }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(localization.string("wagey.limitReached.message", viewModel.resetDays))
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Message list
            ChatMessageList(
                messages: viewModel.messages,
                streamingContentBlocks: viewModel.activeContentBlocks,
                isStreaming: viewModel.isStreaming,
                onSuggestionTapped: { suggestion in
                    Task {
                        await viewModel.sendMessage(suggestion)
                    }
                }
            )

            // Input field
            ChatInputField(
                onSend: { content in
                    Task {
                        await viewModel.sendMessage(content)
                    }
                },
                disabled: viewModel.isStreaming || viewModel.limitReached
            )
        }
        .background(Color.tidexBackground)
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

    private var headerTitle: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(viewModel.currentConversationTitle)
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
