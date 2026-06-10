import SwiftUI

// MARK: - Manage Sharing Sheet

/// Modal sheet for managing sharing relationships
/// Allows viewing/editing friends, adding new recipients, and controlling settings
struct ManageSharingSheet: View {
  @Environment(\.dismiss) private var dismiss

  @StateObject private var viewModel: ManageSharingViewModel

  /// User ID to highlight and scroll to (from deep link)
  var highlightUserId: String?

  /// Whether to auto-expand the add friend form and focus the input
  var autoExpandAddForm: Bool = false

  /// Callback when visibility changes (hide/show) to refresh the sharer list
  var onVisibilityChange: (() -> Void)?
  var onBootstrapRefresh: ((FriendsTabBootstrapData) async -> Void)?

  var typingUserIds: Set<String> = []
  var unreadChatUserIds: Set<String> = []
  var chatPreviewsByUserId: [String: FriendCardMessagePreview] = [:]
  var shiftPreviews: [String: SharerShiftPreview] = [:]
  var isLoadingPreviews: Bool = false

  /// Confirmation dialog state
  @State private var friendToRemove: Friend?
  @State private var removeAction: FriendSharingRemovalAction?
  @State private var friendToBlock: Friend?

  /// Whether the highlighted user is currently pulsing
  @State private var isHighlightActive = false
  @State private var isBlockedUsersExpanded = false

  init(
    highlightUserId: String? = nil,
    autoExpandAddForm: Bool = false,
    initialSnapshot: FriendsManagementSnapshot? = nil,
    onVisibilityChange: (() -> Void)? = nil,
    onBootstrapRefresh: ((FriendsTabBootstrapData) async -> Void)? = nil,
    typingUserIds: Set<String> = [],
    unreadChatUserIds: Set<String> = [],
    chatPreviewsByUserId: [String: FriendCardMessagePreview] = [:],
    shiftPreviews: [String: SharerShiftPreview] = [:],
    isLoadingPreviews: Bool = false
  ) {
    _viewModel = StateObject(
      wrappedValue: ManageSharingViewModel(initialSnapshot: initialSnapshot)
    )
    self.highlightUserId = highlightUserId
    self.autoExpandAddForm = autoExpandAddForm
    self.onVisibilityChange = onVisibilityChange
    self.onBootstrapRefresh = onBootstrapRefresh
    self.typingUserIds = typingUserIds
    self.unreadChatUserIds = unreadChatUserIds
    self.chatPreviewsByUserId = chatPreviewsByUserId
    self.shiftPreviews = shiftPreviews
    self.isLoadingPreviews = isLoadingPreviews
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

          if let offlineMessage = viewModel.offlineActionsUnavailableMessage {
            Section {
              offlineNotice(message: offlineMessage)
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
          } else if viewModel.friends.isEmpty, viewModel.blockedFriends.isEmpty {
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
              isOfflineUnavailable: viewModel.areServerActionsUnavailable,
              capacityDisplay: viewModel.capacityDisplay,
              shouldShowCapacity: viewModel.shouldShowCapacity,
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

          if !viewModel.blockedFriends.isEmpty {
            blockedUsersSection
          }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.tidexBackground)
        .onChange(of: viewModel.friends) { _, _ in
          scrollToHighlightedUserIfNeeded(
            scrollProxy: scrollProxy,
            friends: viewModel.friends + viewModel.blockedFriends
          )
        }
        .onChange(of: viewModel.blockedFriends) { _, _ in
          scrollToHighlightedUserIfNeeded(
            scrollProxy: scrollProxy,
            friends: viewModel.friends + viewModel.blockedFriends
          )
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
      viewModel.onBootstrapRefresh = onBootstrapRefresh
      await viewModel.loadFriendsIfNeeded()
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
      Button(removeButtonTitle, role: .destructive) {
        if let friend = friendToRemove, let action = removeAction {
          Task {
            switch action {
            case .stopSharingMyShifts:
              await viewModel.removeShare(for: friend)

            case .stopSeeingTheirShifts:
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
    } message: {
      Text(confirmationMessage)
    }
    .confirmationDialog(
      blockConfirmationTitle,
      isPresented: .init(
        get: { friendToBlock != nil },
        set: {
          if !$0 {
            friendToBlock = nil
          }
        }
      ),
      titleVisibility: .visible
    ) {
      Button(String(localized: .friendsChatBlockUser), role: .destructive) {
        if let friend = friendToBlock {
          Task {
            await viewModel.blockFriend(friend)
            onVisibilityChange?()
          }
        }
        friendToBlock = nil
      }
      Button(String(localized: .commonCancel), role: .cancel) {
        friendToBlock = nil
      }
    } message: {
      Text(.friendsChatBlockConfirmMessage)
    }
    .onChange(of: viewModel.blockedFriends) { _, blockedFriends in
      if blockedFriends.isEmpty {
        isBlockedUsersExpanded = false
      }
    }
  }

  // MARK: - Confirmation Dialog Title

  private var confirmationTitle: String {
    guard let friend = friendToRemove, let action = removeAction else {
      return ""
    }

    return action.confirmationTitle(friendName: friend.displayName)
  }

  private var confirmationMessage: String {
    guard let friend = friendToRemove, let action = removeAction else {
      return ""
    }

    return action.confirmationMessage(
      friendName: friend.displayName,
      sectionType: sectionType(for: friend)
    )
  }

  private var removeButtonTitle: String {
    removeAction?.title ?? ""
  }

  private var blockConfirmationTitle: String {
    guard let friend = friendToBlock else { return "" }
    return String(localized: .friendsChatBlockConfirmTitle)
      .replacingOccurrences(of: "{name}", with: friend.displayName)
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

  private func offlineNotice(message: String) -> some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      Image(systemName: "wifi.slash")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexWarning)

      Text(message)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
  }

  // MARK: - Friend Sections

  @ViewBuilder
  private var friendSections: some View {
    Section {
      ForEach(orderedFriends) { friend in
        makeFriendRow(friend, sectionType: sectionType(for: friend))
          .listRowBackground(Color.tidexSurfacePrimary)
      }
    }
  }

  private var orderedFriends: [Friend] {
    let friendsById = Dictionary(uniqueKeysWithValues: viewModel.friends.map { ($0.id, $0) })
    let sharedUsers = viewModel.friends.map {
      $0.asSharedUser(hidden: viewModel.isHiddenInFriendsTab(for: $0))
    }
    let orderedIds = ordering.sortedSharers(sharedUsers).map(\.id)
    let orderedFriends = orderedIds.compactMap { friendsById[$0] }
    let orderedIdSet = Set(orderedIds)
    let missingFriends = viewModel.friends
      .filter { !orderedIdSet.contains($0.id) }
      .sorted { lhs, rhs in
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }

    return orderedFriends + missingFriends
  }

  private var ordering: FriendsListOrdering {
    FriendsListOrdering(
      typingUserIds: typingUserIds,
      unreadChatUserIds: unreadChatUserIds,
      bottomedUserIds: [],
      chatPreviewsByUserId: chatPreviewsByUserId,
      shiftPreviews: shiftPreviews,
      isLoadingShiftPreviews: isLoadingPreviews
    )
  }

  @ViewBuilder
  private var blockedUsersSection: some View {
    Section {
      Button {
        withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
          isBlockedUsersExpanded.toggle()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "hand.raised.fill")
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexError)

          Text(.sharingBlockedUsersTitle)
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexTextPrimary)

          Text("\(viewModel.blockedFriends.count)")
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexTextMuted)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxxs)
            .background(
              Capsule(style: .continuous)
                .fill(Color.tidexSurfaceSecondary)
            )

          Spacer()

          Image(systemName: isBlockedUsersExpanded ? "chevron.up" : "chevron.down")
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexTextMuted)
        }
      }
      .buttonStyle(.plain)

      if isBlockedUsersExpanded {
        ForEach(viewModel.blockedFriends) { friend in
          blockedFriendRow(friend)
        }
      }
    } footer: {
      if isBlockedUsersExpanded {
        Text(.sharingBlockedUsersDescription)
      }
    }
    .listRowBackground(Color.tidexSurfacePrimary)
  }

  private func makeFriendRow(_ friend: Friend, sectionType: FriendSectionType) -> some View {
    let isHighlighted = highlightUserId == friend.id && isHighlightActive
    let isHiddenInFriendsTab = viewModel.isHiddenInFriendsTab(for: friend)
    let areServerActionsUnavailable = viewModel.areServerActionsUnavailable
    let isHideActionDisabled = areServerActionsUnavailable && friend.sharesWithMe != nil

    return FriendRow(
      friend: friend,
      sectionType: sectionType,
      isActionInProgress: viewModel.actionInProgress == friend.id,
      isHiddenInFriendsTab: isHiddenInFriendsTab,
      areServerActionsUnavailable: areServerActionsUnavailable,
      isHideActionDisabled: isHideActionDisabled,
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
      onBlock: {
        friendToBlock = friend
      },
      onRemove: { action in
        friendToRemove = friend
        removeAction = action
      }
    )
    .id(friend.id)
    .alignmentGuide(.listRowSeparatorLeading) { d in
      d[.leading] + 52
    }
  }

  private func blockedFriendRow(_ friend: Friend) -> some View {
    HStack(spacing: Spacing.sm) {
      AvatarView(
        url: friend.avatarUrl,
        initials: friend.initials,
        size: AvatarView.Size.medium
      )
      .overlay(alignment: .bottomTrailing) {
        Image(systemName: "hand.raised.fill")
          .font(.system(size: 10))
          .foregroundColor(.white)
          .padding(3)
          .background(Color.tidexError.opacity(0.85))
          .clipShape(Circle())
          .offset(x: 2, y: 2)
      }

      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(friend.displayName)
          .font(.tidexBodyMedium)
          .foregroundColor(.tidexTextPrimary)
          .lineLimit(1)

        if let contactInfo = friend.contactInfo {
          Text(contactInfo)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextMuted)
            .lineLimit(1)
        }
      }

      Spacer(minLength: Spacing.sm)

      Button(String(localized: .sharingUnblock)) {
        Task {
          await viewModel.unblockFriend(friend)
          onVisibilityChange?()
        }
      }
      .font(.tidexFootnoteMedium)
      .foregroundColor(.tidexBlue)
      .buttonStyle(.plain)
      .disabled(viewModel.actionInProgress == friend.id || viewModel.areServerActionsUnavailable)
      .opacity(
        viewModel.actionInProgress == friend.id || viewModel.areServerActionsUnavailable ? 0.6 : 1)
    }
    .padding(.vertical, Spacing.xxs)
  }

  private func sectionType(for friend: Friend) -> FriendSectionType {
    if friend.isMutual { return .mutual }
    if friend.isOutgoingOnly { return .outgoing }
    return .incoming
  }

  // MARK: - Highlight Handling

  /// Scroll to the highlighted user if present
  private func scrollToHighlightedUserIfNeeded(scrollProxy: ScrollViewProxy, friends: [Friend]) {
    guard let highlightUserId,
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

extension Friend {
  fileprivate func asSharedUser(hidden: Bool) -> SharedUser {
    let incomingShare = sharesWithMe
    let outgoingShare = iShareWith

    return SharedUser(
      id: id,
      email: email,
      phone: phone,
      firstName: firstName,
      profilePictureUrl: profilePictureUrl,
      oauthAvatarUrl: oauthAvatarUrl,
      sharedAt: incomingShare?.sharedAt ?? outgoingShare?.sharedAt ?? "",
      showEarnings: incomingShare?.showEarningsToMe ?? false,
      hidden: hidden,
      username: username
    )
  }
}

// MARK: - Preview

#Preview {
  ManageSharingSheet()
}
