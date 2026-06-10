import Nimble
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
      bottomedUserIds: [],
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
      bottomedUserIds: [],
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

  func testHiddenUserWithUnreadMessageTemporarilyAppearsInVisibleFeed() {
    let visible = [
      makeUser(id: "visible", firstName: "Visible", hidden: false)
    ]
    let hidden = [
      makeUser(id: "hidden-chat", firstName: "Hidden Chat", hidden: true),
      makeUser(id: "hidden-shift", firstName: "Hidden Shift", hidden: true),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: ["hidden-shift"],
      unreadChatUserIds: ["hidden-chat"],
      bottomedUserIds: [],
      chatPreviewsByUserId: [
        "hidden-chat": FriendCardMessagePreview(
          text: "Hey",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingUnread
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
  }

  func testHiddenUserWithOpenedMessageStaysOutOfVisibleFeed() {
    let visible = [
      makeUser(id: "visible", firstName: "Visible", hidden: false)
    ]
    let hidden = [
      makeUser(id: "hidden-chat", firstName: "Hidden Chat", hidden: true)
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: [],
      bottomedUserIds: [],
      chatPreviewsByUserId: [
        "hidden-chat": FriendCardMessagePreview(
          text: "Hey",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingOpened
        )
      ],
      shiftPreviews: [:],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(
      ordering.visibleSharers(visible: visible, hidden: hidden).map(\.id),
      ["visible"]
    )
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
      bottomedUserIds: [],
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

  func testBottomedMessageActiveFriendSortsBelowNonBottomedUsers() {
    let users = [
      makeUser(id: "bottomed", firstName: "Bottomed"),
      makeUser(id: "recent", firstName: "Recent"),
      makeUser(id: "shift", firstName: "Shift"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: ["bottomed"],
      bottomedUserIds: ["bottomed"],
      chatPreviewsByUserId: [
        "bottomed": FriendCardMessagePreview(
          text: "Unread",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingUnread
        ),
        "recent": FriendCardMessagePreview(
          text: "Seen",
          timestamp: Date(timeIntervalSince1970: 1_700_000_200),
          state: .incomingOpened
        ),
      ],
      shiftPreviews: [
        "shift": makeShiftPreview(
          sharerId: "shift",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        )
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(ordering.sortedSharers(users).map(\.id), ["recent", "shift", "bottomed"])
  }

  func testBottomedTypingFriendSortsWithActiveTypingUsers() {
    let users = [
      makeUser(id: "bottomed-typing", firstName: "Bottomed Typing"),
      makeUser(id: "recent", firstName: "Recent"),
      makeUser(id: "shift", firstName: "Shift"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: ["bottomed-typing"],
      unreadChatUserIds: [],
      bottomedUserIds: ["bottomed-typing"],
      chatPreviewsByUserId: [
        "bottomed-typing": FriendCardMessagePreview(
          text: "Typing...",
          timestamp: Date(timeIntervalSince1970: 1_700_000_100),
          state: .incomingOpened
        ),
        "recent": FriendCardMessagePreview(
          text: "Seen",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingOpened
        ),
      ],
      shiftPreviews: [
        "shift": makeShiftPreview(
          sharerId: "shift",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
        )
      ],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(ordering.sortedSharers(users).map(\.id), ["bottomed-typing", "recent", "shift"])
  }

  func testBottomedStateDoesNotDisturbNonBottomedOrdering() {
    let users = [
      makeUser(id: "older", firstName: "Older"),
      makeUser(id: "bottomed", firstName: "Bottomed"),
      makeUser(id: "newer", firstName: "Newer"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: [],
      bottomedUserIds: ["bottomed"],
      chatPreviewsByUserId: [
        "older": FriendCardMessagePreview(
          text: "Older",
          timestamp: Date(timeIntervalSince1970: 1_700_000_100),
          state: .incomingOpened
        ),
        "bottomed": FriendCardMessagePreview(
          text: "Bottomed",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingOpened
        ),
        "newer": FriendCardMessagePreview(
          text: "Newer",
          timestamp: Date(timeIntervalSince1970: 1_700_000_200),
          state: .incomingOpened
        ),
      ],
      shiftPreviews: [:],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(ordering.sortedSharers(users).map(\.id), ["newer", "older", "bottomed"])
  }

  func testMultipleBottomedUsersKeepExistingRelativeOrdering() {
    let users = [
      makeUser(id: "bottomed-older", firstName: "Bottomed Older"),
      makeUser(id: "normal", firstName: "Normal"),
      makeUser(id: "bottomed-newer", firstName: "Bottomed Newer"),
    ]

    let ordering = FriendsListOrdering(
      typingUserIds: [],
      unreadChatUserIds: [],
      bottomedUserIds: ["bottomed-older", "bottomed-newer"],
      chatPreviewsByUserId: [
        "bottomed-older": FriendCardMessagePreview(
          text: "Older",
          timestamp: Date(timeIntervalSince1970: 1_700_000_100),
          state: .incomingOpened
        ),
        "normal": FriendCardMessagePreview(
          text: "Normal",
          timestamp: Date(timeIntervalSince1970: 1_700_000_150),
          state: .incomingOpened
        ),
        "bottomed-newer": FriendCardMessagePreview(
          text: "Newer",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingOpened
        ),
      ],
      shiftPreviews: [:],
      isLoadingShiftPreviews: false
    )

    XCTAssertEqual(
      ordering.sortedSharers(users).map(\.id),
      ["normal", "bottomed-newer", "bottomed-older"]
    )
  }

  func testHiddenMessageUserIsNotBottomedIntoVisibleFeed() {
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
      bottomedUserIds: ["hidden-chat"],
      chatPreviewsByUserId: [
        "hidden-chat": FriendCardMessagePreview(
          text: "Hey",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          state: .incomingOpened
        )
      ],
      shiftPreviews: [
        "visible": makeShiftPreview(
          sharerId: "visible",
          shiftDate: "2026-03-18",
          startTime: "08:00",
          endTime: "16:00",
          status: .active
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
      ["visible"]
    )
  }

  func testCalendarAvailabilityHidesChatOnlyUsers() {
    XCTAssertFalse(
      FriendCalendarAvailability.isAvailable(
        sharer: makeUser(id: "chat-only", firstName: "Chat Only", hasSharedCalendarContent: true),
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
        sharer: makeUser(id: "empty", firstName: "Empty", hasSharedCalendarContent: false),
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

  func testCalendarAvailabilityAllowsSharerWithHistoricShiftContentOutsidePreviewWindow() {
    XCTAssertTrue(
      FriendCalendarAvailability.isAvailable(
        sharer: makeUser(
          id: "historic",
          firstName: "Historic",
          hasSharedCalendarContent: true
        ),
        chatOnlyUserIds: [],
        preview: SharerShiftPreview(
          sharerId: "historic",
          shift: nil,
          status: nil,
          showEarnings: false,
          currency: nil,
          hasSharedCalendarContent: false
        )
      )
    )
  }

  func testInitialMonthResolverUsesPreviewShiftMonthWhenAvailable() {
    let sharer = makeUser(id: "preview", firstName: "Preview")

    XCTAssertEqual(
      FriendInitialMonthResolver.targetYearMonth(
        sharer: sharer,
        preview: makeShiftPreview(
          sharerId: "preview",
          shiftDate: "2025-08-12",
          startTime: "08:00",
          endTime: "16:00",
          status: .past
        ),
        current: (year: 2_026, month: 4)
      )?.year,
      2_025
    )
    XCTAssertEqual(
      FriendInitialMonthResolver.targetYearMonth(
        sharer: sharer,
        preview: makeShiftPreview(
          sharerId: "preview",
          shiftDate: "2025-08-12",
          startTime: "08:00",
          endTime: "16:00",
          status: .past
        ),
        current: (year: 2_026, month: 4)
      )?.month,
      8
    )
  }

  func testInitialMonthResolverFallsBackToLatestHistoricShiftMonth() {
    let sharer = makeUser(
      id: "historic-month",
      firstName: "Historic Month",
      hasSharedCalendarContent: true,
      latestSharedShiftDate: "2025-08-19",
      hasRecurringSharedShifts: false
    )

    let targetMonth = FriendInitialMonthResolver.targetYearMonth(
      sharer: sharer,
      preview: nil,
      current: (year: 2_026, month: 4)
    )

    expect(targetMonth?.year) == 2_025
    XCTAssertEqual(targetMonth?.month, 8)
  }

  func testInitialMonthResolverKeepsCurrentMonthForRecurringOnlySharer() {
    let sharer = makeUser(
      id: "recurring",
      firstName: "Recurring",
      hasSharedCalendarContent: true,
      latestSharedShiftDate: nil,
      hasRecurringSharedShifts: true
    )

    XCTAssertNil(
      FriendInitialMonthResolver.targetYearMonth(
        sharer: sharer,
        preview: nil,
        current: (year: 2_026, month: 4)
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

  func testShareExtensionRecipientOrderingMatchesFeedMessageThenShiftFallback() {
    let recipients = [
      ShareRecipient(
        id: "active-shift",
        displayName: "Active Shift",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      ),
      ShareRecipient(
        id: "older-thread",
        displayName: "Older Thread",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      ),
      ShareRecipient(
        id: "newer-thread",
        displayName: "Newer Thread",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      ),
      ShareRecipient(
        id: "no-activity",
        displayName: "No Activity",
        avatarURL: nil,
        statusText: nil,
        canSeeOwnerEarnings: false
      ),
    ]

    let ordered = ShareRecipientFeedOrdering.sortedRecipients(
      recipients,
      threads: [
        ShareRecipientThreadSummary(
          counterpartUserId: "older-thread",
          timestamp: Date(timeIntervalSince1970: 1_700_000_100),
          hasUnread: true
        ),
        ShareRecipientThreadSummary(
          counterpartUserId: "newer-thread",
          timestamp: Date(timeIntervalSince1970: 1_700_000_300),
          hasUnread: false
        ),
      ],
      shiftPreviews: [
        "active-shift": SharingComputedPreview(
          sharerId: "active-shift",
          shift: nil,
          status: .active,
          showEarnings: false
        )
      ]
    )

    XCTAssertEqual(
      ordered.map(\.id),
      ["newer-thread", "older-thread", "active-shift", "no-activity"]
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

  private func makeUser(
    id: String,
    firstName: String,
    hidden: Bool = false,
    hasSharedCalendarContent: Bool = false,
    latestSharedShiftDate: String? = nil,
    hasRecurringSharedShifts: Bool = false
  ) -> SharedUser {
    SharedUser(
      id: id,
      email: nil,
      phone: nil,
      firstName: firstName,
      profilePictureUrl: nil,
      oauthAvatarUrl: nil,
      sharedAt: "2026-03-01",
      showEarnings: false,
      hidden: hidden,
      hasSharedCalendarContent: hasSharedCalendarContent,
      latestSharedShiftDate: latestSharedShiftDate,
      hasRecurringSharedShifts: hasRecurringSharedShifts
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
          gross: 0,
          breakAudit: SharedBreakAudit(
            method: .none,
            thresholdHours: 0,
            deductedHours: 0,
            source: .none,
            appliedPauseWindows: nil,
            notes: []
          )
        ),
        tax_enabled: nil,
        tax_percentage: nil,
        custom_pause_windows: nil,
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

final class FriendSharingRemovalActionTests: XCTestCase {
  func testAvailableActionsMatchRelationshipDirection() {
    XCTAssertEqual(
      FriendSharingRemovalAction.availableActions(for: .mutual),
      [.stopSharingMyShifts, .stopSeeingTheirShifts]
    )
    XCTAssertEqual(
      FriendSharingRemovalAction.availableActions(for: .outgoing),
      [.stopSharingMyShifts]
    )
    XCTAssertEqual(
      FriendSharingRemovalAction.availableActions(for: .incoming),
      [.stopSeeingTheirShifts]
    )
  }

  func testRelationshipStatusCopyMatchesDirection() {
    XCTAssertEqual(
      FriendSectionType.mutual.relationshipStatus,
      String(localized: .sharingRelationshipMutual)
    )
    XCTAssertEqual(
      FriendSectionType.outgoing.relationshipStatus,
      String(localized: .sharingRelationshipOutgoingOnly)
    )
    XCTAssertEqual(
      FriendSectionType.incoming.relationshipStatus,
      String(localized: .sharingRelationshipIncomingOnly)
    )
  }
}  // swiftlint:disable:this file_length
