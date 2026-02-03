import SwiftUI

/// Sidebar view for displaying and managing Wagey conversations
struct ConversationSidebarView: View {
    
    let conversations: [LocalConversation]
    let currentConversationId: String?
    let onSelectConversation: (String) -> Void
    let onNewConversation: () -> Void
    let onDeleteConversation: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader

            Divider()
                .background(Color.tidexBorder)

            // Conversation list
            if conversations.isEmpty {
                emptyState
            } else {
                conversationList
            }
        }
        .background(Color.tidexSurfacePrimary)
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack {
            Text(.wageyConversationsTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            Spacer()

            Button {
                Haptics.play(.light)
                onNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.tidexBlue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundColor(.tidexTextMuted)

            Text(.wageyConversationsEmpty)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(conversations, id: \.id) { conversation in
                    ConversationRowView(
                        conversation: conversation,
                        isSelected: conversation.id == currentConversationId,
                        onSelect: {
                            onSelectConversation(conversation.id)
                        },
                        onDelete: {
                            onDeleteConversation(conversation.id)
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Conversation Row

struct ConversationRowView: View {
    
    let conversation: LocalConversation
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    /// Localized title - translates "New Conversation" to current locale
    private var localizedTitle: String {
        if conversation.title == "New Conversation" {
            return String(localized: .wageyNewConversation)
        }
        return conversation.title
    }

    var body: some View {
        Button {
            Haptics.play(.light)
            onSelect()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedTitle)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(.tidexTextPrimary)
                        .lineLimit(1)

                    Text(formattedDate)
                        .font(.system(size: 12))
                        .foregroundColor(.tidexTextMuted)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexBlue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(isSelected ? Color.tidexSurfaceSecondary : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(String(localized: .commonDelete), systemImage: "trash")
            }
        }
        .confirmationDialog(
            String(localized: .wageyConversationsDeleteConfirm),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: .commonDelete), role: .destructive) {
                onDelete()
            }
            Button(String(localized: .commonCancel), role: .cancel) {}
        }
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
    }
}

// MARK: - Previews

#Preview("With Conversations") {
    ConversationSidebarView(
        conversations: [
            LocalConversation(
                userId: "test",
                title: "Add shift tomorrow",
                messages: [],
                createdAt: Date(),
                updatedAt: Date()
            ),
            LocalConversation(
                userId: "test",
                title: "Calculate my earnings",
                messages: [],
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: Date().addingTimeInterval(-86400)
            ),
            LocalConversation(
                userId: "test",
                title: "How much will I earn this month?",
                messages: [],
                createdAt: Date().addingTimeInterval(-172800),
                updatedAt: Date().addingTimeInterval(-172800)
            )
        ],
        currentConversationId: nil,
        onSelectConversation: { _ in },
        onNewConversation: {},
        onDeleteConversation: { _ in }
    )
    .frame(width: 280)
}

#Preview("Empty") {
    ConversationSidebarView(
        conversations: [],
        currentConversationId: nil,
        onSelectConversation: { _ in },
        onNewConversation: {},
        onDeleteConversation: { _ in }
    )
    .frame(width: 280)
}
