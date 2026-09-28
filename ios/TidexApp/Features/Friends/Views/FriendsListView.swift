import SwiftUI

struct FriendsListOrdering {
  let typingUserIds: Set<String>
  let unreadChatUserIds: Set<String>
  let bottomedUserIds: Set<String>
  let chatPreviewsByUserId: [String: FriendCardMessagePreview]
  let shiftPreviews: [String: SharerShiftPreview]
  let isLoadingShiftPreviews: Bool

  func sortedSharers(_ sharers: [SharedUser]) -> [SharedUser] {
    let descriptors = Dictionary(
      uniqueKeysWithValues: sharers.map { ($0.id, sortDescriptor(for: $0)) })
    return sharers.sorted { lhs, rhs in
      compare(
        lhsDescriptor: descriptors[lhs.id] ?? sortDescriptor(for: lhs),
        rhsDescriptor: descriptors[rhs.id] ?? sortDescriptor(for: rhs)
      )
    }
  }

  func visibleSharers(visible: [SharedUser], hidden: [SharedUser]) -> [SharedUser] {
    let visibleIds = Set(visible.map(\.id))
    let temporarilyVisibleHiddenSharers = hidden.filter {
      !visibleIds.contains($0.id) && unreadChatUserIds.contains($0.id)
    }

    return sortedSharers(visible + temporarilyVisibleHiddenSharers)
  }

  private func sortDescriptor(for sharer: SharedUser) -> FriendSortDescriptor {
    let preview = shiftPreviews[sharer.id]

    return FriendSortDescriptor(
      displayName: sharer.displayName,
      isBottomed: bottomedUserIds.contains(sharer.id) && !typingUserIds.contains(sharer.id),
      messageStatus: messageStatus(for: sharer.id),
      shiftStatus: isLoadingShiftPreviews ? nil : preview?.status,
      shiftPriority: isLoadingShiftPreviews ? 3 : shiftStatusPriority(for: preview?.status),
      shiftTime: isLoadingShiftPreviews ? nil : preview?.shift.flatMap { shiftStartTime(for: $0) }
    )
  }

  private func compare(
    lhsDescriptor: FriendSortDescriptor,
    rhsDescriptor: FriendSortDescriptor
  ) -> Bool {
    if lhsDescriptor.isBottomed != rhsDescriptor.isBottomed {
      return !lhsDescriptor.isBottomed
    }

    let messageStatusLhs = lhsDescriptor.messageStatus
    let messageStatusRhs = rhsDescriptor.messageStatus

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

    return compareShiftFallback(lhsDescriptor, rhsDescriptor)
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
  private func compareShiftFallback(_ lhs: FriendSortDescriptor, _ rhs: FriendSortDescriptor)
    -> Bool
  {
    guard !isLoadingShiftPreviews, !shiftPreviews.isEmpty else {
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    if lhs.shiftPriority != rhs.shiftPriority {
      return lhs.shiftPriority < rhs.shiftPriority
    }

    guard let timeLhs = lhs.shiftTime, let timeRhs = rhs.shiftTime else {
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    switch lhs.shiftStatus {
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

    return Calendar.gregorianCurrent.date(
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

private struct FriendSortDescriptor {
  let displayName: String
  let isBottomed: Bool
  let messageStatus: MessageStatusSortDescriptor
  let shiftStatus: ShiftPreviewStatus?
  let shiftPriority: Int
  let shiftTime: Date?
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
  let bottomedUserIds: Set<String>
  let unreadChatCountsByUserId: [String: Int]
  let chatPreviewsByUserId: [String: FriendCardMessagePreview]
  let selectedSharer: SharedUser?
  let shiftPreviews: [String: SharerShiftPreview]
  let isLoading: Bool
  let isLoadingPreviews: Bool
  let hasFinishedInitialLoad: Bool
  let isRefreshing: Bool
  let onSelectSharer: (SharedUser) -> Void
  let onMessageTap: (SharedUser) -> Void
  let onProfileRequested: (SharedUser) -> Void
  // swiftlint:disable:next explicit_acl
  var highlightedChatUserId: String?
  // swiftlint:disable:next explicit_acl
  var openingThreadUserId: String?
  var onAddFriend: (() -> Void)?

  private var sortedVisibleSharers: [SharedUser] {
    ordering.visibleSharers(visible: sharers, hidden: hiddenSharers)
  }

  private var ordering: FriendsListOrdering {
    FriendsListOrdering(
      typingUserIds: typingUserIds,
      unreadChatUserIds: unreadChatUserIds,
      bottomedUserIds: bottomedUserIds,
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
      } else if sortedVisibleSharers.isEmpty {
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
    }
    .padding(.horizontal, Spacing.md)
    .animation(.spring(duration: 0.4, bounce: 0.15), value: isLoadingPreviews)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: unreadChatUserIds)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: typingUserIds)
    .animation(.spring(duration: 0.35, bounce: 0.12), value: bottomedUserIds)
  }

  @ViewBuilder
  private func sharerCard(for sharer: SharedUser) -> some View {
    let preview = shiftPreviews[sharer.id]
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
      onProfileRequested: {
        onProfileRequested(sharer)
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
    bottomedUserIds: [],
    unreadChatCountsByUserId: [:],
    chatPreviewsByUserId: [:],
    selectedSharer: nil,
    shiftPreviews: [:],
    isLoading: false,
    isLoadingPreviews: false,
    hasFinishedInitialLoad: true,
    isRefreshing: false,
    onSelectSharer: { _ in },
    onMessageTap: { _ in },
    onProfileRequested: { _ in }
  )
  .background(Color.tidexBackground)
}
