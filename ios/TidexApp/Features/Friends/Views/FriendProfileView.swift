import SwiftUI

/// Profile view for a friend, presented as a sheet from the friend detail view.
/// Shows the friend's avatar/name and all management options (same as ManageSharingSheet).
/// The UserMenuButton in the toolbar visually leads into this profile when tapped.
struct FriendProfileView: View {
  let sharedUser: SharedUser
  var onVisibilityChange: (() -> Void)?
  var onFriendRemoved: (() -> Void)?
  var onMessageTapped: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = ManageSharingViewModel()

  @State private var showManageSheet = false
  @State private var friendToRemove: Friend?
  @State private var removeAction: RemoveAction?

  enum RemoveAction {
    case removeShare
    case removeSharer
  }

  private var friend: Friend? {
    viewModel.friends.first { $0.id == sharedUser.id }
  }

  private var sectionType: FriendSectionType? {
    guard let friend else { return nil }
    if friend.isMutual { return .mutual }
    if friend.isOutgoingOnly { return .outgoing }
    if friend.isIncomingOnly { return .incoming }
    return nil
  }

  var body: some View {
    List {
      profileHeaderSection

      if viewModel.isLoading {
        Section {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.xl)
        }
        .listRowBackground(Color.clear)
      } else if let friend, let sectionType {
        notificationSection(friend: friend, sectionType: sectionType)
        sharingSection(friend: friend, sectionType: sectionType)
        actionsSection(friend: friend, sectionType: sectionType)
      }

      manageFriendsLink
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.tidexBackground)
    .task {
      await viewModel.loadFriends()
    }
    .sheet(isPresented: $showManageSheet) {
      ManageSharingSheet(onVisibilityChange: onVisibilityChange)
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
            }
            onFriendRemoved?()
            dismiss()
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
  }

  // MARK: - Profile Header

  private var profileHeaderSection: some View {
    Section {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        HStack {
          Spacer()

          Button(String(localized: .commonDone)) {
            dismiss()
          }
          .font(.tidexHeadline)
          .foregroundColor(.tidexBlue)
          .buttonStyle(.plain)
        }

        HStack(spacing: Spacing.sm) {
          AvatarView(
            url: sharedUser.avatarUrl,
            initials: sharedUser.initials,
            size: 64
          )

          VStack(alignment: .leading, spacing: Spacing.micro) {
            Text(sharedUser.displayName)
              .font(.tidexTitle)
              .foregroundColor(.tidexTextPrimary)
              .lineLimit(1)
              .truncationMode(.tail)

            if let contactInfo = sharedUser.contactInfo {
              Text(contactInfo)
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }
        }
      }
      .padding(.vertical, Spacing.xs)
    }
    .listRowBackground(Color.clear)
  }

  // MARK: - Notification Section

  @ViewBuilder
  private func notificationSection(friend: Friend, sectionType: FriendSectionType) -> some View {
    Section(String(localized: .sharingNotificationsTitle)) {
      if sectionType == .mutual || sectionType == .incoming {
        Toggle(
          String(localized: .sharingMenuNotifyMeOfTheirShifts(friend.firstNameOnly)),
          isOn: .init(
            get: { !(friend.sharesWithMe?.isMuted ?? true) },
            set: { _ in
              Task { await viewModel.toggleMuted(for: friend) }
            }
          )
        )
      }

      if sectionType == .mutual || sectionType == .outgoing {
        Toggle(
          String(localized: .sharingMenuNotifyThemOfMyShifts(friend.firstNameOnly)),
          isOn: .init(
            get: { !(friend.iShareWith?.ownerMuted ?? true) },
            set: { _ in
              Task { await viewModel.toggleOwnerMuted(for: friend) }
            }
          )
        )
      }
    }
  }

  // MARK: - Sharing Section

  @ViewBuilder
  private func sharingSection(friend: Friend, sectionType: FriendSectionType) -> some View {
    switch sectionType {
    case .mutual, .outgoing:
      Section {
        Toggle(
          String(localized: .sharingMenuShowThemMyEarnings(friend.firstNameOnly)),
          isOn: .init(
            get: { friend.iShareWith?.showEarningsToThem ?? false },
            set: { _ in
              Task { await viewModel.toggleEarnings(for: friend) }
            }
          )
        )
      }
    case .incoming:
      Section {
        Button {
          Task { await viewModel.shareBack(with: friend) }
        } label: {
          Label(String(localized: .sharingShareBack), systemImage: "arrowshape.turn.up.left")
        }
      }
    }
  }

  // MARK: - Actions Section

  @ViewBuilder
  private func actionsSection(friend: Friend, sectionType: FriendSectionType) -> some View {
    Section {
      Button {
        onMessageTapped?()
      } label: {
        Label(
          String(localized: .friendsChatMessageFriend(sharedUser.displayName)),
          systemImage: "message.fill"
        )
      }

      if sectionType == .mutual || sectionType == .incoming || sectionType == .outgoing {
        let isHidden = viewModel.isHiddenInFriendsTab(for: friend)
        Button {
          Task {
            await viewModel.toggleHidden(for: friend)
            onVisibilityChange?()
          }
        } label: {
          Label(
            String(
              localized: isHidden
                ? .sharingProfileShowInList(friend.firstNameOnly)
                : .sharingProfileHideFromList(friend.firstNameOnly)),
            systemImage: isHidden ? "eye" : "eye.slash"
          )
        }
      }

      Button(role: .destructive) {
        friendToRemove = friend
        removeAction = sectionType == .incoming ? .removeSharer : .removeShare
      } label: {
        Label(String(localized: .sharingSwipeRemove), systemImage: "trash")
      }
    }
  }

  // MARK: - Manage Friends Link

  private var manageFriendsLink: some View {
    Section {
      Button {
        showManageSheet = true
      } label: {
        HStack {
          Spacer()
          Text(.sharingProfileManageFriends)
            .font(.tidexFootnote)
            .foregroundColor(.tidexBlue)
          Spacer()
        }
      }
    }
    .listRowBackground(Color.clear)
  }

  // MARK: - Confirmation Title

  private var confirmationTitle: String {
    guard let friend = friendToRemove, let action = removeAction else { return "" }
    switch action {
    case .removeShare:
      return String(localized: .sharingStopSharingWith(friend.displayName))
    case .removeSharer:
      return String(localized: .sharingRemoveFromList(friend.displayName))
    }
  }
}

// MARK: - Preview

#Preview {
  FriendProfileView(
    sharedUser: SharedUser(
      id: "1",
      email: "john@example.com",
      phone: nil,
      firstName: "John Doe",
      profilePictureUrl: nil,
      oauthAvatarUrl: nil,
      sharedAt: "2025-01-01",
      showEarnings: true,
      hidden: false
    )
  )
}
