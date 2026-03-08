import SwiftUI

// MARK: - Manage Sharing Sheet

/// Modal sheet for managing sharing relationships
/// Allows viewing/editing friends, adding new recipients, and controlling settings
struct ManageSharingSheet: View {
  @Environment(\.dismiss) private var dismiss

  @StateObject private var viewModel = ManageSharingViewModel()

  /// User ID to highlight and scroll to (from deep link)
  var highlightUserId: String?

  /// Whether to auto-expand the add friend form and focus the input
  var autoExpandAddForm: Bool = false

  /// Callback when visibility changes (hide/show) to refresh the sharer list
  var onVisibilityChange: (() -> Void)?

  /// Confirmation dialog state
  @State private var friendToRemove: Friend?
  @State private var removeAction: RemoveAction?

  /// Whether the highlighted user is currently pulsing
  @State private var isHighlightActive = false

  enum RemoveAction {
    case removeShare  // Revoke their access to my shifts
    case removeSharer  // Remove them from my friends list
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { scrollProxy in
        List {
          // MARK: - Description
          Section {
          } footer: {
            Text(.sharingManageDescription)
              .font(.tidexSubheadline)
          }

          // MARK: - Error Banner
          if let error = viewModel.errorMessage {
            Section {
              ErrorBanner(
                message: error,
                onRetry: {
                  Task {
                    await viewModel.refresh()
                  }
                },
                onDismiss: { viewModel.errorMessage = nil }
              )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
          }

          // MARK: - Content
          if viewModel.isLoading {
            Section {
              loadingView
            }
            .listRowBackground(Color.clear)
          } else if viewModel.friends.isEmpty {
            Section {
              emptyState
            }
            .listRowBackground(Color.clear)
          } else {
            friendSections
          }

          // MARK: - Add Friend
          Section {
            AddFriendForm(
              isExpanded: $viewModel.isAddFormExpanded,
              identifier: $viewModel.addIdentifier,
              showEarnings: $viewModel.addShowEarnings,
              error: $viewModel.addError,
              isLoading: viewModel.isAdding,
              canAdd: viewModel.canAddMore,
              capacityDisplay: viewModel.capacityDisplay,
              onAdd: {
                Task {
                  await viewModel.addFriend()
                }
              },
              onCancel: {
                viewModel.cancelAddFriend()
              }
            )
          }
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.tidexSurfacePrimary)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.tidexBackground)
        .onChange(of: viewModel.friends) { _, friends in
          scrollToHighlightedUserIfNeeded(scrollProxy: scrollProxy, friends: friends)
        }
      }
      .navigationTitle(String(localized: .sharingSeeFriends))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: .commonDone)) {
            dismiss()
          }
          .font(.tidexHeadline)
          .foregroundColor(.tidexBlue)
        }
      }
    }
    .task {
      await viewModel.loadFriends()
      if autoExpandAddForm {
        try? await Task.sleep(for: .milliseconds(300))
        viewModel.isAddFormExpanded = true
      }
    }
    .confirmationDialog(
      confirmationTitle,
      isPresented: .init(
        get: { friendToRemove != nil },
        set: {
          if !$0 {
            friendToRemove = nil
            removeAction = nil
          }
        }
      ),
      titleVisibility: .visible
    ) {
      Button(String(localized: .sharingRemove), role: .destructive) {
        if let friend = friendToRemove, let action = removeAction {
          Task {
            switch action {
            case .removeShare:
              await viewModel.removeShare(for: friend)
            case .removeSharer:
              await viewModel.removeSharer(for: friend)
              onVisibilityChange?()
            }
          }
        }
        friendToRemove = nil
        removeAction = nil
      }
      Button(String(localized: .commonCancel), role: .cancel) {
        friendToRemove = nil
        removeAction = nil
      }
    }
    .onChange(of: viewModel.friends) { _, _ in
      onVisibilityChange?()
    }
  }

  // MARK: - Confirmation Dialog Title

  private var confirmationTitle: String {
    guard let friend = friendToRemove, let action = removeAction else {
      return ""
    }

    switch action {
    case .removeShare:
      return String(localized: .sharingStopSharingWith(friend.displayName))
    case .removeSharer:
      return String(localized: .sharingRemoveFromList(friend.displayName))
    }
  }

  // MARK: - Loading View

  private var loadingView: some View {
    VStack(spacing: Spacing.md) {
      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
        .scaleEffect(1.2)

      Text(.sharingLoadingFriends)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "person.2")
        .font(.system(size: 40))
        .foregroundColor(.tidexTextMuted)

      Text(.sharingNoFriends)
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)

      Text(.sharingNoFriendsDescription)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Spacing.xxl)
  }

  // MARK: - Friend Sections

  @ViewBuilder
  private var friendSections: some View {
    if !viewModel.mutualFriends.isEmpty {
      Section(header: Text(String(localized: .sharingMutual))) {
        ForEach(viewModel.mutualFriends) { friend in
          makeFriendRow(friend, sectionType: .mutual)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }

    if !viewModel.outgoingOnlyFriends.isEmpty {
      Section(header: Text(String(localized: .sharingIShareWith))) {
        ForEach(viewModel.outgoingOnlyFriends) { friend in
          makeFriendRow(friend, sectionType: .outgoing)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }

    if !viewModel.incomingOnlyFriends.isEmpty {
      Section(header: Text(String(localized: .sharingSharesWithMe))) {
        ForEach(viewModel.incomingOnlyFriends) { friend in
          makeFriendRow(friend, sectionType: .incoming)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
  }

  private func makeFriendRow(_ friend: Friend, sectionType: FriendSectionType) -> some View {
    let isHighlighted = highlightUserId == friend.id && isHighlightActive

    return FriendRow(
      friend: friend,
      sectionType: sectionType,
      isActionInProgress: viewModel.actionInProgress == friend.id,
      isHighlighted: isHighlighted,
      onToggleEarnings: {
        Task {
          await viewModel.toggleEarnings(for: friend)
        }
      },
      onShareBack: {
        Task {
          await viewModel.shareBack(with: friend)
        }
      },
      onToggleMuted: {
        Task {
          await viewModel.toggleMuted(for: friend)
        }
      },
      onToggleOwnerMuted: {
        Task {
          await viewModel.toggleOwnerMuted(for: friend)
        }
      },
      onToggleHidden: {
        Task {
          await viewModel.toggleHidden(for: friend)
          onVisibilityChange?()
        }
      },
      onRemove: {
        friendToRemove = friend
        removeAction = sectionType == .incoming ? .removeSharer : .removeShare
      }
    )
    .id(friend.id)
    .alignmentGuide(.listRowSeparatorLeading) { d in
      d[.leading] + 52
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        friendToRemove = friend
        removeAction = sectionType == .incoming ? .removeSharer : .removeShare
      } label: {
        Label(String(localized: .sharingSwipeRemove), systemImage: "trash")
      }
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      if sectionType == .mutual || sectionType == .incoming {
        Button {
          Task {
            await viewModel.toggleHidden(for: friend)
            onVisibilityChange?()
          }
        } label: {
          Label(
            String(
              localized: friend.sharesWithMe?.hidden == true
                ? .sharingSwipeShow : .sharingSwipeHide),
            systemImage: friend.sharesWithMe?.hidden == true ? "eye" : "eye.slash"
          )
        }
        .tint(friend.sharesWithMe?.hidden == true ? .green : .orange)
      }
    }
  }

  // MARK: - Highlight Handling

  /// Scroll to the highlighted user if present
  private func scrollToHighlightedUserIfNeeded(scrollProxy: ScrollViewProxy, friends: [Friend]) {
    guard let highlightUserId = highlightUserId,
      friends.contains(where: { $0.id == highlightUserId })
    else {
      return
    }

    DispatchQueue.main.async {
      withAnimation(.easeOut(duration: 0.25)) {
        scrollProxy.scrollTo(highlightUserId, anchor: .center)
        isHighlightActive = true
      }

      Task { @MainActor in
        try? await Task.sleep(for: .seconds(3))
        withAnimation(.easeOut(duration: 0.3)) {
          isHighlightActive = false
        }
      }
    }
  }
}

// MARK: - Preview

#Preview {
  ManageSharingSheet()
}
