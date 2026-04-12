import SwiftUI

struct FriendsListOrdering {
  let typingUserIds: Set<String>
  let unreadChatUserIds: Set<String>
  let chatPreviewsByUserId: [String: FriendCardMessagePreview]
  let shiftPreviews: [String: SharerShiftPreview]
  let isLoadingShiftPreviews: Bool

  func sortedSharers(_ sharers: [SharedUser]) -> [SharedUser] {
    sharers.sorted(by: compare)
  }

  func visibleSharers(visible: [SharedUser], hidden: [SharedUser]) -> [SharedUser] {
    sortedSharers(visible + hidden.filter { hasMessageStatus(for: $0.id) })
  }

  func hiddenDisclosureSharers(_ hidden: [SharedUser]) -> [SharedUser] {
    sortedSharers(hidden.filter { !hasMessageStatus(for: $0.id) })
  }

  func shouldSuppressShiftPreview(for sharer: SharedUser) -> Bool {
    sharer.hidden && hasMessageStatus(for: sharer.id)
  }

  private func compare(_ lhs: SharedUser, _ rhs: SharedUser) -> Bool {
    let messageStatusLhs = messageStatus(for: lhs.id)
    let messageStatusRhs = messageStatus(for: rhs.id)

    if messageStatusLhs.isPresent != messageStatusRhs.isPresent {
      return messageStatusLhs.isPresent
    }

    if messageStatusLhs.isPresent, messageStatusRhs.isPresent {
      if messageStatusLhs.isTyping != messageStatusRhs.isTyping {
        return messageStatusLhs.isTyping
      }

      if messageStatusLhs.timestamp != messageStatusRhs.timestamp {
        switch (messageStatusLhs.timestamp, messageStatusRhs.timestamp) {
        case (let lhsTimestamp?, let rhsTimestamp?):
          return lhsTimestamp > rhsTimestamp
        case (.some, .none):
          return true
        case (.none, .some):
          return false
        case (.none, .none):
          break
        }
      }

      if messageStatusLhs.priority != messageStatusRhs.priority {
        return messageStatusLhs.priority < messageStatusRhs.priority
      }
    }

    return compareShiftFallback(lhs, rhs)
  }

  private func messageStatus(for sharerId: String) -> MessageStatusSortDescriptor {
    let preview = chatPreviewsByUserId[sharerId]
    let isTyping = typingUserIds.contains(sharerId)
    let hasUnread = unreadChatUserIds.contains(sharerId)

    return MessageStatusSortDescriptor(
      isPresent: isTyping || hasUnread || preview != nil,
      isTyping: isTyping,
      priority: messagePriority(
        isTyping: isTyping,
        hasUnread: hasUnread,
        previewState: preview?.state
      ),
      timestamp: preview?.timestamp
    )
  }

  func hasMessageStatus(for sharerId: String) -> Bool {
    messageStatus(for: sharerId).isPresent
  }

  private func messagePriority(
    isTyping: Bool,
    hasUnread: Bool,
    previewState: FriendCardMessageState?
  ) -> Int {
    if isTyping {
      return 0
    }

    if hasUnread {
      return 1
    }

    switch previewState {
    case .outgoingFailed:
      return 2
    case .outgoingSending:
      return 3
    case .outgoingSent, .outgoingOpened, .incomingOpened:
      return 4
    case .incomingUnread:
      return 1
    case .none:
      return 5
    }
  }

  /// Falls back to the original shift-based ordering for users without message activity.
  private func compareShiftFallback(_ lhs: SharedUser, _ rhs: SharedUser) -> Bool {
    guard !isLoadingShiftPreviews && !shiftPreviews.isEmpty else {
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    let previewLhs = shiftPreviews[lhs.id]
    let previewRhs = shiftPreviews[rhs.id]

    let priorityLhs = shiftStatusPriority(for: previewLhs?.status)
    let priorityRhs = shiftStatusPriority(for: previewRhs?.status)

    if priorityLhs != priorityRhs {
      return priorityLhs < priorityRhs
    }

    guard let shiftLhs = previewLhs?.shift, let shiftRhs = previewRhs?.shift else {
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    let timeLhs = shiftStartTime(for: shiftLhs)
    let timeRhs = shiftStartTime(for: shiftRhs)

    guard let timeLhs, let timeRhs else {
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    switch previewLhs?.status {
    case .upcoming:
      if timeLhs == timeRhs {
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
      return timeLhs < timeRhs
    case .past:
      if timeLhs == timeRhs {
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
      return timeLhs > timeRhs
    default:
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
  }

  private func shiftStatusPriority(for status: ShiftPreviewStatus?) -> Int {
    switch status {
    case .active: return 0
    case .upcoming: return 1
    case .past: return 2
    case .none: return 3
    }
  }

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
}

private struct MessageStatusSortDescriptor {
  let isPresent: Bool
  let isTyping: Bool
  let priority: Int
  let timestamp: Date?
}

enum FriendCalendarAvailability {
  static func isAvailable(
    sharer: SharedUser,
    chatOnlyUserIds: Set<String>,
    preview: SharerShiftPreview?
  ) -> Bool {
    guard !chatOnlyUserIds.contains(sharer.id) else { return false }
    return sharer.hasSharedCalendarContent || (preview?.hasSharedCalendarContent ?? false)
  }
}

/// List of users who share their shifts with the current user.
/// Uses message activity first, then falls back to the legacy shift proximity ordering.
struct SharerListView: View {
  let sharers: [SharedUser]
  let hiddenSharers: [SharedUser]
  let chatOnlyUserIds: Set<String>
  let typingUserIds: Set<String>
  let unreadChatUserIds: Set<String>
  let unreadChatCountsByUserId: [String: Int]
  let chatPreviewsByUserId: [String: FriendCardMessagePreview]
  let selectedSharer: SharedUser?
  let shiftPreviews: [String: SharerShiftPreview]
  let isLoading: Bool
  let isLoadingPreviews: Bool
  let hasFinishedInitialLoad: Bool
  let isRefreshing: Bool
  let onSelectSharer: (SharedUser) -> Void
  let onSelectHiddenSharer: (SharedUser) -> Void
  let onMessageTap: (SharedUser) -> Void
  var highlightedChatUserId: String? = nil
  var openingThreadUserId: String? = nil
  var onAddFriend: (() -> Void)?

  @State private var isShowingHiddenSharers = false

  private var sortedVisibleSharers: [SharedUser] {
    ordering.visibleSharers(visible: sharers, hidden: hiddenSharers)
  }

  private var sortedHiddenSharers: [SharedUser] {
    ordering.hiddenDisclosureSharers(hiddenSharers)
  }

  private var ordering: FriendsListOrdering {
    FriendsListOrdering(
      typingUserIds: typingUserIds,
      unreadChatUserIds: unreadChatUserIds,
      chatPreviewsByUserId: chatPreviewsByUserId,
      shiftPreviews: shiftPreviews,
      isLoadingShiftPreviews: isLoadingPreviews
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
      ForEach(sortedVisibleSharers) { sharer in
        sharerCard(for: sharer)
      }

      if !sortedHiddenSharers.isEmpty {
        hiddenSharersDisclosure
      }
    }
    .padding(.horizontal, Spacing.md)
    .animation(.spring(duration: 0.4, bounce: 0.15), value: isLoadingPreviews)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: isShowingHiddenSharers)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: unreadChatUserIds)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: typingUserIds)
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

          Text("\(sortedHiddenSharers.count)")
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
        ForEach(sortedHiddenSharers) { sharer in
          hiddenSharerCard(for: sharer)
        }
      }
    }
  }

  @ViewBuilder
  private func sharerCard(for sharer: SharedUser) -> some View {
    let suppressShiftPreview = ordering.shouldSuppressShiftPreview(for: sharer)
    let preview = suppressShiftPreview ? nil : shiftPreviews[sharer.id]
    let isOpeningMessage = openingThreadUserId == sharer.id
    let isSelected =
      selectedSharer?.id == sharer.id
      || highlightedChatUserId == sharer.id
      || isOpeningMessage
    let isCalendarAvailable = FriendCalendarAvailability.isAvailable(
      sharer: sharer,
      chatOnlyUserIds: chatOnlyUserIds,
      preview: shiftPreviews[sharer.id]
    )

    FriendCard(
      sharer: sharer,
      preview: preview,
      messagePreview: chatPreviewsByUserId[sharer.id],
      isTyping: typingUserIds.contains(sharer.id),
      isSelected: isSelected,
      isRefreshing: isRefreshing,
      onChatTap: {
        onMessageTap(sharer)
      },
      onCalendarTap: {
        if !isCalendarAvailable {
          return
        }
        onSelectSharer(sharer)
      },
      isCalendarAvailable: isCalendarAvailable,
      isOpeningMessage: isOpeningMessage,
      unreadMessageCount: unreadChatCountsByUserId[sharer.id] ?? 0
    )
  }

  @ViewBuilder
  private func hiddenSharerCard(for sharer: SharedUser) -> some View {
    let preview = shiftPreviews[sharer.id]
    let isOpeningMessage = openingThreadUserId == sharer.id
    let isSelected =
      selectedSharer?.id == sharer.id
      || highlightedChatUserId == sharer.id
      || isOpeningMessage
    let isCalendarAvailable = FriendCalendarAvailability.isAvailable(
      sharer: sharer,
      chatOnlyUserIds: chatOnlyUserIds,
      preview: preview
    )

    FriendCard(
      sharer: sharer,
      preview: preview,
      messagePreview: chatPreviewsByUserId[sharer.id],
      isTyping: typingUserIds.contains(sharer.id),
      isSelected: isSelected,
      isRefreshing: isRefreshing,
      onChatTap: {
        onMessageTap(sharer)
      },
      onCalendarTap: {
        if !isCalendarAvailable {
          return
        }
        onSelectHiddenSharer(sharer)
      },
      isCalendarAvailable: isCalendarAvailable,
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
    typingUserIds: [],
    unreadChatUserIds: [],
    unreadChatCountsByUserId: [:],
    chatPreviewsByUserId: [:],
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
