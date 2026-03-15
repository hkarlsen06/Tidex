import SwiftUI

/// View for displaying and managing Wagey conversations
/// Used inside a sheet with NavigationStack
struct ConversationSidebarView: View {

  let conversations: [LocalConversation]
  let currentConversationId: String?
  let onSelectConversation: (String) -> Void
  let onNewConversation: () -> Void
  let onDeleteConversation: (String) -> Void

  @State private var pendingDeleteConversation: ConversationSidebarItem?

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
    .confirmationDialog(
      String(localized: .wageyConversationsDeleteConfirm),
      isPresented: isShowingDeleteConfirmation,
      titleVisibility: .visible,
      presenting: pendingDeleteConversation
    ) { conversation in
      Button(String(localized: .commonDelete), role: .destructive) {
        onDeleteConversation(conversation.id)
        pendingDeleteConversation = nil
      }
      .accessibilityIdentifier(ConversationSidebarAccessibilityID.confirmDelete(conversation.id))

      Button(String(localized: .commonCancel), role: .cancel) {
        pendingDeleteConversation = nil
      }
      .accessibilityIdentifier(ConversationSidebarAccessibilityID.cancelDelete(conversation.id))
    }
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
      ForEach(conversationItems) { conversation in
        ConversationRowView(
          conversation: conversation,
          isSelected: conversation.id == currentConversationId,
          onSelect: {
            onSelectConversation(conversation.id)
          },
          onRequestDelete: {
            pendingDeleteConversation = conversation
          }
        )
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      }
    }
    .listStyle(.plain)
  }

  private var conversationItems: [ConversationSidebarItem] {
    conversations.map(ConversationSidebarItem.init)
  }

  private var isShowingDeleteConfirmation: Binding<Bool> {
    Binding(
      get: { pendingDeleteConversation != nil },
      set: { isPresented in
        if !isPresented {
          pendingDeleteConversation = nil
        }
      }
    )
  }
}

struct ConversationSidebarItem: Identifiable, Equatable {
  let id: String
  let title: String
  let updatedAt: Date

  init(conversation: LocalConversation) {
    id = conversation.id
    title = conversation.title
    updatedAt = conversation.updatedAt
  }
}

enum ConversationSidebarAccessibilityID {
  static func row(_ conversationId: String) -> String {
    "wagey-history.row.\(conversationId)"
  }

  static func swipeDelete(_ conversationId: String) -> String {
    "wagey-history.delete-swipe.\(conversationId)"
  }

  static func confirmDelete(_ conversationId: String) -> String {
    "wagey-history.delete-confirm.\(conversationId)"
  }

  static func cancelDelete(_ conversationId: String) -> String {
    "wagey-history.delete-cancel.\(conversationId)"
  }
}

// MARK: - Conversation Row

struct ConversationRowView: View {

  let conversation: ConversationSidebarItem
  let isSelected: Bool
  let onSelect: () -> Void
  let onRequestDelete: () -> Void

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
      HStack(spacing: Spacing.sm) {
        VStack(alignment: .leading, spacing: 3) {
          Text(localizedTitle)
            .font(isSelected ? .tidexButton : .tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)

          Text(formattedDate)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
        }

        Spacer()

        if isSelected {
          Image(systemName: "checkmark")
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexBlue)
        }
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(ConversationSidebarAccessibilityID.row(conversation.id))
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button {
        onRequestDelete()
      } label: {
        Label(String(localized: .commonDelete), systemImage: "trash")
      }
      .tint(.tidexError)
      .accessibilityIdentifier(ConversationSidebarAccessibilityID.swipeDelete(conversation.id))
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
