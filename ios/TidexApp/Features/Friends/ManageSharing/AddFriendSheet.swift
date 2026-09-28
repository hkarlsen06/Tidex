import SwiftUI

// MARK: - Add Friend Sheet

/// Adds a friend by email, phone, or username.
/// Hidden and blocked people sit one tap further in, behind a row that names nobody,
/// so opening the sheet never shows someone the people they blocked.
/// Everything else about a friend lives in `FriendProfileView`.
struct AddFriendSheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var viewModel: ManageSharingViewModel
  @State private var didRequestInitialFocus = false
  @FocusState private var isIdentifierFocused: Bool

  private let onBootstrapRefresh: ((FriendsTabBootstrapData) async -> Void)?

  init(
    initialSnapshot: FriendsManagementSnapshot? = nil,
    onBootstrapRefresh: ((FriendsTabBootstrapData) async -> Void)? = nil
  ) {
    _viewModel = State(
      wrappedValue: ManageSharingViewModel(initialSnapshot: initialSnapshot)
    )
    self.onBootstrapRefresh = onBootstrapRefresh
  }

  private var canAdd: Bool {
    !viewModel.addIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !viewModel.isAdding
      && !viewModel.areServerActionsUnavailable
  }

  var body: some View {
    NavigationStack {
      Form {
        Group {
          addFriendSection

          if viewModel.hasHiddenOrBlockedPeople {
            Section {
              NavigationLink {
                HiddenAndBlockedPeopleView(viewModel: viewModel)
              } label: {
                Text(.sharingHiddenAndBlocked)
              }
            }
          }
        }
        .listRowBackground(Color.tidexSurfacePrimary)
      }
      .scrollContentBackground(.hidden)
      .background(Color.tidexBackground)
      .navigationTitle(String(localized: .sharingAddFriend))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { toolbarContent }
    }
    .task {
      viewModel.onBootstrapRefresh = onBootstrapRefresh
      if !didRequestInitialFocus {
        didRequestInitialFocus = true
        isIdentifierFocused = true
      }
      await viewModel.loadFriendsIfNeeded()
    }
    .alert(
      String(localized: .commonError),
      isPresented: .init(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.errorMessage = nil } }
      )
    ) {
      Button(String(localized: .commonOk), role: .cancel) {
        viewModel.errorMessage = nil
      }
    } message: {
      Text(viewModel.errorMessage ?? "")
    }
  }

  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button(String(localized: .commonCancel)) {
        dismiss()
      }
    }

    ToolbarItem(placement: .confirmationAction) {
      if viewModel.isAdding {
        ProgressView()
      } else {
        Button(String(localized: .sharingAdd), action: add)
          .disabled(!canAdd)
      }
    }
  }

  // MARK: - Sections

  private var addFriendSection: some View {
    Section {
      TextField(
        String(localized: .sharingEmailOrPhoneOrUsername),
        text: $viewModel.addIdentifier
      )
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .submitLabel(.done)
      .focused($isIdentifierFocused)
      .onSubmit(add)
      .onChange(of: viewModel.addIdentifier) { _, _ in
        viewModel.addError = nil
      }

      Toggle(String(localized: .sharingShowEarnings), isOn: $viewModel.addShowEarnings)
        .tint(.tidexBlue)
    } footer: {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        if let error = viewModel.addError {
          Text(error)
            .foregroundStyle(Color.tidexError)
        }

        if viewModel.areServerActionsUnavailable {
          Text(.sharingOfflineAddFriendUnavailable)
        } else {
          // Adding someone starts sharing at once; there is no request for them to accept.
          Text(
            viewModel.addShowEarnings
              ? .sharingAddFriendSharesRightAwayWithEarnings : .sharingAddFriendSharesRightAway
          )
        }
      }
    }
    .disabled(viewModel.isAdding || viewModel.areServerActionsUnavailable)
  }

  // MARK: - Actions

  private func add() {
    guard canAdd else { return }
    Task {
      if await viewModel.addFriend() {
        Haptics.play(.success)
        dismiss()
      }
    }
  }
}

// MARK: - Hidden and Blocked People

/// Pushed from `AddFriendSheet`. Pops itself once nobody is left to show.
private struct HiddenAndBlockedPeopleView: View {
  @Environment(\.dismiss) private var dismiss

  let viewModel: ManageSharingViewModel

  var body: some View {
    Form {
      Group {
        if !viewModel.hiddenFriends.isEmpty {
          hiddenFriendsSection
        }

        if !viewModel.blockedFriends.isEmpty {
          blockedFriendsSection
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .scrollContentBackground(.hidden)
    .background(Color.tidexBackground)
    .navigationTitle(String(localized: .sharingHiddenAndBlocked))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: viewModel.hasHiddenOrBlockedPeople) { _, hasPeople in
      if !hasPeople {
        dismiss()
      }
    }
  }

  private var hiddenFriendsSection: some View {
    Section {
      ForEach(viewModel.hiddenFriends) { friend in
        // Showing an incoming sharer again is a server call; outgoing-only hiding is local.
        let isUnavailable =
          viewModel.actionInProgress != nil
          || (viewModel.areServerActionsUnavailable && friend.sharesWithMe != nil)

        personRow(friend, actionTitle: String(localized: .sharingHiddenShow), isDisabled: isUnavailable) {
          Task { await viewModel.toggleHidden(for: friend) }
        }
      }
    } header: {
      Text(.sharingHidden)
    } footer: {
      Text(.sharingHiddenDescription)
    }
  }

  private var blockedFriendsSection: some View {
    Section {
      ForEach(viewModel.blockedFriends) { friend in
        personRow(
          friend,
          actionTitle: String(localized: .sharingUnblock),
          isDisabled: viewModel.actionInProgress != nil || viewModel.areServerActionsUnavailable
        ) {
          Task { await viewModel.unblockFriend(friend) }
        }
      }
    } header: {
      Text(.sharingBlockedUsersTitle)
    } footer: {
      Text(.sharingBlockedUsersDescription)
    }
  }

  private func personRow(
    _ friend: Friend,
    actionTitle: String,
    isDisabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: Spacing.sm) {
      AvatarView(
        url: friend.avatarUrl,
        initials: friend.initials,
        size: AvatarView.Size.medium
      )

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

      if viewModel.actionInProgress == friend.id {
        ProgressView()
      } else {
        Button(actionTitle, action: action)
          .buttonStyle(.borderless)
          .tint(.tidexBlue)
          .disabled(isDisabled)
      }
    }
    .padding(.vertical, Spacing.xxxs)
  }
}

// MARK: - Preview

#Preview {
  AddFriendSheet()
}
