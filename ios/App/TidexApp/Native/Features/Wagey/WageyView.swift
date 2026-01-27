import SwiftUI

/// Main Wagey chat view
/// Composes the header, message list, and input field
struct WageyView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.localization) private var localization
    @Environment(\.dismiss) private var dismiss

    /// ViewModel for managing chat state
    @State private var viewModel = WageyViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Message list
                ChatMessageList(
                    messages: viewModel.messages,
                    streamingText: viewModel.currentStreamingText,
                    streamingToolCalls: viewModel.activeToolCalls,
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerTitle
                }

                ToolbarItem(placement: .topBarLeading) {
                    closeButton
                }

                ToolbarItem(placement: .topBarTrailing) {
                    newChatButton
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

    // MARK: - Header Components

    private var headerTitle: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(localization.string("wagey.title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

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

    private var newChatButton: some View {
        Button {
            Haptics.play(.light)
            viewModel.clearConversation()
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
