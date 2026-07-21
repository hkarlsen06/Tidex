import SwiftUI

/// View for displaying and managing Wagey conversations
/// Used inside a sheet with NavigationStack
struct ConversationSidebarView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order

  let conversations: [LocalConversation]  // swiftlint:disable:this explicit_acl
  let currentConversationId: String?  // swiftlint:disable:this explicit_acl
  let onSelectConversation: (String) -> Void  // swiftlint:disable:this explicit_acl
  let onNewConversation: () -> Void  // swiftlint:disable:this explicit_acl
  let onDeleteConversation: (String) -> Void  // swiftlint:disable:this explicit_acl

  @State private var pendingDeleteConversation: ConversationSidebarItem?

  var body: some View {  // swiftlint:disable:this explicit_acl
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

struct ConversationSidebarItem: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let title: String  // swiftlint:disable:this explicit_acl
  let updatedAt: Date  // swiftlint:disable:this explicit_acl

  init(conversation: LocalConversation) {  // swiftlint:disable:this explicit_acl
    id = conversation.id
    title = conversation.title
    updatedAt = conversation.updatedAt
  }
}

enum ConversationSidebarAccessibilityID {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  static func row(_ conversationId: String) -> String {  // swiftlint:disable:this explicit_acl
    "wagey-history.row.\(conversationId)"
  }

  static func swipeDelete(_ conversationId: String) -> String {  // swiftlint:disable:this explicit_acl
    "wagey-history.delete-swipe.\(conversationId)"
  }

  static func confirmDelete(_ conversationId: String) -> String {  // swiftlint:disable:this explicit_acl
    "wagey-history.delete-confirm.\(conversationId)"
  }

  static func cancelDelete(_ conversationId: String) -> String {  // swiftlint:disable:this explicit_acl
    "wagey-history.delete-cancel.\(conversationId)"
  }
}

// MARK: - Conversation Row

struct ConversationRowView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl

  let conversation: ConversationSidebarItem  // swiftlint:disable:this explicit_acl
  let isSelected: Bool  // swiftlint:disable:this explicit_acl
  let onSelect: () -> Void  // swiftlint:disable:this explicit_acl
  let onRequestDelete: () -> Void  // swiftlint:disable:this explicit_acl

  /// Localized title - translates "New Conversation" to current locale
  private var localizedTitle: String {
    if conversation.title == "New Conversation" {
      return String(localized: .wageyNewConversation)
    }
    return conversation.title
  }

  var body: some View {  // swiftlint:disable:this explicit_acl
    Button {
      Haptics.play(.light)
      onSelect()
    } label: {
      HStack(spacing: Spacing.sm) {
        VStack(alignment: .leading, spacing: 3) {  // swiftlint:disable:this no_magic_numbers
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
          Image(systemName: "checkmark")  // swiftlint:disable:this accessibility_label_for_image
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
    let formatter = RelativeDateTimeFormatter()  // swiftlint:disable:this explicit_type_interface
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: conversation.updatedAt, relativeTo: Date())
  }
}

// MARK: - Previews

#Preview("With Conversations") {  // swiftlint:disable:this closure_body_length
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
          createdAt: Date().addingTimeInterval(-86_400),
          updatedAt: Date().addingTimeInterval(-86_400)
        ),
        LocalConversation(
          userId: "test",
          title: "How much will I earn this month?",
          messages: [],
          createdAt: Date().addingTimeInterval(-172_800),
          updatedAt: Date().addingTimeInterval(-172_800)
        ),
      ],
      currentConversationId: nil,
      onSelectConversation: { _ in },  // swiftlint:disable:this no_empty_block
      onNewConversation: {},  // swiftlint:disable:this no_empty_block
      onDeleteConversation: { _ in }  // swiftlint:disable:this no_empty_block
    )
  }
}

#Preview("Empty") {
  NavigationStack {
    ConversationSidebarView(
      conversations: [],
      currentConversationId: nil,
      onSelectConversation: { _ in },  // swiftlint:disable:this no_empty_block
      onNewConversation: {},  // swiftlint:disable:this no_empty_block
      onDeleteConversation: { _ in }  // swiftlint:disable:this no_empty_block
    )
  }
}
