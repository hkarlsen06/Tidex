import SwiftUI

/// Friends' next shifts, above the add-a-job invitation on Home for a user without a job.
/// Uses the same view model and cache as the Friends tab.
struct HomeFriendsShifts: View {
  @Environment(AppCoordinator.self) private var coordinator
  @State private var viewModel = SharingViewModel()

  var body: some View {
    FriendsNextShiftsList(
      sharers: viewModel.sharers.filter { !viewModel.chatOnlyUserIds.contains($0.id) },
      previews: viewModel.shiftPreviews
    ) { sharer in
      // Opens the friend's calendar on the Friends tab.
      coordinator.pendingDeepLink = .sharing(
        sharerId: sharer.id, highlightDates: nil, changes: nil)
    }
    .task { await viewModel.loadSharers() }
  }
}

/// Up to three friends with a shift under way or coming up, soonest first. Shows nothing
/// when no friend has one.
struct FriendsNextShiftsList: View {
  let sharers: [SharedUser]
  let previews: [String: SharerShiftPreview]
  let onOpen: (SharedUser) -> Void

  private static let maxCount = 3

  private var friendsWithShifts: [SharedUser] {
    let ordering = FriendsListOrdering(
      typingUserIds: [], unreadChatUserIds: [], bottomedUserIds: [], chatPreviewsByUserId: [:],
      shiftPreviews: previews, isLoadingShiftPreviews: false)
    let withShifts = sharers.filter { previews[$0.id]?.status.map { $0 != .past } ?? false }
    return Array(ordering.sortedSharers(withShifts).prefix(Self.maxCount))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      if !friendsWithShifts.isEmpty {
        Text(.sharingHomeNextShifts)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)
          .accessibilityAddTraits(.isHeader)

        ForEach(friendsWithShifts) { sharer in
          FriendCard(
            sharer: sharer, preview: previews[sharer.id], messagePreview: nil, isTyping: false,
            isSelected: false, isRefreshing: false,
            onChatTap: { onOpen(sharer) }, onCalendarTap: { onOpen(sharer) })
        }
      }
    }
  }
}
