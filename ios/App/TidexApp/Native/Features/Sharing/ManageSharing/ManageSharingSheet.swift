import SwiftUI

// MARK: - Manage Sharing Sheet

/// Modal sheet for managing sharing relationships
/// Allows viewing/editing friends, adding new recipients, and controlling settings
struct ManageSharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.localization) private var localization

    @StateObject private var viewModel = ManageSharingViewModel()

    /// Callback when visibility changes (block/unblock) to refresh the sharer list
    var onVisibilityChange: (() -> Void)?

    /// Confirmation dialog state
    @State private var friendToRemove: Friend?
    @State private var removeAction: RemoveAction?

    enum RemoveAction {
        case removeShare    // Revoke their access to my shifts
        case removeSharer   // Remove them from my friends list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Description
                        descriptionSection

                        // Error banner
                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                        }

                        // Friend sections
                        if viewModel.isLoading {
                            loadingView
                        } else if viewModel.friends.isEmpty {
                            emptyState
                        } else {
                            friendSections
                        }

                        // Add friend form
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
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
            .navigationTitle(localization.string("sharing.manageTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localization.string("common.done")) {
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.tidexBlue)
                }
            }
        }
        .task {
            await viewModel.loadFriends()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: .init(
                get: { friendToRemove != nil },
                set: { if !$0 { friendToRemove = nil; removeAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localization.string("sharing.remove"), role: .destructive) {
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
            Button(localization.string("common.cancel"), role: .cancel) {
                friendToRemove = nil
                removeAction = nil
            }
        }
        .onChange(of: viewModel.friends) { _, _ in
            // Notify parent when friends list changes
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
            return "Slutte å dele med \(friend.displayName)?"
        case .removeSharer:
            return "Fjerne \(friend.displayName) fra listen?"
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("sharing.manageDescription"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.tidexTextPrimary)

            Spacer()

            Button(action: { viewModel.errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.1))
        )
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                .scaleEffect(1.2)

            Text("Laster venner...")
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundColor(.tidexTextMuted)

            Text(localization.string("sharing.noFriends"))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.tidexTextPrimary)

            Text("Legg til venner for å dele vaktene dine")
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Friend Sections

    @ViewBuilder
    private var friendSections: some View {
        // Mutual shares
        if !viewModel.mutualFriends.isEmpty {
            friendSection(
                title: localization.string("sharing.mutual"),
                friends: viewModel.mutualFriends,
                sectionType: .mutual
            )
        }

        // Outgoing shares (I share with them)
        if !viewModel.outgoingOnlyFriends.isEmpty {
            friendSection(
                title: localization.string("sharing.iShareWith"),
                friends: viewModel.outgoingOnlyFriends,
                sectionType: .outgoing
            )
        }

        // Incoming shares (they share with me)
        if !viewModel.incomingOnlyFriends.isEmpty {
            friendSection(
                title: localization.string("sharing.sharesWithMe"),
                friends: viewModel.incomingOnlyFriends,
                sectionType: .incoming
            )
        }
    }

    private func friendSection(title: String, friends: [Friend], sectionType: FriendSectionType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextMuted)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            // Friends list
            VStack(spacing: 0) {
                ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                    FriendRow(
                        friend: friend,
                        sectionType: sectionType,
                        isActionInProgress: viewModel.actionInProgress == friend.id,
                        onToggleMuted: {
                            Task {
                                await viewModel.toggleMuted(for: friend)
                            }
                        },
                        onToggleBlocked: {
                            Task {
                                await viewModel.toggleBlocked(for: friend)
                                onVisibilityChange?()
                            }
                        },
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
                        onRemove: {
                            // Show confirmation dialog
                            friendToRemove = friend
                            removeAction = sectionType == .incoming ? .removeSharer : .removeShare
                        }
                    )

                    // Divider (except last item)
                    if index < friends.count - 1 {
                        Divider()
                            .padding(.leading, 68)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tidexSurfacePrimary)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ManageSharingSheet()
        .environment(\.localization, LocalizationManager.shared)
}
