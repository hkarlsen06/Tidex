import SwiftUI

/// View for displaying and managing Wagey conversations
/// Used inside a sheet with NavigationStack
struct ConversationSidebarView: View {

  let conversations: [LocalConversation]
  let currentConversationId: String?
  let onSelectConversation: (String) -> Void
  let onNewConversation: () -> Void
  let onDeleteConversation: (String) -> Void

  var body: some View {
    Group {
      if conversations.isEmpty {
        emptyState
      } else {
        conversationList
      }
    }
    .navigationTitle(Text(.wageyConversationsTitle))
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    ContentUnavailableView {
      Label {
        Text(.wageyConversationsEmpty)
      } icon: {
        Image(systemName: "bubble.left.and.bubble.right")
          .foregroundColor(.tidexTextMuted)
      }
    } actions: {
      Button {
        Haptics.play(.light)
        onNewConversation()
      } label: {
        Text(.wageyNewConversation)
      }
      .buttonStyle(.borderedProminent)
    }
  }

  // MARK: - Conversation List

  private var conversationList: some View {
    List {
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
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      }
    }
    .listStyle(.plain)
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
        VStack(alignment: .leading, spacing: 3) {
          Text(localizedTitle)
            .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)

          Text(formattedDate)
            .font(.system(size: 13))
            .foregroundColor(.tidexTextMuted)
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.tidexBlue)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
  NavigationStack {
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
        ),
      ],
      currentConversationId: nil,
      onSelectConversation: { _ in },
      onNewConversation: {},
      onDeleteConversation: { _ in }
    )
  }
}

#Preview("Empty") {
  NavigationStack {
    ConversationSidebarView(
      conversations: [],
      currentConversationId: nil,
      onSelectConversation: { _ in },
      onNewConversation: {},
      onDeleteConversation: { _ in }
    )
  }
}
