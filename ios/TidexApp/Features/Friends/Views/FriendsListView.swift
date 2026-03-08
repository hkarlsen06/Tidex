import SwiftUI

/// List of users who share their shifts with the current user
/// Sorts sharers by shift proximity to match Next.js behavior:
/// 1. Active shifts first (currently happening)
/// 2. Upcoming shifts next (soonest first)
/// 3. Past shifts next (most recent first)
/// 4. No shifts last
struct SharerListView: View {
  let sharers: [SharedUser]
  let hiddenSharers: [SharedUser]
  let chatOnlyUserIds: Set<String>
  let unreadChatUserIds: Set<String>
  let unreadChatCountsByUserId: [String: Int]
  let selectedSharer: SharedUser?
  let shiftPreviews: [String: SharerShiftPreview]
  let isLoading: Bool
  let isLoadingPreviews: Bool
  let hasFinishedInitialLoad: Bool
  let isRefreshing: Bool
  let onSelectSharer: (SharedUser) -> Void
  let onSelectHiddenSharer: (SharedUser) -> Void
  let onMessageTap: (SharedUser) -> Void
  var openingThreadUserId: String? = nil
  var onAddFriend: (() -> Void)?

  @State private var isShowingHiddenSharers = false

  private var sortedVisibleSharers: [SharedUser] {
    sortedSharers(from: sharers)
  }

  private var sortedHiddenSharers: [SharedUser] {
    sortedSharers(from: hiddenSharers)
  }

  private var promotedUnreadSharers: [SharedUser] {
    let combined = sortedSharers(from: sharers + hiddenSharers)
    var seenIds = Set<String>()

    return combined.filter { sharer in
      guard unreadChatUserIds.contains(sharer.id), seenIds.insert(sharer.id).inserted else {
        return false
      }
      return true
    }
  }

  private var sortedVisibleNonUnreadSharers: [SharedUser] {
    sortedVisibleSharers.filter { !unreadChatUserIds.contains($0.id) }
  }

  private var sortedHiddenNonUnreadSharers: [SharedUser] {
    sortedHiddenSharers.filter { !unreadChatUserIds.contains($0.id) }
  }

  /// Sharers sorted by shift proximity (matches Next.js SharersList.tsx sorting)
  /// Sorting is deferred until previews finish loading to prevent layout jumps
  private func sortedSharers(from sharers: [SharedUser]) -> [SharedUser] {
    // While previews are loading, maintain stable alphabetical order
    // This prevents jarring re-sorts as individual previews arrive
    guard !isLoadingPreviews && !shiftPreviews.isEmpty else {
      return sharers.sorted {
        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
      }
    }

    return sharers.sorted { a, b in
      let previewA = shiftPreviews[a.id]
      let previewB = shiftPreviews[b.id]

      // Priority: active > upcoming > past > no shift
      let priorityA = statusPriority(for: previewA?.status)
      let priorityB = statusPriority(for: previewB?.status)

      if priorityA != priorityB {
        return priorityA < priorityB
      }

      // Within same status, sort by time
      guard let shiftA = previewA?.shift, let shiftB = previewB?.shift else {
        // Fallback to alphabetical for stable ordering
        return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
      }

      let timeA = shiftStartTime(for: shiftA)
      let timeB = shiftStartTime(for: shiftB)

      guard let timeA = timeA, let timeB = timeB else {
        return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
      }

      switch previewA?.status {
      case .upcoming:
        // Upcoming: soonest first (ascending), then alphabetical for same time
        if timeA == timeB {
          return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        return timeA < timeB
      case .past:
        // Past: most recent first (descending), then alphabetical for same time
        if timeA == timeB {
          return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
        return timeA > timeB
      default:
        return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
      }
    }
  }

  /// Get priority value for status (lower = higher priority)
  private func statusPriority(for status: ShiftPreviewStatus?) -> Int {
    switch status {
    case .active: return 0
    case .upcoming: return 1
    case .past: return 2
    case .none: return 3
    }
  }

  /// Parse shift start time for sorting
  private func shiftStartTime(for shift: SharedShiftData) -> Date? {
    guard let shiftDate = Date.fromISODateString(shift.shift_date) else { return nil }

    let components = shift.start_time.split(separator: ":").compactMap { Int($0) }
    guard components.count >= 2 else { return nil }

    return Calendar.current.date(
      bySettingHour: components[0],
      minute: components[1],
      second: 0,
      of: shiftDate
    )
  }

  var body: some View {
    Group {
      if (!hasFinishedInitialLoad && sharers.isEmpty && hiddenSharers.isEmpty)
        || (isLoading && sharers.isEmpty && hiddenSharers.isEmpty)
      {
        loadingState
      } else if sharers.isEmpty && hiddenSharers.isEmpty {
        FriendsListEmptyState(onAddFriend: onAddFriend)
      } else {
        sharersList
      }
    }
  }

  private var loadingState: some View {
    VStack(spacing: Spacing.md) {
      ProgressView()
        .scaleEffect(1.2)

      Text(.sharingLoading)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.vertical, 80)
  }

  private var sharersList: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      ForEach(promotedUnreadSharers) { sharer in
        sharerCard(for: sharer)
      }

      ForEach(sortedVisibleNonUnreadSharers) { sharer in
        sharerCard(for: sharer)
      }

      if !sortedHiddenNonUnreadSharers.isEmpty {
        hiddenSharersDisclosure
      }
    }
    .padding(.horizontal, Spacing.md)
    .animation(.spring(duration: 0.4, bounce: 0.15), value: isLoadingPreviews)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: isShowingHiddenSharers)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: unreadChatUserIds)
  }

  @ViewBuilder
  private var hiddenSharersDisclosure: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Button {
        withAnimation(.spring(duration: 0.35, bounce: 0.12)) {
          isShowingHiddenSharers.toggle()
        }
      } label: {
        HStack(spacing: Spacing.xs) {
          Image(systemName: "eye.slash")
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexTextMuted)

          Text(.sharingHidden)
            .font(.tidexLabelStrong)
            .foregroundColor(.tidexTextPrimary)

          Text("\(sortedHiddenNonUnreadSharers.count)")
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexTextMuted)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxxs)
            .background(
              Capsule(style: .continuous)
                .fill(Color.tidexSurfaceSecondary)
            )

          Spacer()

          Image(systemName: isShowingHiddenSharers ? "chevron.up" : "chevron.down")
            .font(.tidexFootnoteMedium)
            .foregroundColor(.tidexTextMuted)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
            .fill(Color.tidexSurfacePrimary)
        )
        .tidexCardShadow(.subtle, cornerRadius: CornerRadius.card)
      }
      .buttonStyle(.plain)

      if isShowingHiddenSharers {
        ForEach(sortedHiddenNonUnreadSharers) { sharer in
          hiddenSharerCard(for: sharer)
        }
      }
    }
  }

  @ViewBuilder
  private func sharerCard(for sharer: SharedUser) -> some View {
    let preview = shiftPreviews[sharer.id]
    let isSelected = selectedSharer?.id == sharer.id
    let isOpeningMessage = openingThreadUserId == sharer.id
    let opensChatDirectly = chatOnlyUserIds.contains(sharer.id)

    FriendCard(
      sharer: sharer,
      preview: preview,
      isSelected: isSelected,
      isRefreshing: isRefreshing,
      onChatTap: {
        onMessageTap(sharer)
      },
      onCalendarTap: {
        if opensChatDirectly {
          return
        }
        onSelectSharer(sharer)
      },
      isCalendarAvailable: !opensChatDirectly,
      isOpeningMessage: isOpeningMessage,
      unreadMessageCount: unreadChatCountsByUserId[sharer.id] ?? 0
    )
  }

  @ViewBuilder
  private func hiddenSharerCard(for sharer: SharedUser) -> some View {
    let preview = shiftPreviews[sharer.id]
    let isSelected = selectedSharer?.id == sharer.id
    let isOpeningMessage = openingThreadUserId == sharer.id
    let opensChatDirectly = chatOnlyUserIds.contains(sharer.id)

    FriendCard(
      sharer: sharer,
      preview: preview,
      isSelected: isSelected,
      isRefreshing: isRefreshing,
      onChatTap: {
        onMessageTap(sharer)
      },
      onCalendarTap: {
        if opensChatDirectly {
          return
        }
        onSelectHiddenSharer(sharer)
      },
      isCalendarAvailable: !opensChatDirectly,
      isOpeningMessage: isOpeningMessage,
      unreadMessageCount: unreadChatCountsByUserId[sharer.id] ?? 0
    )
  }
}

#Preview {
  SharerListView(
    sharers: [
      SharedUser(
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
    ],
    hiddenSharers: [
      SharedUser(
        id: "2",
        email: "jane@example.com",
        phone: nil,
        firstName: "Jane Smith",
        profilePictureUrl: nil,
        oauthAvatarUrl: nil,
        sharedAt: "2025-01-01",
        showEarnings: false,
        hidden: true
      )
    ],
    chatOnlyUserIds: [],
    unreadChatUserIds: [],
    unreadChatCountsByUserId: [:],
    selectedSharer: nil,
    shiftPreviews: [:],
    isLoading: false,
    isLoadingPreviews: false,
    hasFinishedInitialLoad: true,
    isRefreshing: false,
    onSelectSharer: { _ in },
    onSelectHiddenSharer: { _ in },
    onMessageTap: { _ in }
  )
  .background(Color.tidexBackground)
}
