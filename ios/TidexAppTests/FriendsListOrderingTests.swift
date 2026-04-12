import XCTest

@testable import Tidex

final class FriendsListOrderingTests: XCTestCase {
  func testMessagingActivitySortsByLatestMessageBeforeShiftFallback() {
    let users = [
      makeUser(id: "active-shift", firstName: "Active"),
      makeUser(id: "older-message", firstName: "Older"),
      makeUser(id: "newer-message", firstName: "Newer"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: ["older-message"],
      chatPreviewsByUserId: [
        "older-message": FriendCardMessagePreview(
          text: "Unread",
          timestamp: Date(timeIntervalSince1970: 1_700_000_100),
          state: .incomingUnread
        ),
        "newer-message": FriendCardMessagePreview(
          text: "Seen",
          timestamp: Date(timeIntervalSince1970: 1_700_000_200),
          state: .incomingOpened
        ),
      ],
      shiftPreviews: [
        "active-shift": makeShiftPreview(
          sharerId: "active-shift",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        )
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(
      ordering.sortedSharers(users).map(\.id),
      ["newer-message", "older-message", "active-shift"]
    )
  }

  func testFallsBackToLegacyShiftOrderingWhenNoMessageStatusExists() {
    let users = [
      makeUser(id: "no-shift", firstName: "No Shift"),
      makeUser(id: "upcoming", firstName: "Upcoming"),
      makeUser(id: "active", firstName: "Active"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: [],
      chatPreviewsByUserId: [:],
      shiftPreviews: [
        "upcoming": makeShiftPreview(
          sharerId: "upcoming",
          shiftDate: "2026-03-19",
          startTime: "09:00",
          endTime: "17:00",
          status: .upcoming
        ),
        "active": makeShiftPreview(
          sharerId: "active",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        ),
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(ordering.sortedSharers(users).map(\.id), ["active", "upcoming", "no-shift"])
  }

  func testHiddenUsersWithMessageActivityArePromotedOutOfHiddenDisclosure() {
    let visible = [
      makeUser(id: "visible", firstName: "Visible", hidden: false)
    ]
    let hidden = [
      makeUser(id: "hidden-chat", firstName: "Hidden Chat", hidden: true),
      makeUser(id: "hidden-shift", firstName: "Hidden Shift", hidden: true),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: [],
      chatPreviewsByUserId: [
        "hidden-chat": FriendCardMessagePreview(
          text: "Hey",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingOpened
        )
      ],
      shiftPreviews: [
        "hidden-chat": makeShiftPreview(
          sharerId: "hidden-chat",
          shiftDate: "2026-03-20",
          startTime: "10:00",
          endTime: "18:00",
          status: .upcoming
        ),
        "hidden-shift": makeShiftPreview(
          sharerId: "hidden-shift",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        ),
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(
      ordering.visibleSharers(visible: visible, hidden: hidden).map(\.id),
      ["hidden-chat", "visible"]
    )
    XCTAssertEqual(ordering.hiddenDisclosureSharers(hidden).map(\.id), ["hidden-shift"])
    XCTAssertTrue(ordering.shouldSuppressShiftPreview(for: hidden[0]))
    XCTAssertFalse(ordering.shouldSuppressShiftPreview(for: hidden[1]))
  }

  func testTypingUsersSortAheadOfOtherMessageActivityAndThenSortByRecency() {
    let users = [
      makeUser(id: "typing", firstName: "Typing"),
      makeUser(id: "unread", firstName: "Unread"),
      makeUser(id: "recent", firstName: "Recent"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: ["typing"],
      unreadChatUserIds: ["unread"],
      chatPreviewsByUserId: [
        "typing": FriendCardMessagePreview(
          text: "Typing…",
          timestamp: Date(timeIntervalSince1970: 1_700_000_100),
          state: .incomingOpened
        ),
        "unread": FriendCardMessagePreview(
          text: "Unread",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingUnread
        ),
        "recent": FriendCardMessagePreview(
          text: "Recent",
          timestamp: Date(timeIntervalSince1970: 1_700_000_400),
          state: .incomingOpened
        ),
      ],
      shiftPreviews: [:],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(ordering.sortedSharers(users).map(\.id), ["typing", "recent", "unread"])
  }

  func testCalendarAvailabilityHidesChatOnlyUsers() {
    XCTAssertFalse(
      FriendCalendarAvailability.isAvailable(
        sharerId: "chat-only",
        chatOnlyUserIds: ["chat-only"],
        preview: makeShiftPreview(
          sharerId: "chat-only",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        )
      )
    )
  }

  func testCalendarAvailabilityRequiresSharedCalendarContent() {
    XCTAssertFalse(
      FriendCalendarAvailability.isAvailable(
        sharerId: "empty",
        chatOnlyUserIds: [],
        preview: SharerShiftPreview(
          sharerId: "empty",
          shift: nil,
          status: nil,
          showEarnings: false,
          currency: nil,
          hasSharedCalendarContent: false
        )
      )
    )
  }

  func testCalendarAvailabilityAllowsSharerWithConfiguredContentWithoutPreviewShift() {
    XCTAssertTrue(
      FriendCalendarAvailability.isAvailable(
        sharerId: "configured",
        chatOnlyUserIds: [],
        preview: SharerShiftPreview(
          sharerId: "configured",
          shift: nil,
          status: nil,
          showEarnings: false,
          currency: nil,
          hasSharedCalendarContent: true
        )
      )
    )
  }

  func testCalendarAvailabilityDoesNotTreatPayrollOnlyConfigurationAsCalendarContent() {
    XCTAssertFalse(
      FriendCalendarAvailability.isAvailable(
        sharerId: "payroll-only",
        chatOnlyUserIds: [],
        preview: SharerShiftPreview(
          sharerId: "payroll-only",
          shift: nil,
          status: nil,
          showEarnings: false,
          currency: nil,
          hasSharedCalendarContent: false
        )
      )
    )
  }

  func testSendAttachmentRecipientOrderingPrefersMostRecentDirectThread() {
    let recipients = [
      ShareRecipient(
        id: "older",
        displayName: "Older",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      ),
      ShareRecipient(
        id: "no-thread",
        displayName: "No Thread",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      ),
      ShareRecipient(
        id: "newer",
        displayName: "Newer",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      ),
    ]

    let threads = [
      FriendThread(
        id: "thread-older",
        kind: .direct,
        title: nil,
        avatarUrl: nil,
        metadataData: nil,
        counterpartUserId: "older",
        counterpartDisplayName: "Older",
        counterpartProfilePictureUrl: nil,
        counterpartOAuthAvatarUrl: nil,
        lastMessageId: "message-older",
        lastMessageSenderId: "viewer",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_100),
        lastMessageBody: "Older",
        lastMessageHasImage: false,
        unreadCount: 0,
        muted: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      FriendThread(
        id: "thread-newer",
        kind: .direct,
        title: nil,
        avatarUrl: nil,
        metadataData: nil,
        counterpartUserId: "newer",
        counterpartDisplayName: "Newer",
        counterpartProfilePictureUrl: nil,
        counterpartOAuthAvatarUrl: nil,
        lastMessageId: "message-newer",
        lastMessageSenderId: "viewer",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_300),
        lastMessageBody: "Newer",
        lastMessageHasImage: false,
        unreadCount: 0,
        muted: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_200)
      ),
    ]

    XCTAssertEqual(
      SendAttachmentRecipientOrdering.sortedRecipients(recipients, threads: threads).map(\.id),
      ["newer", "older", "no-thread"]
    )
  }

  func testSendAttachmentRecipientResolverFallsBackToLocalThreadsAndCachedFriends() {
    let cachedFriends = SharedShiftsRepository.CachedFriendsSnapshot(
      sharers: [
        SharedUser(
          id: "cached-friend",
          email: "cached@example.com",
          phone: nil,
          firstName: "Cached",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharedAt: "2026-03-01",
          showEarnings: false,
          hidden: false
        )
      ],
      chatOnlyUserIds: ["cached-friend"]
    )
    let threads = [
      FriendThread(
        id: "thread-chat",
        kind: .direct,
        title: nil,
        avatarUrl: nil,
        metadataData: nil,
        counterpartUserId: "thread-friend",
        counterpartDisplayName: "Thread Friend",
        counterpartProfilePictureUrl: nil,
        counterpartOAuthAvatarUrl: nil,
        lastMessageId: "message-thread",
        lastMessageSenderId: "viewer",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_400),
        lastMessageBody: "Latest",
        lastMessageHasImage: false,
        unreadCount: 0,
        muted: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_300)
      )
    ]

    XCTAssertEqual(
      SendAttachmentRecipientResolver
        .mergedRecipients(
          fetchedRecipients: [],
          cachedFriends: cachedFriends,
          threads: threads,
          includeLocalFallbacks: true
        )
        .map(\.id),
      ["thread-friend", "cached-friend"]
    )
  }

  func testSendAttachmentRecipientResolverKeepsFetchedRecipientsAuthoritativeWhenAvailable() {
    let cachedFriends = SharedShiftsRepository.CachedFriendsSnapshot(
      sharers: [
        SharedUser(
          id: "cached-friend",
          email: "cached@example.com",
          phone: nil,
          firstName: "Cached",
          profilePictureUrl: nil,
          oauthAvatarUrl: nil,
          sharedAt: "2026-03-01",
          showEarnings: false,
          hidden: false
        )
      ],
      chatOnlyUserIds: []
    )
    let fetchedRecipients = [
      ShareRecipient(
        id: "server-friend",
        displayName: "Server Friend",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: true
      )
    ]
    let threads = [
      FriendThread(
        id: "thread-chat",
        kind: .direct,
        title: nil,
        avatarUrl: nil,
        metadataData: nil,
        counterpartUserId: "thread-friend",
        counterpartDisplayName: "Thread Friend",
        counterpartProfilePictureUrl: nil,
        counterpartOAuthAvatarUrl: nil,
        lastMessageId: "message-thread",
        lastMessageSenderId: "viewer",
        lastMessageAt: Date(timeIntervalSince1970: 1_700_000_400),
        lastMessageBody: "Latest",
        lastMessageHasImage: false,
        unreadCount: 0,
        muted: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_300)
      )
    ]

    XCTAssertEqual(
      SendAttachmentRecipientResolver
        .mergedRecipients(
          fetchedRecipients: fetchedRecipients,
          cachedFriends: cachedFriends,
          threads: threads,
          includeLocalFallbacks: false
        )
        .map(\.id),
      ["server-friend"]
    )
  }

  private func makeUser(id: String, firstName: String, hidden: Bool = false) -> SharedUser {
    SharedUser(
      id: id,
      email: nil,
      phone: nil,
      firstName: firstName,
      profilePictureUrl: nil,
      oauthAvatarUrl: nil,
      sharedAt: "2026-03-01",
      showEarnings: false,
      hidden: hidden
    )
  }

  private func makeShiftPreview(
    sharerId: String,
    shiftDate: String,
    startTime: String,
    endTime: String,
    status: ShiftPreviewStatus
  ) -> SharerShiftPreview {
    SharerShiftPreview(
      sharerId: sharerId,
      shift: SharedShiftData(
        id: "\(sharerId)-shift",
        user_id: sharerId,
        job_id: nil,
        job_name: nil,
        job_color: nil,
        shift_date: shiftDate,
        start_time: startTime,
        end_time: endTime,
        computed: SharedShiftComputed(
          id: "\(sharerId)-shift",
          durationHours: 8,
          paidHours: 8,
          basePay: 0,
          supplementPay: 0,
          gross: 0
        ),
        tax_enabled: nil,
        tax_percentage: nil,
        custom_supplements: nil,
        recurring_id: nil,
        recurring_anchor_weekday: nil
      ),
      status: status,
      showEarnings: false,
      currency: nil
    )
  }
}
